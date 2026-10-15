//=============================================================================
// axil_smp_mgr.sv
//-----------------------------------------------------------------------------
//  axil_if のサンプル : AXI4-Lite マネージャ (合成可能)。
//  start を受けると次を順に行い、読み出したデータと応答を照合する。
//    1. BASE_ADDR から NREG 個のレジスタに書く (AW と W は同時に出す)
//    2. 同じレジスタを読み、書いた値と比べる
//    3. 存在しないレジスタ (BASE_ADDR + 4 * NREG) を読み、SLVERR が返ることを確かめる
//  done は 1 サイクル。err は照合が合わないと 1 (次の start まで保持)。
//
//  ポートは axil_if.mgr 1 本だけ。
//=============================================================================
`timescale 1ns / 1ps

module axil_smp_mgr #(
  parameter int unsigned     ADDR_WIDTH = 32
 ,parameter int unsigned     DATA_WIDTH = 32
 ,parameter longint unsigned BASE_ADDR  = 64'h0000_0000
 ,parameter int unsigned     NREG       = 4
) (
  input  logic aclk
 ,input  logic aresetn
 ,input  logic start
 ,output logic busy
 ,output logic done
 ,output logic err
 ,axil_if.mgr  m_axi
);

  // つないだ axil_if の幅がこのモジュールの parameter と同じか (違えばエラボレーションで止める)
  if( ($bits(m_axi.awaddr)!=ADDR_WIDTH)||($bits(m_axi.wdata)!=DATA_WIDTH) ) begin : g_chk_if
    $error("axil_smp_mgr : ADDR_WIDTH / DATA_WIDTH differ from the axil_if connected to m_axi");
  end

  localparam int unsigned STRB_WIDTH = DATA_WIDTH/8;
  localparam int unsigned NOP        = 2*NREG+1;      // 書き込み NREG 回 + 読み出し NREG 回 + 存在しないレジスタ
  localparam int unsigned OPW        = $clog2(NOP+1);

  typedef enum logic [2:0] {
    S_IDLE
   ,S_WRITE
   ,S_BRESP
   ,S_READ
   ,S_RDATA
  } st_t;

  st_t            st_q;
  logic [OPW-1:0] op_q;       // 何番目の操作か
  logic           awvalid_q;
  logic           wvalid_q;
  logic           arvalid_q;
  logic           done_q;
  logic           err_q;

  // 操作 i のレジスタ番号 (書き込み : i、読み出し : i-NREG、最後 : NREG)
  function automatic logic [ADDR_WIDTH-1:0] op_addr(input logic [OPW-1:0] i);
    if( 32'(i)<NREG ) begin
      return ADDR_WIDTH'(BASE_ADDR+4*64'(i));
    end else begin
      return ADDR_WIDTH'(BASE_ADDR+4*(64'(i)-64'(NREG)));
    end
  endfunction

  // レジスタ k に書く値
  function automatic logic [DATA_WIDTH-1:0] pat(input logic [OPW-1:0] k);
    return DATA_WIDTH'(32'h1234_5600+32'(k));
  endfunction

  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      st_q      <= S_IDLE;
      op_q      <= '0;
      awvalid_q <= 1'b0;
      wvalid_q  <= 1'b0;
      arvalid_q <= 1'b0;
      done_q    <= 1'b0;
      err_q     <= 1'b0;
    end else begin
      done_q <= 1'b0;
      case( st_q )
        S_IDLE : begin
          if( start ) begin
            err_q     <= 1'b0;
            op_q      <= '0;
            awvalid_q <= 1'b1;
            wvalid_q  <= 1'b1;
            st_q      <= S_WRITE;
          end
        end
        S_WRITE : begin
          if( m_axi.awready ) begin
            awvalid_q <= 1'b0;
          end
          if( m_axi.wready ) begin
            wvalid_q <= 1'b0;
          end
          if( (!awvalid_q||m_axi.awready)&&(!wvalid_q||m_axi.wready) ) begin
            st_q <= S_BRESP;
          end
        end
        S_BRESP : begin
          if( m_axi.bvalid ) begin
            if( m_axi.bresp!=2'b00 ) begin
              err_q <= 1'b1;
            end
            op_q <= op_q+1'b1;
            if( 32'(op_q)==NREG-1 ) begin
              arvalid_q <= 1'b1;
              st_q      <= S_READ;
            end else begin
              awvalid_q <= 1'b1;
              wvalid_q  <= 1'b1;
              st_q      <= S_WRITE;
            end
          end
        end
        S_READ : begin
          if( m_axi.arready ) begin
            arvalid_q <= 1'b0;
            st_q      <= S_RDATA;
          end
        end
        S_RDATA : begin
          if( m_axi.rvalid ) begin
            if( 32'(op_q)==NOP-1 ) begin
              // 存在しないレジスタ : SLVERR が返ること
              if( m_axi.rresp!=2'b10 ) begin
                err_q <= 1'b1;
              end
              done_q <= 1'b1;
              st_q   <= S_IDLE;
            end else begin
              if( (m_axi.rresp!=2'b00)||(m_axi.rdata!=pat(OPW'(32'(op_q)-NREG))) ) begin
                err_q <= 1'b1;
              end
              op_q      <= op_q+1'b1;
              arvalid_q <= 1'b1;
              st_q      <= S_READ;
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
  // AXI4-Lite の出力
  //---------------------------------------------------------------------------
  assign m_axi.awaddr  = op_addr(op_q);
  assign m_axi.awprot  = 3'b000;
  assign m_axi.awvalid = awvalid_q;
  assign m_axi.wdata   = pat(op_q);
  assign m_axi.wstrb   = {STRB_WIDTH{1'b1}};
  assign m_axi.wvalid  = wvalid_q;
  assign m_axi.bready  = (st_q==S_BRESP);
  assign m_axi.araddr  = op_addr(op_q);
  assign m_axi.arprot  = 3'b000;
  assign m_axi.arvalid = arvalid_q;
  assign m_axi.rready  = (st_q==S_RDATA);

  assign busy = (st_q!=S_IDLE);
  assign done = done_q;
  assign err  = err_q;

endmodule
