//=============================================================================
// axi4_full_master_p2p_bridge.sv
//-----------------------------------------------------------------------------
//  valid/busy 方式の p2p インタフェース <-> AXI4-Full マスタの bridge。
//    Write 方向 : p2p 入力で受けたデータを AXI Write でメモリへ
//    Read 方向  : AXI Read でメモリから読んだデータを p2p 出力へ
//
//    p2p_in_dat/vld/busy    --> [WR FIFO] --> axi4_mst_wr_engine --> AW/W/B
//    p2p_out_dat/last/vld/busy <-- [RD FIFO] <-- axi4_mst_rd_engine <-- AR/R
//
//  p2p プロトコル (busy = ready の反転、Stratus HLS の cynw_p2p 相当):
//    - 送信側が dat と vld を、受信側が busy を駆動する
//    - vld=1 かつ busy=0 のクロック立ち上がりで 1 ビート転送成立
//    - p2p_in_busy は WR FIFO 満杯 (登録値) から、p2p_out_vld は RD FIFO の
//      格納有無 (登録値) から生成する。p2p 側と AXI 側の間に組合せパスは無い
//
//  - Write / Read はそれぞれ独立したコマンド (アドレス + ビート数) で動く
//  - p2p_out_last は Read コマンドごとの最終ビートで 1
//  - wr_done は最終バーストの B 受領時 (メモリへの書き込み完了)
//    rd_done は最終バーストの R 受領時。データは RD FIFO に残っている場合がある
//    ので、p2p 側の終端は p2p_out_last で判断する
//
//  WR_FIFO_DEPTH / RD_FIFO_DEPTH >= MAX_BURST が必要
//  (1 バースト分のデータ / 空きが揃うまで AW / AR を出さないため)。
//
//  参考: AMBA AXI Protocol Specification (Arm IHI 0022)
//        https://developer.arm.com/documentation/ihi0022/latest/
//=============================================================================
`timescale 1ns / 1ps

module axi4_full_master_p2p_bridge #(
  parameter int unsigned ADDR_WIDTH    = 32
 ,parameter int unsigned DATA_WIDTH    = 64
 ,parameter int unsigned ID_WIDTH      = 4
 ,parameter int unsigned WR_ID         = 0
 ,parameter int unsigned RD_ID         = 1
 ,parameter int unsigned LEN_WIDTH     = 16
 ,parameter int unsigned MAX_BURST     = 16
 ,parameter int unsigned WR_FIFO_DEPTH = 32
 ,parameter int unsigned RD_FIFO_DEPTH = 32
) (
  //---------------------------------------------------------------------------
  // Global
  //---------------------------------------------------------------------------
  input  logic                      aclk
 ,input  logic                      aresetn
  //---------------------------------------------------------------------------
  // Write コマンド (ストリーム -> メモリ)
  //---------------------------------------------------------------------------
 ,input  logic                      wr_cmd_valid
 ,output logic                      wr_cmd_ready
 ,input  logic [ADDR_WIDTH-1:0]     wr_cmd_addr
 ,input  logic [LEN_WIDTH-1:0]      wr_cmd_len
 ,output logic                      wr_busy
 ,output logic                      wr_done
 ,output logic                      wr_done_err
  //---------------------------------------------------------------------------
  // Read コマンド (メモリ -> ストリーム)
  //---------------------------------------------------------------------------
 ,input  logic                      rd_cmd_valid
 ,output logic                      rd_cmd_ready
 ,input  logic [ADDR_WIDTH-1:0]     rd_cmd_addr
 ,input  logic [LEN_WIDTH-1:0]      rd_cmd_len
 ,output logic                      rd_busy
 ,output logic                      rd_done
 ,output logic                      rd_done_err
  //---------------------------------------------------------------------------
  // p2p 入力チャネル (Write データ)
  //---------------------------------------------------------------------------
 ,input  logic [DATA_WIDTH-1:0]     p2p_in_dat
 ,input  logic                      p2p_in_vld
 ,output logic                      p2p_in_busy
  //---------------------------------------------------------------------------
  // p2p 出力チャネル (Read データ)
  //   p2p_out_last は dat と同時に有効なサイドバンド。不要なら未接続でよい
  //---------------------------------------------------------------------------
 ,output logic [DATA_WIDTH-1:0]     p2p_out_dat
 ,output logic                      p2p_out_last
 ,output logic                      p2p_out_vld
 ,input  logic                      p2p_out_busy
  //---------------------------------------------------------------------------
  // ステータス (FIFO 格納数)
  //---------------------------------------------------------------------------
 ,output logic [$clog2(WR_FIFO_DEPTH+1)-1:0] wr_fifo_level
 ,output logic [$clog2(RD_FIFO_DEPTH+1)-1:0] rd_fifo_level
  //---------------------------------------------------------------------------
  // AXI4 master : Write address channel
  //---------------------------------------------------------------------------
 ,output logic [ID_WIDTH-1:0]       m_axi_awid
 ,output logic [ADDR_WIDTH-1:0]     m_axi_awaddr
 ,output logic [7:0]                m_axi_awlen
 ,output logic [2:0]                m_axi_awsize
 ,output logic [1:0]                m_axi_awburst
 ,output logic                      m_axi_awlock
 ,output logic [3:0]                m_axi_awcache
 ,output logic [2:0]                m_axi_awprot
 ,output logic [3:0]                m_axi_awqos
 ,output logic [3:0]                m_axi_awregion
 ,output logic                      m_axi_awvalid
 ,input  logic                      m_axi_awready
  //---------------------------------------------------------------------------
  // AXI4 master : Write data channel
  //---------------------------------------------------------------------------
 ,output logic [DATA_WIDTH-1:0]     m_axi_wdata
 ,output logic [(DATA_WIDTH/8)-1:0] m_axi_wstrb
 ,output logic                      m_axi_wlast
 ,output logic                      m_axi_wvalid
 ,input  logic                      m_axi_wready
  //---------------------------------------------------------------------------
  // AXI4 master : Write response channel
  //---------------------------------------------------------------------------
 ,input  logic [ID_WIDTH-1:0]       m_axi_bid
 ,input  logic [1:0]                m_axi_bresp
 ,input  logic                      m_axi_bvalid
 ,output logic                      m_axi_bready
  //---------------------------------------------------------------------------
  // AXI4 master : Read address channel
  //---------------------------------------------------------------------------
 ,output logic [ID_WIDTH-1:0]       m_axi_arid
 ,output logic [ADDR_WIDTH-1:0]     m_axi_araddr
 ,output logic [7:0]                m_axi_arlen
 ,output logic [2:0]                m_axi_arsize
 ,output logic [1:0]                m_axi_arburst
 ,output logic                      m_axi_arlock
 ,output logic [3:0]                m_axi_arcache
 ,output logic [2:0]                m_axi_arprot
 ,output logic [3:0]                m_axi_arqos
 ,output logic [3:0]                m_axi_arregion
 ,output logic                      m_axi_arvalid
 ,input  logic                      m_axi_arready
  //---------------------------------------------------------------------------
  // AXI4 master : Read data channel
  //---------------------------------------------------------------------------
 ,input  logic [ID_WIDTH-1:0]       m_axi_rid
 ,input  logic [DATA_WIDTH-1:0]     m_axi_rdata
 ,input  logic [1:0]                m_axi_rresp
 ,input  logic                      m_axi_rlast
 ,input  logic                      m_axi_rvalid
 ,output logic                      m_axi_rready
);

  //---------------------------------------------------------------------------
  // Local parameters
  //---------------------------------------------------------------------------
  localparam int unsigned WR_LVL_W = $clog2(WR_FIFO_DEPTH+1);
  localparam int unsigned RD_LVL_W = $clog2(RD_FIFO_DEPTH+1);
  localparam int unsigned CNT_W    = 16;

  //===========================================================================
  // Write 方向 : p2p 入力 -> WR FIFO -> Write エンジン
  //   busy は FIFO 満杯で 1 (vld には組合せ依存しない)
  //===========================================================================
  logic [DATA_WIDTH-1:0] wf_data;
  logic                  wf_valid;
  logic                  wf_ready;
  logic                  wf_wr_ready;
  logic [WR_LVL_W-1:0]   wf_level;

  assign p2p_in_busy   = !wf_wr_ready;
  assign wr_fifo_level = wf_level;

  axi4_sync_fifo #(
    .WIDTH(DATA_WIDTH)
   ,.DEPTH(WR_FIFO_DEPTH)
  ) u_wr_fifo (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.wr_data(p2p_in_dat)
   ,.wr_valid(p2p_in_vld)
   ,.wr_ready(wf_wr_ready)
   ,.rd_data(wf_data)
   ,.rd_valid(wf_valid)
   ,.rd_ready(wf_ready)
   ,.level(wf_level)
  );

  axi4_mst_wr_engine #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.ID_WIDTH(ID_WIDTH)
   ,.AXI_ID(WR_ID)
   ,.LEN_WIDTH(LEN_WIDTH)
   ,.CNT_WIDTH(CNT_W)
   ,.MAX_BURST(MAX_BURST)
  ) u_wr (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.cmd_valid(wr_cmd_valid)
   ,.cmd_ready(wr_cmd_ready)
   ,.cmd_addr(wr_cmd_addr)
   ,.cmd_len(wr_cmd_len)
   ,.busy(wr_busy)
   ,.done(wr_done)
   ,.done_err(wr_done_err)
   ,.s_data(wf_data)
   ,.s_valid(wf_valid)
   ,.s_ready(wf_ready)
   ,.s_count(CNT_W'(wf_level))
   ,.m_axi_awid(m_axi_awid)
   ,.m_axi_awaddr(m_axi_awaddr)
   ,.m_axi_awlen(m_axi_awlen)
   ,.m_axi_awsize(m_axi_awsize)
   ,.m_axi_awburst(m_axi_awburst)
   ,.m_axi_awlock(m_axi_awlock)
   ,.m_axi_awcache(m_axi_awcache)
   ,.m_axi_awprot(m_axi_awprot)
   ,.m_axi_awqos(m_axi_awqos)
   ,.m_axi_awregion(m_axi_awregion)
   ,.m_axi_awvalid(m_axi_awvalid)
   ,.m_axi_awready(m_axi_awready)
   ,.m_axi_wdata(m_axi_wdata)
   ,.m_axi_wstrb(m_axi_wstrb)
   ,.m_axi_wlast(m_axi_wlast)
   ,.m_axi_wvalid(m_axi_wvalid)
   ,.m_axi_wready(m_axi_wready)
   ,.m_axi_bid(m_axi_bid)
   ,.m_axi_bresp(m_axi_bresp)
   ,.m_axi_bvalid(m_axi_bvalid)
   ,.m_axi_bready(m_axi_bready)
  );

  //===========================================================================
  // Read 方向 : Read エンジン -> RD FIFO ({last, data}) -> p2p 出力
  //   vld は FIFO の格納有無 (busy には組合せ依存しない)
  //   転送 : vld=1 かつ busy=0 のクロックエッジで FIFO をポップする
  //===========================================================================
  logic [DATA_WIDTH-1:0] re_data;
  logic                  re_last;
  logic                  re_valid;
  logic                  re_ready;
  logic [DATA_WIDTH:0]   rf_rd_data;
  logic                  rf_rd_valid;
  logic [RD_LVL_W-1:0]   rf_level;

  axi4_mst_rd_engine #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.ID_WIDTH(ID_WIDTH)
   ,.AXI_ID(RD_ID)
   ,.LEN_WIDTH(LEN_WIDTH)
   ,.CNT_WIDTH(CNT_W)
   ,.MAX_BURST(MAX_BURST)
  ) u_rd (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.cmd_valid(rd_cmd_valid)
   ,.cmd_ready(rd_cmd_ready)
   ,.cmd_addr(rd_cmd_addr)
   ,.cmd_len(rd_cmd_len)
   ,.busy(rd_busy)
   ,.done(rd_done)
   ,.done_err(rd_done_err)
   ,.m_data(re_data)
   ,.m_last(re_last)
   ,.m_valid(re_valid)
   ,.m_ready(re_ready)
   ,.m_space(CNT_W'(RD_FIFO_DEPTH) - CNT_W'(rf_level))
   ,.m_axi_arid(m_axi_arid)
   ,.m_axi_araddr(m_axi_araddr)
   ,.m_axi_arlen(m_axi_arlen)
   ,.m_axi_arsize(m_axi_arsize)
   ,.m_axi_arburst(m_axi_arburst)
   ,.m_axi_arlock(m_axi_arlock)
   ,.m_axi_arcache(m_axi_arcache)
   ,.m_axi_arprot(m_axi_arprot)
   ,.m_axi_arqos(m_axi_arqos)
   ,.m_axi_arregion(m_axi_arregion)
   ,.m_axi_arvalid(m_axi_arvalid)
   ,.m_axi_arready(m_axi_arready)
   ,.m_axi_rid(m_axi_rid)
   ,.m_axi_rdata(m_axi_rdata)
   ,.m_axi_rresp(m_axi_rresp)
   ,.m_axi_rlast(m_axi_rlast)
   ,.m_axi_rvalid(m_axi_rvalid)
   ,.m_axi_rready(m_axi_rready)
  );

  axi4_sync_fifo #(
    .WIDTH(DATA_WIDTH+1)
   ,.DEPTH(RD_FIFO_DEPTH)
  ) u_rd_fifo (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.wr_data({re_last, re_data})
   ,.wr_valid(re_valid)
   ,.wr_ready(re_ready)
   ,.rd_data(rf_rd_data)
   ,.rd_valid(rf_rd_valid)
   ,.rd_ready(!p2p_out_busy)
   ,.level(rf_level)
  );

  assign p2p_out_dat   = rf_rd_data[DATA_WIDTH-1:0];
  assign p2p_out_last  = rf_rd_data[DATA_WIDTH];
  assign p2p_out_vld   = rf_rd_valid;
  assign rd_fifo_level = rf_level;

  //---------------------------------------------------------------------------
  // エラボレーション時チェック
  //---------------------------------------------------------------------------
  initial begin
    if( (WR_FIFO_DEPTH<MAX_BURST)||(RD_FIFO_DEPTH<MAX_BURST) ) begin
      $error("axi4_full_master_p2p_bridge : FIFO depth must be >= MAX_BURST (%0d)", MAX_BURST);
    end
  end

endmodule
