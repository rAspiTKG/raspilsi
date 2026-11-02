// ============================================================================
// BAYER2RGB_AXIM_WR_BRIDGE : 書き込み要求・データ・応答(vld/busy/data) ⇔ AXI4マスタ AW/W/B
//   - AW、W、Bともに2段スキッドバッファを通し、AXI側の出力をすべてFFから出す
//   - AWID=0、AWSIZE=16バイト、AWBURST=INCR、AWLOCK=0 に固定
//   - AWとWは独立に流す(WはAWの受け付けを待たない。AXI4の依存規則どおり)
//   - BIDは見ない(IDは1種類だけ使う)
// ============================================================================
module BAYER2RGB_AXIM_WR_BRIDGE
  import BAYER2RGB_PKG::*;
(
  input  logic                 clk
 ,input  logic                 rst_n
 // AXI4マスタ AW
 ,output logic [MEM_IDW-1:0]   BAYER2RGB_MEM_AWID
 ,output logic [MEM_AW-1:0]    BAYER2RGB_MEM_AWADDR
 ,output logic [7:0]           BAYER2RGB_MEM_AWLEN
 ,output logic [2:0]           BAYER2RGB_MEM_AWSIZE
 ,output logic [1:0]           BAYER2RGB_MEM_AWBURST
 ,output logic                 BAYER2RGB_MEM_AWLOCK
 ,output logic [3:0]           BAYER2RGB_MEM_AWCACHE
 ,output logic [2:0]           BAYER2RGB_MEM_AWPROT
 ,output logic [3:0]           BAYER2RGB_MEM_AWQOS
 ,output logic                 BAYER2RGB_MEM_AWVALID
 ,input  logic                 BAYER2RGB_MEM_AWREADY
 // AXI4マスタ W
 ,output logic [MEM_DW-1:0]    BAYER2RGB_MEM_WDATA
 ,output logic [MEM_BYTES-1:0] BAYER2RGB_MEM_WSTRB
 ,output logic                 BAYER2RGB_MEM_WLAST
 ,output logic                 BAYER2RGB_MEM_WVALID
 ,input  logic                 BAYER2RGB_MEM_WREADY
 // AXI4マスタ B
 ,input  logic [MEM_IDW-1:0]   BAYER2RGB_MEM_BID
 ,input  logic [1:0]           BAYER2RGB_MEM_BRESP
 ,input  logic                 BAYER2RGB_MEM_BVALID
 ,output logic                 BAYER2RGB_MEM_BREADY
 // WR_DMAとの間
 ,BAYER2RGB_VBD_IF.dst         aw       // 書き込み要求(axreq_t)
 ,BAYER2RGB_VBD_IF.dst         w        // 書き込みデータ(wbeat_t)
 ,BAYER2RGB_VBD_IF.src         b        // 書き込み応答(BRESP)
);

  // --------------------------------------------------------------------------
  // AXI4のポートを内部信号に受ける
  // --------------------------------------------------------------------------
  logic [MEM_AW-1:0]    s_mem_awaddr;
  logic [7:0]           s_mem_awlen;
  logic [3:0]           s_mem_awcache;
  logic [2:0]           s_mem_awprot;
  logic [3:0]           s_mem_awqos;
  logic                 s_mem_awvalid;
  logic                 s_mem_awready;
  logic [MEM_DW-1:0]    s_mem_wdata;
  logic [MEM_BYTES-1:0] s_mem_wstrb;
  logic                 s_mem_wlast;
  logic                 s_mem_wvalid;
  logic                 s_mem_wready;
  logic [1:0]           s_mem_bresp;
  logic                 s_mem_bvalid;
  logic                 s_mem_bready;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [MEM_IDW-1:0]   s_mem_bid;      // IDは1種類なので見ない
  /* verilator lint_on UNUSEDSIGNAL */

  assign BAYER2RGB_MEM_AWID    = MEM_WR_ID;
  assign BAYER2RGB_MEM_AWADDR  = s_mem_awaddr;
  assign BAYER2RGB_MEM_AWLEN   = s_mem_awlen;
  assign BAYER2RGB_MEM_AWSIZE  = 3'(MEM_SIZE);
  assign BAYER2RGB_MEM_AWBURST = AXI_BURST_INCR;
  assign BAYER2RGB_MEM_AWLOCK  = 1'b0;
  assign BAYER2RGB_MEM_AWCACHE = s_mem_awcache;
  assign BAYER2RGB_MEM_AWPROT  = s_mem_awprot;
  assign BAYER2RGB_MEM_AWQOS   = s_mem_awqos;
  assign BAYER2RGB_MEM_AWVALID = s_mem_awvalid;
  assign s_mem_awready         = BAYER2RGB_MEM_AWREADY;
  assign BAYER2RGB_MEM_WDATA   = s_mem_wdata;
  assign BAYER2RGB_MEM_WSTRB   = s_mem_wstrb;
  assign BAYER2RGB_MEM_WLAST   = s_mem_wlast;
  assign BAYER2RGB_MEM_WVALID  = s_mem_wvalid;
  assign s_mem_wready          = BAYER2RGB_MEM_WREADY;
  assign s_mem_bid             = BAYER2RGB_MEM_BID;
  assign s_mem_bresp           = BAYER2RGB_MEM_BRESP;
  assign s_mem_bvalid          = BAYER2RGB_MEM_BVALID;
  assign BAYER2RGB_MEM_BREADY  = s_mem_bready;

  // --------------------------------------------------------------------------
  // AW: WR_DMA → AXI
  // --------------------------------------------------------------------------
  axreq_t s_aw_out;
  wbeat_t s_w_out;
  logic   s_b_busy;

  BAYER2RGB_SKID #(
    .DW (AXREQ_W)
  ) u_skid_aw (
    .clk    (clk)
   ,.rst_n  (rst_n)
   ,.i_vld  (aw.vld)
   ,.o_busy (aw.busy)
   ,.i_data (aw.data)
   ,.o_vld  (s_mem_awvalid)
   ,.i_busy (!s_mem_awready)
   ,.o_data (s_aw_out)
  );

  assign s_mem_awaddr  = s_aw_out.addr;
  assign s_mem_awlen   = s_aw_out.len;
  assign s_mem_awcache = s_aw_out.cache;
  assign s_mem_awprot  = s_aw_out.prot;
  assign s_mem_awqos   = s_aw_out.qos;

  // --------------------------------------------------------------------------
  // W: WR_DMA → AXI
  // --------------------------------------------------------------------------
  BAYER2RGB_SKID #(
    .DW (WBEAT_W)
  ) u_skid_w (
    .clk    (clk)
   ,.rst_n  (rst_n)
   ,.i_vld  (w.vld)
   ,.o_busy (w.busy)
   ,.i_data (w.data)
   ,.o_vld  (s_mem_wvalid)
   ,.i_busy (!s_mem_wready)
   ,.o_data (s_w_out)
  );

  assign s_mem_wdata = s_w_out.data;
  assign s_mem_wstrb = s_w_out.strb;
  assign s_mem_wlast = s_w_out.last;

  // --------------------------------------------------------------------------
  // B: AXI → WR_DMA
  // --------------------------------------------------------------------------
  BAYER2RGB_SKID #(
    .DW (BRESP_W)
  ) u_skid_b (
    .clk    (clk)
   ,.rst_n  (rst_n)
   ,.i_vld  (s_mem_bvalid)
   ,.o_busy (s_b_busy)
   ,.i_data (s_mem_bresp)
   ,.o_vld  (b.vld)
   ,.i_busy (b.busy)
   ,.o_data (b.data)
  );

  assign s_mem_bready = !s_b_busy;

endmodule
