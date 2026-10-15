//=============================================================================
// axi4_smp_mgr.sv
//-----------------------------------------------------------------------------
//  axi4_if のサンプル : AXI4 マネージャ (合成可能)。
//  start を受けると次を順に行い、読み出したデータを照合する。
//    1. BASE_ADDR から NBEAT ビートの INCR 書き込み (データ幅いっぱい)
//    2. BASE_ADDR から NBEAT ビートの INCR 読み出し
//    3. BASE_ADDR + 2 ワードから 4 ビートの WRAP 読み出し (2, 3, 0, 1 ワード目の順に返る)
//  done は 1 サイクル。err は応答が OKAY でない / データが違うと 1 (次の start まで保持)。
//
//  ポートは axi4_if.mgr 1 本だけ (個別の m_axi_* は書かない)。
//=============================================================================
`timescale 1ns / 1ps

module axi4_smp_mgr #(
  parameter int unsigned     ADDR_WIDTH = 32
 ,parameter int unsigned     DATA_WIDTH = 64
 ,parameter int unsigned     ID_WIDTH   = 4
 ,parameter int unsigned     AXI_ID     = 0
 ,parameter longint unsigned BASE_ADDR  = 64'h0000_0100  // 4 ワード (4 * DATA_WIDTH/8 バイト) にアライン
 ,parameter int unsigned     NBEAT      = 8              // 4〜256 (4KB 境界をまたがないこと)
) (
  input  logic aclk
 ,input  logic aresetn
 ,input  logic start
 ,output logic busy
 ,output logic done
 ,output logic err
 ,axi4_if.mgr  m_axi
);

  // つないだ axi4_if の幅がこのモジュールの parameter と同じか (違えばエラボレーションで止める)
  if( ($bits(m_axi.awaddr)!=ADDR_WIDTH)||($bits(m_axi.wdata)!=DATA_WIDTH)||($bits(m_axi.awid)!=ID_WIDTH) ) begin : g_chk_if
    $error("axi4_smp_mgr : ADDR_WIDTH / DATA_WIDTH / ID_WIDTH differ from the axi4_if connected to m_axi");
  end

  localparam int unsigned STRB_WIDTH = DATA_WIDTH/8;
  localparam int unsigned OFSW       = $clog2(STRB_WIDTH);

  typedef enum logic [2:0] {
    S_IDLE
   ,S_WRITE
   ,S_BRESP
   ,S_READ
   ,S_RDATA
  } st_t;

  st_t        st_q;
  logic       wrap_q;     // 0 : INCR の読み出し / 1 : WRAP の読み出し
  logic       awvalid_q;
  logic       wvalid_q;
  logic [8:0] wcnt_q;     // 送った W のビート数
  logic       arvalid_q;
  logic [8:0] rcnt_q;     // 受け取った R のビート数
  logic       done_q;
  logic       err_q;

  // i ワード目に書くデータ (バイトごとに違う値)
  function automatic logic [DATA_WIDTH-1:0] pat(input logic [7:0] i);
    logic [DATA_WIDTH-1:0] d;
    for( int k=0; k<STRB_WIDTH; k++ ) begin
      d[8*k+:8] = (i*8'(STRB_WIDTH)+8'(k))^8'hA5;
    end
    return d;
  endfunction

  // 読み出しの rcnt_q ビート目の期待値
  function automatic logic [DATA_WIDTH-1:0] exp_rd(input logic wrap, input logic [8:0] n);
    if( wrap ) begin
      return pat(8'((n+9'd2)&9'd3));
    end else begin
      return pat(n[7:0]);
    end
  endfunction

  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      st_q      <= S_IDLE;
      wrap_q    <= 1'b0;
      awvalid_q <= 1'b0;
      wvalid_q  <= 1'b0;
      wcnt_q    <= '0;
      arvalid_q <= 1'b0;
      rcnt_q    <= '0;
      done_q    <= 1'b0;
      err_q     <= 1'b0;
    end else begin
      done_q <= 1'b0;
      case( st_q )
        S_IDLE : begin
          if( start ) begin
            err_q     <= 1'b0;
            awvalid_q <= 1'b1;
            wvalid_q  <= 1'b1;
            wcnt_q    <= '0;
            st_q      <= S_WRITE;
          end
        end
        S_WRITE : begin
          if( m_axi.awready ) begin
            awvalid_q <= 1'b0;
          end
          if( wvalid_q&&m_axi.wready ) begin
            wcnt_q <= wcnt_q+9'd1;
            if( wcnt_q==9'(NBEAT-1) ) begin
              wvalid_q <= 1'b0;
            end
          end
          // AW と最後の W を送り終えたら B を待つ
          if( (!awvalid_q||m_axi.awready)&&(!wvalid_q||(m_axi.wready&&(wcnt_q==9'(NBEAT-1)))) ) begin
            st_q <= S_BRESP;
          end
        end
        S_BRESP : begin
          if( m_axi.bvalid ) begin
            if( m_axi.bresp!=2'b00 ) begin
              err_q <= 1'b1;
            end
            wrap_q    <= 1'b0;
            arvalid_q <= 1'b1;
            st_q      <= S_READ;
          end
        end
        S_READ : begin
          if( m_axi.arready ) begin
            arvalid_q <= 1'b0;
            rcnt_q    <= '0;
            st_q      <= S_RDATA;
          end
        end
        S_RDATA : begin
          if( m_axi.rvalid ) begin
            rcnt_q <= rcnt_q+9'd1;
            if( (m_axi.rresp!=2'b00)||(m_axi.rdata!=exp_rd(wrap_q,rcnt_q)) ) begin
              err_q <= 1'b1;
            end
            if( m_axi.rlast ) begin
              if( wrap_q ) begin
                done_q <= 1'b1;
                st_q   <= S_IDLE;
              end else begin
                wrap_q    <= 1'b1;
                arvalid_q <= 1'b1;
                st_q      <= S_READ;
              end
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
  // AXI の出力
  //---------------------------------------------------------------------------
  assign m_axi.awid     = ID_WIDTH'(AXI_ID);
  assign m_axi.awaddr   = ADDR_WIDTH'(BASE_ADDR);
  assign m_axi.awlen    = 8'(NBEAT-1);
  assign m_axi.awsize   = 3'(OFSW);
  assign m_axi.awburst  = 2'b01;                 // INCR
  assign m_axi.awlock   = 1'b0;
  assign m_axi.awcache  = 4'b0011;
  assign m_axi.awprot   = 3'b000;
  assign m_axi.awqos    = 4'd0;
  assign m_axi.awregion = 4'd0;
  assign m_axi.awvalid  = awvalid_q;
  assign m_axi.wdata    = pat(wcnt_q[7:0]);
  assign m_axi.wstrb    = '1;
  assign m_axi.wlast    = (wcnt_q==9'(NBEAT-1));
  assign m_axi.wvalid   = wvalid_q;
  assign m_axi.bready   = (st_q==S_BRESP);
  assign m_axi.arid     = ID_WIDTH'(AXI_ID);
  assign m_axi.araddr   = wrap_q ? ADDR_WIDTH'(BASE_ADDR+2*STRB_WIDTH) : ADDR_WIDTH'(BASE_ADDR);
  assign m_axi.arlen    = wrap_q ? 8'd3 : 8'(NBEAT-1);
  assign m_axi.arsize   = 3'(OFSW);
  assign m_axi.arburst  = wrap_q ? 2'b10 : 2'b01; // WRAP / INCR
  assign m_axi.arlock   = 1'b0;
  assign m_axi.arcache  = 4'b0011;
  assign m_axi.arprot   = 3'b000;
  assign m_axi.arqos    = 4'd0;
  assign m_axi.arregion = 4'd0;
  assign m_axi.arvalid  = arvalid_q;
  assign m_axi.rready   = (st_q==S_RDATA);

  assign busy = (st_q!=S_IDLE);
  assign done = done_q;
  assign err  = err_q;

  // 使わない入力 (ID は 1 つだけなので BID / RID は見ない)
  wire unused_ok = &{1'b0, m_axi.bid, m_axi.rid};

endmodule
