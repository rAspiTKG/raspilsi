//=============================================================================
// apb_smp_req.sv
//-----------------------------------------------------------------------------
//  apb_if のサンプル : APB リクエスタ (合成可能)。NSEL 個のコンプリータに apb_if の配列でつなぐ。
//    - コンプリータ i は i * 2^SEL_BITS から (アドレスの [SEL_BITS +: log2(NSEL)] で PSEL を選ぶ)
//    - start を受けると、下の表 (op) の転送を順に行い、読み出しデータと PSLVERR を照合する
//      (コンプリータ 0 / 1 への書き込みと読み出し、PSTRB の一部だけの書き込み、
//       存在しないレジスタの読み出しで PSLVERR が返ること)
//    - 転送の間に IDLE を挟まず、ACCESS の次のサイクルを次の転送の SETUP にする
//    - PADDR / PWRITE / PWDATA / PSTRB / PPROT / PENABLE は全てのリンクに同じものを出し、
//      PSEL だけをリンクごとに出す
//  done は 1 サイクル。err は照合が合わないと 1 (次の start まで保持)。
//=============================================================================
`timescale 1ns / 1ps

module apb_smp_req #(
  parameter int unsigned ADDR_WIDTH = 32
 ,parameter int unsigned DATA_WIDTH = 32      // 32 だけ (表のデータが 32 ビット)
 ,parameter int unsigned NSEL       = 2       // 2 以上
 ,parameter int unsigned SEL_BITS   = 12
) (
  input  logic pclk
 ,input  logic presetn
 ,input  logic start
 ,output logic busy
 ,output logic done
 ,output logic err
 ,apb_if.req   m_apb [NSEL]
);

`ifndef SYNTHESIS
  // つないだ apb_if の幅がこのモジュールの parameter と同じか。interface の配列のポートなので、シミュレーションの
  // 開始時に確かめる (Verilator 5.052 は配列のポートの幅を、エラボレーションの時点では interface の既定の
  // parameter で計算するため、generate の if では正しく比べられない)
  initial begin
    if( ($bits(m_apb[0].paddr)!=ADDR_WIDTH)||($bits(m_apb[0].pwdata)!=DATA_WIDTH) ) begin
      $fatal(1, "apb_smp_req : ADDR_WIDTH / DATA_WIDTH differ from the apb_if connected to m_apb");
    end
  end
`endif

  localparam int unsigned SELW = $clog2(NSEL);
  localparam int unsigned NOP  = 9;
  localparam int unsigned OPW  = 4;

  if( DATA_WIDTH!=32 ) begin : g_chk_width
    $error("apb_smp_req : DATA_WIDTH must be 32");
  end

  typedef struct packed {
    logic        write;
    logic [31:0] addr;
    logic [31:0] data;     // 書き込みデータ / 読み出しの期待値
    logic [3:0]  strb;
    logic        experr;   // PSLVERR を期待する
  } op_t;

  function automatic op_t op(input logic [OPW-1:0] i);
    case( i )
      4'd0 : begin
        return '{1'b1, 32'h0000_0000, 32'h1111_0000, 4'hF, 1'b0};
      end
      4'd1 : begin
        return '{1'b1, 32'h0000_0004, 32'h1111_0004, 4'hF, 1'b0};
      end
      4'd2 : begin
        return '{1'b1, 32'h0000_1000, 32'h2222_1000, 4'hF, 1'b0};
      end
      4'd3 : begin
        return '{1'b1, 32'h0000_1004, 32'h2222_1004, 4'h3, 1'b0};
      end
      4'd4 : begin
        return '{1'b0, 32'h0000_0000, 32'h1111_0000, 4'h0, 1'b0};
      end
      4'd5 : begin
        return '{1'b0, 32'h0000_0004, 32'h1111_0004, 4'h0, 1'b0};
      end
      4'd6 : begin
        return '{1'b0, 32'h0000_1000, 32'h2222_1000, 4'h0, 1'b0};
      end
      4'd7 : begin
        return '{1'b0, 32'h0000_1004, 32'h0000_1004, 4'h0, 1'b0};
      end
      default : begin
        return '{1'b0, 32'h0000_1040, 32'h0000_0000, 4'h0, 1'b1};
      end
    endcase
  endfunction

  typedef enum logic [1:0] {
    S_IDLE
   ,S_SETUP
   ,S_ACCESS
  } st_t;

  st_t                   st_q;
  logic [OPW-1:0]        op_q;
  logic                  done_q;
  logic                  err_q;
  op_t                   cur;
  logic [SELW-1:0]       sel;
  logic [NSEL-1:0]       sel_ready;
  logic [NSEL-1:0]       sel_slverr;
  logic [DATA_WIDTH-1:0] sel_rdata [NSEL];
  logic                  ready;
  logic                  slverr;
  logic [DATA_WIDTH-1:0] rdata;

  assign cur    = op(op_q);
  assign sel    = cur.addr[SEL_BITS+:SELW];
  assign ready  = sel_ready[sel];
  assign slverr = sel_slverr[sel];
  assign rdata  = sel_rdata[sel];

  always @(posedge pclk or negedge presetn) begin
    if( !presetn ) begin
      st_q   <= S_IDLE;
      op_q   <= '0;
      done_q <= 1'b0;
      err_q  <= 1'b0;
    end else begin
      done_q <= 1'b0;
      case( st_q )
        S_IDLE : begin
          if( start ) begin
            op_q  <= '0;
            err_q <= 1'b0;
            st_q  <= S_SETUP;
          end
        end
        S_SETUP : begin
          st_q <= S_ACCESS;
        end
        S_ACCESS : begin
          if( ready ) begin
            if( slverr!=cur.experr ) begin
              err_q <= 1'b1;
            end
            if( !cur.write&&!cur.experr&&(rdata!=cur.data) ) begin
              err_q <= 1'b1;
            end
            if( 32'(op_q)==NOP-1 ) begin
              done_q <= 1'b1;
              st_q   <= S_IDLE;
            end else begin
              op_q <= op_q+1'b1;
              st_q <= S_SETUP;
            end
          end
        end
        default : begin
          st_q <= S_IDLE;
        end
      endcase
    end
  end

  //---------------------------------------------------------------------------
  // APB の出力 (PSEL だけリンクごと)
  //---------------------------------------------------------------------------
  for( genvar i=0; i<NSEL; i++ ) begin : g_sel
    assign m_apb[i].psel    = (st_q!=S_IDLE)&&(sel==SELW'(i));
    assign m_apb[i].penable = (st_q==S_ACCESS);
    assign m_apb[i].paddr   = ADDR_WIDTH'(cur.addr);
    assign m_apb[i].pwrite  = cur.write;
    assign m_apb[i].pwdata  = cur.data;
    assign m_apb[i].pstrb   = cur.write ? cur.strb : 4'h0;
    assign m_apb[i].pprot   = 3'b000;
    assign sel_ready[i]     = m_apb[i].pready;
    assign sel_slverr[i]    = m_apb[i].pslverr;
    assign sel_rdata[i]     = m_apb[i].prdata;
  end

  assign busy = (st_q!=S_IDLE);
  assign done = done_q;
  assign err  = err_q;

endmodule
