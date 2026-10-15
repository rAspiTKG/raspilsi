//=============================================================================
// ahb_smp_mgr.sv
//-----------------------------------------------------------------------------
//  ahb_if のサンプル : AHB マネージャ (合成可能)。
//  start を受けると、下の表 (op) の転送をパイプラインで出し、読み出しデータと応答を照合する。
//    - サブオーディネート 0 (0x0000〜) : INCR4 の書き込み -> INCR4 の読み出し -> WRAP4 の読み出し
//    - サブオーディネート 1 (0x1000〜) : ワードの書き込み / 読み出し、ハーフワードの書き込み
//    - どこにもつながっていないアドレス (0x2000) の読み出しは ERROR が返ること
//  done は 1 サイクル。err は照合が合わないと 1 (次の start まで保持)。
//
//  ポートは ahb_if.mgr 1 本だけ。HWDATA / HWSTRB はデータフェーズの転送の値を出す。
//=============================================================================
`timescale 1ns / 1ps

module ahb_smp_mgr #(
  parameter int unsigned ADDR_WIDTH  = 32
 ,parameter int unsigned DATA_WIDTH  = 32     // 32 だけ (表のデータが 32 ビット)
 ,parameter int unsigned HPROT_WIDTH = 4
) (
  input  logic hclk
 ,input  logic hresetn
 ,input  logic start
 ,output logic busy
 ,output logic done
 ,output logic err
 ,ahb_if.mgr   m_ahb
);

  // つないだ ahb_if の幅がこのモジュールの parameter と同じか (違えばエラボレーションで止める)
  if( ($bits(m_ahb.haddr)!=ADDR_WIDTH)||($bits(m_ahb.hwdata)!=DATA_WIDTH)||($bits(m_ahb.hprot)!=HPROT_WIDTH) ) begin : g_chk_if
    $error("ahb_smp_mgr : ADDR_WIDTH / DATA_WIDTH / HPROT_WIDTH differ from the ahb_if connected to m_ahb");
  end

  localparam int unsigned NOP = 17;    // 表の転送の数
  localparam int unsigned OPW = 5;

  if( DATA_WIDTH!=32 ) begin : g_chk_width
    $error("ahb_smp_mgr : DATA_WIDTH must be 32");
  end

  // 転送 1 つ分
  typedef struct packed {
    logic [1:0]  trans;   // NONSEQ / SEQ
    logic [2:0]  burst;
    logic        write;
    logic [2:0]  size;
    logic [31:0] addr;
    logic [31:0] data;    // 書き込みデータ / 読み出しの期待値 (バイトレーンに置いた値)
    logic        experr;  // ERROR 応答を期待する
  } op_t;

  localparam logic [1:0] NONSEQ = 2'b10;
  localparam logic [1:0] SEQ    = 2'b11;
  localparam logic [2:0] SINGLE = 3'b000;
  localparam logic [2:0] WRAP4  = 3'b010;
  localparam logic [2:0] INCR4  = 3'b011;

  function automatic op_t op(input logic [OPW-1:0] i);
    case( i )
      5'd0 : begin
        return '{NONSEQ, INCR4, 1'b1, 3'd2, 32'h0000_0010, 32'hD000_0000, 1'b0};
      end
      5'd1 : begin
        return '{SEQ, INCR4, 1'b1, 3'd2, 32'h0000_0014, 32'hD111_1111, 1'b0};
      end
      5'd2 : begin
        return '{SEQ, INCR4, 1'b1, 3'd2, 32'h0000_0018, 32'hD222_2222, 1'b0};
      end
      5'd3 : begin
        return '{SEQ, INCR4, 1'b1, 3'd2, 32'h0000_001C, 32'hD333_3333, 1'b0};
      end
      5'd4 : begin
        return '{NONSEQ, INCR4, 1'b0, 3'd2, 32'h0000_0010, 32'hD000_0000, 1'b0};
      end
      5'd5 : begin
        return '{SEQ, INCR4, 1'b0, 3'd2, 32'h0000_0014, 32'hD111_1111, 1'b0};
      end
      5'd6 : begin
        return '{SEQ, INCR4, 1'b0, 3'd2, 32'h0000_0018, 32'hD222_2222, 1'b0};
      end
      5'd7 : begin
        return '{SEQ, INCR4, 1'b0, 3'd2, 32'h0000_001C, 32'hD333_3333, 1'b0};
      end
      5'd8 : begin
        return '{NONSEQ, WRAP4, 1'b0, 3'd2, 32'h0000_0018, 32'hD222_2222, 1'b0};
      end
      5'd9 : begin
        return '{SEQ, WRAP4, 1'b0, 3'd2, 32'h0000_001C, 32'hD333_3333, 1'b0};
      end
      5'd10 : begin
        return '{SEQ, WRAP4, 1'b0, 3'd2, 32'h0000_0010, 32'hD000_0000, 1'b0};
      end
      5'd11 : begin
        return '{SEQ, WRAP4, 1'b0, 3'd2, 32'h0000_0014, 32'hD111_1111, 1'b0};
      end
      5'd12 : begin
        return '{NONSEQ, SINGLE, 1'b1, 3'd2, 32'h0000_1020, 32'h1234_5678, 1'b0};
      end
      5'd13 : begin
        return '{NONSEQ, SINGLE, 1'b0, 3'd2, 32'h0000_1020, 32'h1234_5678, 1'b0};
      end
      5'd14 : begin
        return '{NONSEQ, SINGLE, 1'b1, 3'd1, 32'h0000_1022, 32'hBEEF_0000, 1'b0};
      end
      5'd15 : begin
        return '{NONSEQ, SINGLE, 1'b0, 3'd2, 32'h0000_1020, 32'hBEEF_5678, 1'b0};
      end
      default : begin
        return '{NONSEQ, SINGLE, 1'b0, 3'd2, 32'h0000_2000, 32'h0000_0000, 1'b1};
      end
    endcase
  endfunction

  // 書き込みの有効なバイトレーン (HSIZE と HADDR から)
  function automatic logic [3:0] lanes(input logic [2:0] size, input logic [1:0] a);
    case( size )
      3'd0 : begin
        return 4'b0001<<a;
      end
      3'd1 : begin
        return a[1] ? 4'b1100 : 4'b0011;
      end
      default : begin
        return 4'b1111;
      end
    endcase
  endfunction

  logic           ap_v_q;   // アドレスフェーズに転送を出している
  logic [OPW-1:0] ap_i_q;
  logic           dp_v_q;   // データフェーズの転送がある
  logic [OPW-1:0] dp_i_q;
  logic           done_q;
  logic           err_q;
  op_t            ap;
  op_t            dp;

  assign ap = op(ap_i_q);
  assign dp = op(dp_i_q);

  always @(posedge hclk or negedge hresetn) begin
    if( !hresetn ) begin
      ap_v_q <= 1'b0;
      ap_i_q <= '0;
      dp_v_q <= 1'b0;
      dp_i_q <= '0;
      done_q <= 1'b0;
      err_q  <= 1'b0;
    end else begin
      done_q <= 1'b0;
      if( start&&!ap_v_q&&!dp_v_q ) begin
        ap_v_q <= 1'b1;
        ap_i_q <= '0;
        err_q  <= 1'b0;
      end else if( m_ahb.hready ) begin
        // データフェーズの転送が終わった
        if( dp_v_q ) begin
          if( m_ahb.hresp!=dp.experr ) begin
            err_q <= 1'b1;
          end
          if( !dp.write&&!dp.experr&&(m_ahb.hrdata!=dp.data) ) begin
            err_q <= 1'b1;
          end
          if( 32'(dp_i_q)==NOP-1 ) begin
            done_q <= 1'b1;
          end
        end
        // アドレスフェーズの転送を受け付けた
        dp_v_q <= ap_v_q;
        dp_i_q <= ap_i_q;
        if( ap_v_q ) begin
          ap_i_q <= ap_i_q+1'b1;
          if( 32'(ap_i_q)==NOP-1 ) begin
            ap_v_q <= 1'b0;
          end
        end
      end
    end
  end

  //---------------------------------------------------------------------------
  // AHB の出力
  //---------------------------------------------------------------------------
  assign m_ahb.haddr     = ADDR_WIDTH'(ap.addr);
  assign m_ahb.htrans    = ap_v_q ? ap.trans : 2'b00;
  assign m_ahb.hwrite    = ap.write;
  assign m_ahb.hsize     = ap.size;
  assign m_ahb.hburst    = ap.burst;
  assign m_ahb.hprot     = HPROT_WIDTH'(4'b0011);
  assign m_ahb.hnonsec   = 1'b0;
  assign m_ahb.hexcl     = 1'b0;
  assign m_ahb.hmaster   = '0;
  assign m_ahb.hmastlock = 1'b0;
  assign m_ahb.hwdata    = DATA_WIDTH'(dp.data);
  assign m_ahb.hwstrb    = (dp_v_q&&dp.write) ? lanes(dp.size, dp.addr[1:0]) : 4'b0000;

  assign busy = ap_v_q||dp_v_q;
  assign done = done_q;
  assign err  = err_q;

  // 使わない入力と、表の中で使わないフィールド
  wire unused_ok = &{1'b0, m_ahb.hexokay, ap.data, ap.experr, dp.trans, dp.burst};

endmodule
