// ============================================================================
// BAYER2RGB_AXIM_RD_BRIDGE : 読み出し要求・データ(vld/busy/data) ⇔ AXI4マスタ AR/R
//   - AR、Rともに2段スキッドバッファを通し、AXI側の出力をすべてFFから出す
//   - ARID=0、ARSIZE=16バイト、ARBURST=INCR、ARLOCK=0 に固定
//   - RIDは見ない(IDは1種類だけ使う)
// ============================================================================
module BAYER2RGB_AXIM_RD_BRIDGE
  import BAYER2RGB_PKG::*;
(
  input  logic               clk
 ,input  logic               rst_n
 // AXI4マスタ AR
 ,output logic [MEM_IDW-1:0] BAYER2RGB_MEM_ARID
 ,output logic [MEM_AW-1:0]  BAYER2RGB_MEM_ARADDR
 ,output logic [7:0]         BAYER2RGB_MEM_ARLEN
 ,output logic [2:0]         BAYER2RGB_MEM_ARSIZE
 ,output logic [1:0]         BAYER2RGB_MEM_ARBURST
 ,output logic               BAYER2RGB_MEM_ARLOCK
 ,output logic [3:0]         BAYER2RGB_MEM_ARCACHE
 ,output logic [2:0]         BAYER2RGB_MEM_ARPROT
 ,output logic [3:0]         BAYER2RGB_MEM_ARQOS
 ,output logic               BAYER2RGB_MEM_ARVALID
 ,input  logic               BAYER2RGB_MEM_ARREADY
 // AXI4マスタ R
 ,input  logic [MEM_IDW-1:0] BAYER2RGB_MEM_RID
 ,input  logic [MEM_DW-1:0]  BAYER2RGB_MEM_RDATA
 ,input  logic [1:0]         BAYER2RGB_MEM_RRESP
 ,input  logic               BAYER2RGB_MEM_RLAST
 ,input  logic               BAYER2RGB_MEM_RVALID
 ,output logic               BAYER2RGB_MEM_RREADY
 // RD_DMAとの間
 ,BAYER2RGB_VBD_IF.dst       ar       // 読み出し要求(axreq_t)
 ,BAYER2RGB_VBD_IF.src       r        // 読み出しデータ(rbeat_t)
);

  // --------------------------------------------------------------------------
  // AXI4のポートを内部信号に受ける
  // --------------------------------------------------------------------------
  logic [MEM_AW-1:0]  s_mem_araddr;
  logic [7:0]         s_mem_arlen;
  logic [3:0]         s_mem_arcache;
  logic [2:0]         s_mem_arprot;
  logic [3:0]         s_mem_arqos;
  logic               s_mem_arvalid;
  logic               s_mem_arready;
  logic [MEM_DW-1:0]  s_mem_rdata;
  logic [1:0]         s_mem_rresp;
  logic               s_mem_rlast;
  logic               s_mem_rvalid;
  logic               s_mem_rready;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [MEM_IDW-1:0] s_mem_rid;      // IDは1種類なので見ない
  /* verilator lint_on UNUSEDSIGNAL */

  assign BAYER2RGB_MEM_ARID    = MEM_RD_ID;
  assign BAYER2RGB_MEM_ARADDR  = s_mem_araddr;
  assign BAYER2RGB_MEM_ARLEN   = s_mem_arlen;
  assign BAYER2RGB_MEM_ARSIZE  = 3'(MEM_SIZE);
  assign BAYER2RGB_MEM_ARBURST = AXI_BURST_INCR;
  assign BAYER2RGB_MEM_ARLOCK  = 1'b0;
  assign BAYER2RGB_MEM_ARCACHE = s_mem_arcache;
  assign BAYER2RGB_MEM_ARPROT  = s_mem_arprot;
  assign BAYER2RGB_MEM_ARQOS   = s_mem_arqos;
  assign BAYER2RGB_MEM_ARVALID = s_mem_arvalid;
  assign s_mem_arready         = BAYER2RGB_MEM_ARREADY;
  assign s_mem_rid             = BAYER2RGB_MEM_RID;
  assign s_mem_rdata           = BAYER2RGB_MEM_RDATA;
  assign s_mem_rresp           = BAYER2RGB_MEM_RRESP;
  assign s_mem_rlast           = BAYER2RGB_MEM_RLAST;
  assign s_mem_rvalid          = BAYER2RGB_MEM_RVALID;
  assign BAYER2RGB_MEM_RREADY  = s_mem_rready;

  // --------------------------------------------------------------------------
  // AR: RD_DMA → AXI
  // --------------------------------------------------------------------------
  axreq_t s_ar_out;
  logic   s_r_busy;

  BAYER2RGB_SKID #(
    .DW (AXREQ_W)
  ) u_skid_ar (
    .clk    (clk)
   ,.rst_n  (rst_n)
   ,.i_vld  (ar.vld)
   ,.o_busy (ar.busy)
   ,.i_data (ar.data)
   ,.o_vld  (s_mem_arvalid)
   ,.i_busy (!s_mem_arready)
   ,.o_data (s_ar_out)
  );

  assign s_mem_araddr  = s_ar_out.addr;
  assign s_mem_arlen   = s_ar_out.len;
  assign s_mem_arcache = s_ar_out.cache;
  assign s_mem_arprot  = s_ar_out.prot;
  assign s_mem_arqos   = s_ar_out.qos;

  // --------------------------------------------------------------------------
  // R: AXI → RD_DMA
  // --------------------------------------------------------------------------
  BAYER2RGB_SKID #(
    .DW (RBEAT_W)
  ) u_skid_r (
    .clk    (clk)
   ,.rst_n  (rst_n)
   ,.i_vld  (s_mem_rvalid)
   ,.o_busy (s_r_busy)
   ,.i_data ({s_mem_rresp, s_mem_rlast, s_mem_rdata})
   ,.o_vld  (r.vld)
   ,.i_busy (r.busy)
   ,.o_data (r.data)
  );

  assign s_mem_rready = !s_r_busy;

endmodule
