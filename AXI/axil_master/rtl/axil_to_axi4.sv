//=============================================================================
// axil_to_axi4.sv
//-----------------------------------------------------------------------------
//  AXI4-Lite マスタを、AXI4 (または AXI4 互換に設定した AXI5) のスレーブポートにつなぐための変換。
//  AXI4-Lite に無い信号を固定値にするだけで、レジスタもロジックも持たない。
//
//      axil_master_mem / axil_master_engine --(AXI4-Lite)--> [axil_to_axi4] --(AXI4 + AWAKEUP)--> インタコネクト
//
//  固定値 (AXI4-Lite のトランザクションの性質から決まるもの):
//    AxLEN   = 0                       1 ビートだけ
//    AxSIZE  = log2(DATA_WIDTH/8)      データバス幅いっぱい
//    AxBURST = INCR (2'b01)
//    AxLOCK  = 0                       排他アクセスは使わない
//    AxCACHE = 4'b0000                 Device Non-bufferable (変更不可・バッファ不可)
//    AxID    = 0                       ID は 1 つだけ (応答は要求の順に返る)
//    WLAST   = 1
//    AxQOS   = parameter QOS
//  BID / RID / RLAST は見ない。
//
//  AWAKEUP (AXI5):
//    Arm CoreLink NI-700 は AXI4-Lite に対応しておらず、つなぐマスタに AWAKEUP を求める。
//    マスタの axi_wakeup (要求を受けてから全ての応答を受けるまで 1 になるレジスタ出力) を
//    そのまま AWAKEUP に出す。AWVALID / ARVALID が 1 のときは必ず 1 になっている。
//=============================================================================
`timescale 1ns / 1ps

module axil_to_axi4 #(
  parameter int unsigned ADDR_WIDTH = 32
 ,parameter int unsigned DATA_WIDTH = 32
 ,parameter int unsigned ID_WIDTH   = 4
 ,parameter logic [3:0]  QOS        = 4'b0000
) (
  //---------------------------------------------------------------------------
  // AXI4-Lite slave 側 (マスタの m_axi_* をつなぐ)
  //---------------------------------------------------------------------------
  input  logic [ADDR_WIDTH-1:0]     s_axi_awaddr
 ,input  logic [2:0]                s_axi_awprot
 ,input  logic                      s_axi_awvalid
 ,output logic                      s_axi_awready
 ,input  logic [DATA_WIDTH-1:0]     s_axi_wdata
 ,input  logic [(DATA_WIDTH/8)-1:0] s_axi_wstrb
 ,input  logic                      s_axi_wvalid
 ,output logic                      s_axi_wready
 ,output logic [1:0]                s_axi_bresp
 ,output logic                      s_axi_bvalid
 ,input  logic                      s_axi_bready
 ,input  logic [ADDR_WIDTH-1:0]     s_axi_araddr
 ,input  logic [2:0]                s_axi_arprot
 ,input  logic                      s_axi_arvalid
 ,output logic                      s_axi_arready
 ,output logic [DATA_WIDTH-1:0]     s_axi_rdata
 ,output logic [1:0]                s_axi_rresp
 ,output logic                      s_axi_rvalid
 ,input  logic                      s_axi_rready
 ,input  logic                      s_axi_wakeup
  //---------------------------------------------------------------------------
  // AXI4 master 側 (+ AXI5 の AWAKEUP)
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
 ,output logic                      m_axi_awvalid
 ,input  logic                      m_axi_awready
 ,output logic [DATA_WIDTH-1:0]     m_axi_wdata
 ,output logic [(DATA_WIDTH/8)-1:0] m_axi_wstrb
 ,output logic                      m_axi_wlast
 ,output logic                      m_axi_wvalid
 ,input  logic                      m_axi_wready
 ,input  logic [ID_WIDTH-1:0]       m_axi_bid
 ,input  logic [1:0]                m_axi_bresp
 ,input  logic                      m_axi_bvalid
 ,output logic                      m_axi_bready
 ,output logic [ID_WIDTH-1:0]       m_axi_arid
 ,output logic [ADDR_WIDTH-1:0]     m_axi_araddr
 ,output logic [7:0]                m_axi_arlen
 ,output logic [2:0]                m_axi_arsize
 ,output logic [1:0]                m_axi_arburst
 ,output logic                      m_axi_arlock
 ,output logic [3:0]                m_axi_arcache
 ,output logic [2:0]                m_axi_arprot
 ,output logic [3:0]                m_axi_arqos
 ,output logic                      m_axi_arvalid
 ,input  logic                      m_axi_arready
 ,input  logic [ID_WIDTH-1:0]       m_axi_rid
 ,input  logic [DATA_WIDTH-1:0]     m_axi_rdata
 ,input  logic [1:0]                m_axi_rresp
 ,input  logic                      m_axi_rlast
 ,input  logic                      m_axi_rvalid
 ,output logic                      m_axi_rready
 ,output logic                      m_axi_awakeup
);

  localparam logic [2:0] SIZE_FULL = 3'($clog2(DATA_WIDTH/8));

  // 書き込みアドレス
  assign m_axi_awid    = {ID_WIDTH{1'b0}};
  assign m_axi_awaddr  = s_axi_awaddr;
  assign m_axi_awlen   = 8'd0;
  assign m_axi_awsize  = SIZE_FULL;
  assign m_axi_awburst = 2'b01;
  assign m_axi_awlock  = 1'b0;
  assign m_axi_awcache = 4'b0000;
  assign m_axi_awprot  = s_axi_awprot;
  assign m_axi_awqos   = QOS;
  assign m_axi_awvalid = s_axi_awvalid;
  assign s_axi_awready = m_axi_awready;

  // 書き込みデータ
  assign m_axi_wdata   = s_axi_wdata;
  assign m_axi_wstrb   = s_axi_wstrb;
  assign m_axi_wlast   = 1'b1;
  assign m_axi_wvalid  = s_axi_wvalid;
  assign s_axi_wready  = m_axi_wready;

  // 書き込み応答
  assign s_axi_bresp   = m_axi_bresp;
  assign s_axi_bvalid  = m_axi_bvalid;
  assign m_axi_bready  = s_axi_bready;

  // 読み出しアドレス
  assign m_axi_arid    = {ID_WIDTH{1'b0}};
  assign m_axi_araddr  = s_axi_araddr;
  assign m_axi_arlen   = 8'd0;
  assign m_axi_arsize  = SIZE_FULL;
  assign m_axi_arburst = 2'b01;
  assign m_axi_arlock  = 1'b0;
  assign m_axi_arcache = 4'b0000;
  assign m_axi_arprot  = s_axi_arprot;
  assign m_axi_arqos   = QOS;
  assign m_axi_arvalid = s_axi_arvalid;
  assign s_axi_arready = m_axi_arready;

  // 読み出しデータ
  assign s_axi_rdata   = m_axi_rdata;
  assign s_axi_rresp   = m_axi_rresp;
  assign s_axi_rvalid  = m_axi_rvalid;
  assign m_axi_rready  = s_axi_rready;

  // AXI5 の wakeup
  assign m_axi_awakeup = s_axi_wakeup;

  //---------------------------------------------------------------------------
  // 未使用信号 (ID は 1 つ、ビートは 1 つなので見ない)
  //---------------------------------------------------------------------------
  logic unused_ok;
  assign unused_ok = &{1'b0, m_axi_bid, m_axi_rid, m_axi_rlast};

  //---------------------------------------------------------------------------
  // パラメータチェック (エラボレーション時)
  //---------------------------------------------------------------------------
`ifndef AXIL_MASTER_NO_ELAB_CHECK
  generate
    if( (DATA_WIDTH!=32)&&(DATA_WIDTH!=64) ) begin : g_chk_data
      $error("axil_to_axi4 : DATA_WIDTH must be 32 or 64 (DATA_WIDTH=%0d)", DATA_WIDTH);
    end
    if( ID_WIDTH<1 ) begin : g_chk_id
      $error("axil_to_axi4 : ID_WIDTH must be >= 1 (ID_WIDTH=%0d)", ID_WIDTH);
    end
  endgenerate
`endif

endmodule
