// ============================================================================
// BAYER2RGB : Bayer(14bit) → RGB888 変換(トップ階層)
//   メモリ上のBayer画像を読み、BLC → WB → バイリニアデモザイク → 偽色抑制
//   → ガンマ を通して、メモリにRGB888(R,G,B順)で書き込む。
//   制御 : AXI4-Liteスレーブ(ctrl_clk)  BAYER2RGB_REG_*
//   データ: AXI4マスタ(clk)             BAYER2RGB_MEM_*
// ============================================================================
module BAYER2RGB
  import BAYER2RGB_PKG::*;
(
  // クロック・リセット
  input  logic                 clk
 ,input  logic                 rst_n
 ,input  logic                 ctrl_clk
 ,input  logic                 ctrl_rst_n
 // 割り込み(ctrl_clk、High、レベル)
 ,output logic                 irq
 // AXI4-Liteスレーブ(ctrl_clk)
 ,input  logic [REG_AW-1:0]    BAYER2RGB_REG_AWADDR
 ,input  logic [2:0]           BAYER2RGB_REG_AWPROT
 ,input  logic                 BAYER2RGB_REG_AWVALID
 ,output logic                 BAYER2RGB_REG_AWREADY
 ,input  logic [REG_DW-1:0]    BAYER2RGB_REG_WDATA
 ,input  logic [REG_DW/8-1:0]  BAYER2RGB_REG_WSTRB
 ,input  logic                 BAYER2RGB_REG_WVALID
 ,output logic                 BAYER2RGB_REG_WREADY
 ,output logic [1:0]           BAYER2RGB_REG_BRESP
 ,output logic                 BAYER2RGB_REG_BVALID
 ,input  logic                 BAYER2RGB_REG_BREADY
 ,input  logic [REG_AW-1:0]    BAYER2RGB_REG_ARADDR
 ,input  logic [2:0]           BAYER2RGB_REG_ARPROT
 ,input  logic                 BAYER2RGB_REG_ARVALID
 ,output logic                 BAYER2RGB_REG_ARREADY
 ,output logic [REG_DW-1:0]    BAYER2RGB_REG_RDATA
 ,output logic [1:0]           BAYER2RGB_REG_RRESP
 ,output logic                 BAYER2RGB_REG_RVALID
 ,input  logic                 BAYER2RGB_REG_RREADY
 // AXI4マスタ(clk)
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
 ,output logic [MEM_DW-1:0]    BAYER2RGB_MEM_WDATA
 ,output logic [MEM_BYTES-1:0] BAYER2RGB_MEM_WSTRB
 ,output logic                 BAYER2RGB_MEM_WLAST
 ,output logic                 BAYER2RGB_MEM_WVALID
 ,input  logic                 BAYER2RGB_MEM_WREADY
 ,input  logic [MEM_IDW-1:0]   BAYER2RGB_MEM_BID
 ,input  logic [1:0]           BAYER2RGB_MEM_BRESP
 ,input  logic                 BAYER2RGB_MEM_BVALID
 ,output logic                 BAYER2RGB_MEM_BREADY
 ,output logic [MEM_IDW-1:0]   BAYER2RGB_MEM_ARID
 ,output logic [MEM_AW-1:0]    BAYER2RGB_MEM_ARADDR
 ,output logic [7:0]           BAYER2RGB_MEM_ARLEN
 ,output logic [2:0]           BAYER2RGB_MEM_ARSIZE
 ,output logic [1:0]           BAYER2RGB_MEM_ARBURST
 ,output logic                 BAYER2RGB_MEM_ARLOCK
 ,output logic [3:0]           BAYER2RGB_MEM_ARCACHE
 ,output logic [2:0]           BAYER2RGB_MEM_ARPROT
 ,output logic [3:0]           BAYER2RGB_MEM_ARQOS
 ,output logic                 BAYER2RGB_MEM_ARVALID
 ,input  logic                 BAYER2RGB_MEM_ARREADY
 ,input  logic [MEM_IDW-1:0]   BAYER2RGB_MEM_RID
 ,input  logic [MEM_DW-1:0]    BAYER2RGB_MEM_RDATA
 ,input  logic [1:0]           BAYER2RGB_MEM_RRESP
 ,input  logic                 BAYER2RGB_MEM_RLAST
 ,input  logic                 BAYER2RGB_MEM_RVALID
 ,output logic                 BAYER2RGB_MEM_RREADY
);

  // --------------------------------------------------------------------------
  // 内部信号
  // --------------------------------------------------------------------------
  // 制御系
  BAYER2RGB_VBD_IF #(.DW(REGREQ_W)) s_req ();   // レジスタアクセス要求
  BAYER2RGB_VBD_IF #(.DW(REGRSP_W)) s_rsp ();   // レジスタアクセス応答
  cfg_t    s_cfg;
  logic    s_start;
  logic    s_sw_rst;
  logic    s_cdc_busy;
  evt_t    s_evt_c;
  // 映像系
  ctl_t    s_ctl_v;
  rd_evt_t s_rd_evt;
  wr_evt_t s_wr_evt;
  BAYER2RGB_VBD_IF #(.DW(AXREQ_W))    s_ar  ();  // 読み出し要求
  BAYER2RGB_VBD_IF #(.DW(RBEAT_W))    s_r   ();  // 読み出しデータ
  BAYER2RGB_VBD_IF #(.DW(BEAT_W))     s_pix ();  // COREへの画素
  BAYER2RGB_VBD_IF #(.DW(OUT_DATA_W)) s_rgb ();  // COREからのRGB
  BAYER2RGB_VBD_IF #(.DW(AXREQ_W))    s_aw  ();  // 書き込み要求
  BAYER2RGB_VBD_IF #(.DW(WBEAT_W))    s_w   ();  // 書き込みデータ
  BAYER2RGB_VBD_IF #(.DW(BRESP_W))    s_b   ();  // 書き込み応答

  // --------------------------------------------------------------------------
  // 制御系(ctrl_clk)
  // --------------------------------------------------------------------------
  BAYER2RGB_AXIL_BRIDGE u_axil_bridge (
    .ctrl_clk              (ctrl_clk)
   ,.ctrl_rst_n            (ctrl_rst_n)
   ,.BAYER2RGB_REG_AWADDR  (BAYER2RGB_REG_AWADDR)
   ,.BAYER2RGB_REG_AWPROT  (BAYER2RGB_REG_AWPROT)
   ,.BAYER2RGB_REG_AWVALID (BAYER2RGB_REG_AWVALID)
   ,.BAYER2RGB_REG_AWREADY (BAYER2RGB_REG_AWREADY)
   ,.BAYER2RGB_REG_WDATA   (BAYER2RGB_REG_WDATA)
   ,.BAYER2RGB_REG_WSTRB   (BAYER2RGB_REG_WSTRB)
   ,.BAYER2RGB_REG_WVALID  (BAYER2RGB_REG_WVALID)
   ,.BAYER2RGB_REG_WREADY  (BAYER2RGB_REG_WREADY)
   ,.BAYER2RGB_REG_BRESP   (BAYER2RGB_REG_BRESP)
   ,.BAYER2RGB_REG_BVALID  (BAYER2RGB_REG_BVALID)
   ,.BAYER2RGB_REG_BREADY  (BAYER2RGB_REG_BREADY)
   ,.BAYER2RGB_REG_ARADDR  (BAYER2RGB_REG_ARADDR)
   ,.BAYER2RGB_REG_ARPROT  (BAYER2RGB_REG_ARPROT)
   ,.BAYER2RGB_REG_ARVALID (BAYER2RGB_REG_ARVALID)
   ,.BAYER2RGB_REG_ARREADY (BAYER2RGB_REG_ARREADY)
   ,.BAYER2RGB_REG_RDATA   (BAYER2RGB_REG_RDATA)
   ,.BAYER2RGB_REG_RRESP   (BAYER2RGB_REG_RRESP)
   ,.BAYER2RGB_REG_RVALID  (BAYER2RGB_REG_RVALID)
   ,.BAYER2RGB_REG_RREADY  (BAYER2RGB_REG_RREADY)
   ,.req                   (s_req)
   ,.rsp                   (s_rsp)
  );

  BAYER2RGB_REG u_reg (
    .ctrl_clk   (ctrl_clk)
   ,.ctrl_rst_n (ctrl_rst_n)
   ,.req        (s_req)
   ,.rsp        (s_rsp)
   ,.o_cfg      (s_cfg)
   ,.o_start    (s_start)
   ,.o_sw_rst   (s_sw_rst)
   ,.i_cdc_busy (s_cdc_busy)
   ,.i_evt      (s_evt_c)
   ,.o_irq      (irq)
  );

  BAYER2RGB_CDC u_cdc (
    .ctrl_clk   (ctrl_clk)
   ,.ctrl_rst_n (ctrl_rst_n)
   ,.i_cfg      (s_cfg)
   ,.i_start    (s_start)
   ,.i_sw_rst   (s_sw_rst)
   ,.o_busy     (s_cdc_busy)
   ,.o_evt      (s_evt_c)
   ,.clk        (clk)
   ,.rst_n      (rst_n)
   ,.o_ctl      (s_ctl_v)
   ,.i_rd_evt   (s_rd_evt)
   ,.i_wr_evt   (s_wr_evt)
  );

  // --------------------------------------------------------------------------
  // 映像系(clk)
  // --------------------------------------------------------------------------
  BAYER2RGB_AXIM_RD_BRIDGE u_axim_rd_bridge (
    .clk                   (clk)
   ,.rst_n                 (rst_n)
   ,.BAYER2RGB_MEM_ARID    (BAYER2RGB_MEM_ARID)
   ,.BAYER2RGB_MEM_ARADDR  (BAYER2RGB_MEM_ARADDR)
   ,.BAYER2RGB_MEM_ARLEN   (BAYER2RGB_MEM_ARLEN)
   ,.BAYER2RGB_MEM_ARSIZE  (BAYER2RGB_MEM_ARSIZE)
   ,.BAYER2RGB_MEM_ARBURST (BAYER2RGB_MEM_ARBURST)
   ,.BAYER2RGB_MEM_ARLOCK  (BAYER2RGB_MEM_ARLOCK)
   ,.BAYER2RGB_MEM_ARCACHE (BAYER2RGB_MEM_ARCACHE)
   ,.BAYER2RGB_MEM_ARPROT  (BAYER2RGB_MEM_ARPROT)
   ,.BAYER2RGB_MEM_ARQOS   (BAYER2RGB_MEM_ARQOS)
   ,.BAYER2RGB_MEM_ARVALID (BAYER2RGB_MEM_ARVALID)
   ,.BAYER2RGB_MEM_ARREADY (BAYER2RGB_MEM_ARREADY)
   ,.BAYER2RGB_MEM_RID     (BAYER2RGB_MEM_RID)
   ,.BAYER2RGB_MEM_RDATA   (BAYER2RGB_MEM_RDATA)
   ,.BAYER2RGB_MEM_RRESP   (BAYER2RGB_MEM_RRESP)
   ,.BAYER2RGB_MEM_RLAST   (BAYER2RGB_MEM_RLAST)
   ,.BAYER2RGB_MEM_RVALID  (BAYER2RGB_MEM_RVALID)
   ,.BAYER2RGB_MEM_RREADY  (BAYER2RGB_MEM_RREADY)
   ,.ar                    (s_ar)
   ,.r                     (s_r)
  );

  BAYER2RGB_RD_DMA u_rd_dma (
    .clk   (clk)
   ,.rst_n (rst_n)
   ,.i_ctl (s_ctl_v)
   ,.ar    (s_ar)
   ,.r     (s_r)
   ,.pix   (s_pix)
   ,.o_evt (s_rd_evt)
  );

  BAYER2RGB_CORE u_core (
    .clk   (clk)
   ,.rst_n (rst_n)
   ,.i_ctl (s_ctl_v)
   ,.pix   (s_pix)
   ,.rgb   (s_rgb)
  );

  BAYER2RGB_WR_DMA u_wr_dma (
    .clk   (clk)
   ,.rst_n (rst_n)
   ,.i_ctl (s_ctl_v)
   ,.rgb   (s_rgb)
   ,.aw    (s_aw)
   ,.w     (s_w)
   ,.b     (s_b)
   ,.o_evt (s_wr_evt)
  );

  BAYER2RGB_AXIM_WR_BRIDGE u_axim_wr_bridge (
    .clk                   (clk)
   ,.rst_n                 (rst_n)
   ,.BAYER2RGB_MEM_AWID    (BAYER2RGB_MEM_AWID)
   ,.BAYER2RGB_MEM_AWADDR  (BAYER2RGB_MEM_AWADDR)
   ,.BAYER2RGB_MEM_AWLEN   (BAYER2RGB_MEM_AWLEN)
   ,.BAYER2RGB_MEM_AWSIZE  (BAYER2RGB_MEM_AWSIZE)
   ,.BAYER2RGB_MEM_AWBURST (BAYER2RGB_MEM_AWBURST)
   ,.BAYER2RGB_MEM_AWLOCK  (BAYER2RGB_MEM_AWLOCK)
   ,.BAYER2RGB_MEM_AWCACHE (BAYER2RGB_MEM_AWCACHE)
   ,.BAYER2RGB_MEM_AWPROT  (BAYER2RGB_MEM_AWPROT)
   ,.BAYER2RGB_MEM_AWQOS   (BAYER2RGB_MEM_AWQOS)
   ,.BAYER2RGB_MEM_AWVALID (BAYER2RGB_MEM_AWVALID)
   ,.BAYER2RGB_MEM_AWREADY (BAYER2RGB_MEM_AWREADY)
   ,.BAYER2RGB_MEM_WDATA   (BAYER2RGB_MEM_WDATA)
   ,.BAYER2RGB_MEM_WSTRB   (BAYER2RGB_MEM_WSTRB)
   ,.BAYER2RGB_MEM_WLAST   (BAYER2RGB_MEM_WLAST)
   ,.BAYER2RGB_MEM_WVALID  (BAYER2RGB_MEM_WVALID)
   ,.BAYER2RGB_MEM_WREADY  (BAYER2RGB_MEM_WREADY)
   ,.BAYER2RGB_MEM_BID     (BAYER2RGB_MEM_BID)
   ,.BAYER2RGB_MEM_BRESP   (BAYER2RGB_MEM_BRESP)
   ,.BAYER2RGB_MEM_BVALID  (BAYER2RGB_MEM_BVALID)
   ,.BAYER2RGB_MEM_BREADY  (BAYER2RGB_MEM_BREADY)
   ,.aw                    (s_aw)
   ,.w                     (s_w)
   ,.b                     (s_b)
  );

endmodule
