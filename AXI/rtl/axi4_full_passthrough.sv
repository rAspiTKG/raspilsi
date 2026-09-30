//=============================================================================
// axi4_full_passthrough.sv
//-----------------------------------------------------------------------------
//  AXI4-Full スレーブポートで受け取ったトランザクションを、
//  AXI4-Full マスタポートへそのまま出力するモジュール (レジスタスライス相当)。
//
//  5 チャネル (AW / W / B / AR / R) それぞれに独立したスキッドバッファを置き、
//  VALID/READY ハンドシェイクを実装しつつ全信号を素通しする。
//    - AW / W / AR : スレーブポート → マスタポート方向
//    - B  / R      : マスタポート → スレーブポート方向
//
//  チャネル毎に順序を保つため、AXI4 のトランザクション順序規則を崩さない。
//  BYPASS=1 にすると全チャネルが単純結線 (組合せ素通し) になる。
//
//  参考: AMBA AXI Protocol Specification (Arm IHI 0022)
//        https://developer.arm.com/documentation/ihi0022/latest/
//        - A3.2 Basic transaction handshake
//        - A3.3 Channel signals   (各チャネルの信号一覧)
//
//  注意 (簡易実装):
//    - USER 信号 (AxUSER/WUSER/BUSER/RUSER) は未対応
//    - アドレスデコードや保護チェックは行わない (完全な素通し)
//=============================================================================
`timescale 1ns / 1ps

module axi4_full_passthrough #(
  parameter int unsigned ADDR_WIDTH = 32
 ,parameter int unsigned DATA_WIDTH = 64
 ,parameter int unsigned ID_WIDTH   = 4
 ,parameter bit          BYPASS     = 1'b0
) (
  //---------------------------------------------------------------------------
  // Global
  //---------------------------------------------------------------------------
  input  logic                      aclk
 ,input  logic                      aresetn
  //---------------------------------------------------------------------------
  // Slave port (上流マスタから受け取る)
  //---------------------------------------------------------------------------
 ,input  logic [ID_WIDTH-1:0]       s_axi_awid
 ,input  logic [ADDR_WIDTH-1:0]     s_axi_awaddr
 ,input  logic [7:0]                s_axi_awlen
 ,input  logic [2:0]                s_axi_awsize
 ,input  logic [1:0]                s_axi_awburst
 ,input  logic                      s_axi_awlock
 ,input  logic [3:0]                s_axi_awcache
 ,input  logic [2:0]                s_axi_awprot
 ,input  logic [3:0]                s_axi_awqos
 ,input  logic [3:0]                s_axi_awregion
 ,input  logic                      s_axi_awvalid
 ,output logic                      s_axi_awready
 ,input  logic [DATA_WIDTH-1:0]     s_axi_wdata
 ,input  logic [(DATA_WIDTH/8)-1:0] s_axi_wstrb
 ,input  logic                      s_axi_wlast
 ,input  logic                      s_axi_wvalid
 ,output logic                      s_axi_wready
 ,output logic [ID_WIDTH-1:0]       s_axi_bid
 ,output logic [1:0]                s_axi_bresp
 ,output logic                      s_axi_bvalid
 ,input  logic                      s_axi_bready
 ,input  logic [ID_WIDTH-1:0]       s_axi_arid
 ,input  logic [ADDR_WIDTH-1:0]     s_axi_araddr
 ,input  logic [7:0]                s_axi_arlen
 ,input  logic [2:0]                s_axi_arsize
 ,input  logic [1:0]                s_axi_arburst
 ,input  logic                      s_axi_arlock
 ,input  logic [3:0]                s_axi_arcache
 ,input  logic [2:0]                s_axi_arprot
 ,input  logic [3:0]                s_axi_arqos
 ,input  logic [3:0]                s_axi_arregion
 ,input  logic                      s_axi_arvalid
 ,output logic                      s_axi_arready
 ,output logic [ID_WIDTH-1:0]       s_axi_rid
 ,output logic [DATA_WIDTH-1:0]     s_axi_rdata
 ,output logic [1:0]                s_axi_rresp
 ,output logic                      s_axi_rlast
 ,output logic                      s_axi_rvalid
 ,input  logic                      s_axi_rready
  //---------------------------------------------------------------------------
  // Master port (下流スレーブへそのまま出す)
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
 ,output logic [3:0]                m_axi_arregion
 ,output logic                      m_axi_arvalid
 ,input  logic                      m_axi_arready
 ,input  logic [ID_WIDTH-1:0]       m_axi_rid
 ,input  logic [DATA_WIDTH-1:0]     m_axi_rdata
 ,input  logic [1:0]                m_axi_rresp
 ,input  logic                      m_axi_rlast
 ,input  logic                      m_axi_rvalid
 ,output logic                      m_axi_rready
);

  //---------------------------------------------------------------------------
  // Local parameters / channel payload types
  //---------------------------------------------------------------------------
  localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;

  typedef struct packed {
    logic [ID_WIDTH-1:0]   id;
    logic [ADDR_WIDTH-1:0] addr;
    logic [7:0]            len;
    logic [2:0]            size;
    logic [1:0]            burst;
    logic                  lock;
    logic [3:0]            cache;
    logic [2:0]            prot;
    logic [3:0]            qos;
    logic [3:0]            region;
  } axi_ax_t;

  typedef struct packed {
    logic [DATA_WIDTH-1:0] data;
    logic [STRB_WIDTH-1:0] strb;
    logic                  last;
  } axi_w_t;

  typedef struct packed {
    logic [ID_WIDTH-1:0] id;
    logic [1:0]          resp;
  } axi_b_t;

  typedef struct packed {
    logic [ID_WIDTH-1:0]   id;
    logic [DATA_WIDTH-1:0] data;
    logic [1:0]            resp;
    logic                  last;
  } axi_r_t;

  axi_ax_t s_aw_pl, m_aw_pl;
  axi_w_t  s_w_pl , m_w_pl;
  axi_b_t  s_b_pl , m_b_pl;
  axi_ax_t s_ar_pl, m_ar_pl;
  axi_r_t  s_r_pl , m_r_pl;

  //---------------------------------------------------------------------------
  // Pack (スレーブポート入力 → ペイロード)
  //---------------------------------------------------------------------------
  assign s_aw_pl = '{ id     : s_axi_awid
                    , addr   : s_axi_awaddr
                    , len    : s_axi_awlen
                    , size   : s_axi_awsize
                    , burst  : s_axi_awburst
                    , lock   : s_axi_awlock
                    , cache  : s_axi_awcache
                    , prot   : s_axi_awprot
                    , qos    : s_axi_awqos
                    , region : s_axi_awregion };

  assign s_w_pl  = '{ data   : s_axi_wdata
                    , strb   : s_axi_wstrb
                    , last   : s_axi_wlast };

  assign s_ar_pl = '{ id     : s_axi_arid
                    , addr   : s_axi_araddr
                    , len    : s_axi_arlen
                    , size   : s_axi_arsize
                    , burst  : s_axi_arburst
                    , lock   : s_axi_arlock
                    , cache  : s_axi_arcache
                    , prot   : s_axi_arprot
                    , qos    : s_axi_arqos
                    , region : s_axi_arregion };

  assign m_b_pl  = '{ id     : m_axi_bid
                    , resp   : m_axi_bresp };

  assign m_r_pl  = '{ id     : m_axi_rid
                    , data   : m_axi_rdata
                    , resp   : m_axi_rresp
                    , last   : m_axi_rlast };

  //---------------------------------------------------------------------------
  // Unpack (ペイロード → 出力ポート)
  //---------------------------------------------------------------------------
  assign m_axi_awid     = m_aw_pl.id;
  assign m_axi_awaddr   = m_aw_pl.addr;
  assign m_axi_awlen    = m_aw_pl.len;
  assign m_axi_awsize   = m_aw_pl.size;
  assign m_axi_awburst  = m_aw_pl.burst;
  assign m_axi_awlock   = m_aw_pl.lock;
  assign m_axi_awcache  = m_aw_pl.cache;
  assign m_axi_awprot   = m_aw_pl.prot;
  assign m_axi_awqos    = m_aw_pl.qos;
  assign m_axi_awregion = m_aw_pl.region;

  assign m_axi_wdata    = m_w_pl.data;
  assign m_axi_wstrb    = m_w_pl.strb;
  assign m_axi_wlast    = m_w_pl.last;

  assign m_axi_arid     = m_ar_pl.id;
  assign m_axi_araddr   = m_ar_pl.addr;
  assign m_axi_arlen    = m_ar_pl.len;
  assign m_axi_arsize   = m_ar_pl.size;
  assign m_axi_arburst  = m_ar_pl.burst;
  assign m_axi_arlock   = m_ar_pl.lock;
  assign m_axi_arcache  = m_ar_pl.cache;
  assign m_axi_arprot   = m_ar_pl.prot;
  assign m_axi_arqos    = m_ar_pl.qos;
  assign m_axi_arregion = m_ar_pl.region;

  assign s_axi_bid      = s_b_pl.id;
  assign s_axi_bresp    = s_b_pl.resp;

  assign s_axi_rid      = s_r_pl.id;
  assign s_axi_rdata    = s_r_pl.data;
  assign s_axi_rresp    = s_r_pl.resp;
  assign s_axi_rlast    = s_r_pl.last;

  //---------------------------------------------------------------------------
  // Write address channel : slave -> master
  //---------------------------------------------------------------------------
  axi4_skid_buffer #(
    .WIDTH($bits(axi_ax_t))
   ,.BYPASS(BYPASS)
  ) u_aw_slice (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.s_data(s_aw_pl)
   ,.s_valid(s_axi_awvalid)
   ,.s_ready(s_axi_awready)
   ,.m_data(m_aw_pl)
   ,.m_valid(m_axi_awvalid)
   ,.m_ready(m_axi_awready)
  );

  //---------------------------------------------------------------------------
  // Write data channel : slave -> master
  //---------------------------------------------------------------------------
  axi4_skid_buffer #(
    .WIDTH($bits(axi_w_t))
   ,.BYPASS(BYPASS)
  ) u_w_slice (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.s_data(s_w_pl)
   ,.s_valid(s_axi_wvalid)
   ,.s_ready(s_axi_wready)
   ,.m_data(m_w_pl)
   ,.m_valid(m_axi_wvalid)
   ,.m_ready(m_axi_wready)
  );

  //---------------------------------------------------------------------------
  // Write response channel : master -> slave
  //---------------------------------------------------------------------------
  axi4_skid_buffer #(
    .WIDTH($bits(axi_b_t))
   ,.BYPASS(BYPASS)
  ) u_b_slice (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.s_data(m_b_pl)
   ,.s_valid(m_axi_bvalid)
   ,.s_ready(m_axi_bready)
   ,.m_data(s_b_pl)
   ,.m_valid(s_axi_bvalid)
   ,.m_ready(s_axi_bready)
  );

  //---------------------------------------------------------------------------
  // Read address channel : slave -> master
  //---------------------------------------------------------------------------
  axi4_skid_buffer #(
    .WIDTH($bits(axi_ax_t))
   ,.BYPASS(BYPASS)
  ) u_ar_slice (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.s_data(s_ar_pl)
   ,.s_valid(s_axi_arvalid)
   ,.s_ready(s_axi_arready)
   ,.m_data(m_ar_pl)
   ,.m_valid(m_axi_arvalid)
   ,.m_ready(m_axi_arready)
  );

  //---------------------------------------------------------------------------
  // Read data channel : master -> slave
  //---------------------------------------------------------------------------
  axi4_skid_buffer #(
    .WIDTH($bits(axi_r_t))
   ,.BYPASS(BYPASS)
  ) u_r_slice (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.s_data(m_r_pl)
   ,.s_valid(m_axi_rvalid)
   ,.s_ready(m_axi_rready)
   ,.m_data(s_r_pl)
   ,.m_valid(s_axi_rvalid)
   ,.m_ready(s_axi_rready)
  );

endmodule
