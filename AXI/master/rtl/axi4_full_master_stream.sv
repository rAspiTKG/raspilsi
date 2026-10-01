//=============================================================================
// axi4_full_master_stream.sv
//-----------------------------------------------------------------------------
//  ストリーム <-> AXI4-Full マスタ。
//    Write 方向 : 入力ストリーム (s_t*) で受けたデータを AXI Write でメモリへ
//    Read 方向  : AXI Read でメモリから読んだデータを出力ストリーム (m_t*) へ
//
//    s_tdata/s_tvalid/s_tready --> [WR FIFO] --> axi4_mst_wr_engine --> AW/W/B
//    m_tdata/m_tlast/m_t*      <-- [RD FIFO] <-- axi4_mst_rd_engine <-- AR/R
//
//  - Write / Read はそれぞれ独立したコマンド (アドレス + ビート数) で動く
//  - ストリームのハンドシェイク: tvalid && tready のクロックエッジで 1 ビート
//    s_tready は FIFO の空き (登録値)、m_tvalid は FIFO の格納有無 (登録値) から
//    生成するので、ストリーム側と AXI 側の間に組合せパスは無い
//  - m_tlast は Read コマンドごとの最終ビートで 1
//  - wr_done は最終バーストの B 受領時 (メモリへの書き込み完了)
//    rd_done は最終バーストの R 受領時。データは RD FIFO に残っている場合がある
//    ので、ストリーム側の終端は m_tlast で判断する
//
//  WR_FIFO_DEPTH / RD_FIFO_DEPTH >= MAX_BURST が必要
//  (1 バースト分のデータ / 空きが揃うまで AW / AR を出さないため)。
//
//  参考: AMBA AXI Protocol Specification (Arm IHI 0022)
//        https://developer.arm.com/documentation/ihi0022/latest/
//=============================================================================
`timescale 1ns / 1ps

module axi4_full_master_stream #(
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
  // 入力ストリーム (Write データ)
  //---------------------------------------------------------------------------
 ,input  logic [DATA_WIDTH-1:0]     s_tdata
 ,input  logic                      s_tvalid
 ,output logic                      s_tready
  //---------------------------------------------------------------------------
  // 出力ストリーム (Read データ)
  //---------------------------------------------------------------------------
 ,output logic [DATA_WIDTH-1:0]     m_tdata
 ,output logic                      m_tlast
 ,output logic                      m_tvalid
 ,input  logic                      m_tready
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
  // Write 方向 : 入力ストリーム -> WR FIFO -> Write エンジン
  //===========================================================================
  logic [DATA_WIDTH-1:0] wf_data;
  logic                  wf_valid;
  logic                  wf_ready;
  logic [WR_LVL_W-1:0]   wf_level;

  axi4_sync_fifo #(
    .WIDTH(DATA_WIDTH)
   ,.DEPTH(WR_FIFO_DEPTH)
  ) u_wr_fifo (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.wr_data(s_tdata)
   ,.wr_valid(s_tvalid)
   ,.wr_ready(s_tready)
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
  // Read 方向 : Read エンジン -> RD FIFO ({last, data}) -> 出力ストリーム
  //===========================================================================
  logic [DATA_WIDTH-1:0] re_data;
  logic                  re_last;
  logic                  re_valid;
  logic                  re_ready;
  logic [DATA_WIDTH:0]   rf_rd_data;
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
   ,.rd_valid(m_tvalid)
   ,.rd_ready(m_tready)
   ,.level(rf_level)
  );

  assign m_tdata = rf_rd_data[DATA_WIDTH-1:0];
  assign m_tlast = rf_rd_data[DATA_WIDTH];

  //---------------------------------------------------------------------------
  // エラボレーション時チェック
  //---------------------------------------------------------------------------
  initial begin
    if( (WR_FIFO_DEPTH<MAX_BURST)||(RD_FIFO_DEPTH<MAX_BURST) ) begin
      $error("axi4_full_master_stream : FIFO depth must be >= MAX_BURST (%0d)", MAX_BURST);
    end
  end

endmodule
