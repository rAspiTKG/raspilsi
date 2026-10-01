//=============================================================================
// axi4_full_master_bfm.sv
//-----------------------------------------------------------------------------
//  検証用の簡易 AXI4-Full マスタ BFM。
//  write_burst() / read_burst() タスクで 1 本のバーストを流す。
//    - 送信データ : wr_buf[]  / 送信 WSTRB : wr_strb_buf[]
//    - 受信データ : rd_buf[]
//    - 応答       : last_bid / last_bresp / last_rid / last_rresp
//    - RLAST の位置チェック結果 : last_rlast_ok
//
//  タイミング規約 (シミュレータ非依存にするため):
//    - 駆動   : negedge aclk で更新する。DUT が観測する posedge では既に安定。
//    - 観測   : 握手 (VALID&&READY) を posedge の always_ff でサンプルし、
//               その結果 (xx_hs) を negedge でポーリングする。
//               実ハードと同じ観測点になるため評価順序に依存しない。
//
//  VALID は READY を待たずにアサートし、握手が成立するまで下げない
//  (AXI4 spec A3.2.1: https://developer.arm.com/documentation/ihi0022/latest/)。
//=============================================================================
`timescale 1ns / 1ps

module axi4_full_master_bfm #(
  parameter int unsigned ADDR_WIDTH = 32
 ,parameter int unsigned DATA_WIDTH = 64
 ,parameter int unsigned ID_WIDTH   = 4
) (
  input  logic                      aclk
 ,input  logic                      aresetn
  // Write address channel
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
  // Write data channel
 ,output logic [DATA_WIDTH-1:0]     m_axi_wdata
 ,output logic [(DATA_WIDTH/8)-1:0] m_axi_wstrb
 ,output logic                      m_axi_wlast
 ,output logic                      m_axi_wvalid
 ,input  logic                      m_axi_wready
  // Write response channel
 ,input  logic [ID_WIDTH-1:0]       m_axi_bid
 ,input  logic [1:0]                m_axi_bresp
 ,input  logic                      m_axi_bvalid
 ,output logic                      m_axi_bready
  // Read address channel
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
  // Read data channel
 ,input  logic [ID_WIDTH-1:0]       m_axi_rid
 ,input  logic [DATA_WIDTH-1:0]     m_axi_rdata
 ,input  logic [1:0]                m_axi_rresp
 ,input  logic                      m_axi_rlast
 ,input  logic                      m_axi_rvalid
 ,output logic                      m_axi_rready
);

  localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;

  //---------------------------------------------------------------------------
  // テストベンチから参照するバッファ / 結果
  //---------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] wr_buf      [0:255];
  logic [STRB_WIDTH-1:0] wr_strb_buf [0:255];
  logic [DATA_WIDTH-1:0] rd_buf      [0:255];
  logic [ID_WIDTH-1:0]   last_bid;
  logic [1:0]            last_bresp;
  logic [ID_WIDTH-1:0]   last_rid;
  logic [1:0]            last_rresp;
  logic                  last_rlast_ok;

  //---------------------------------------------------------------------------
  // 握手サンプラ (posedge で観測する。実ハードのフリップフロップと同じ)
  //---------------------------------------------------------------------------
  logic                  aw_hs;
  logic                  w_hs;
  logic                  b_hs;
  logic                  ar_hs;
  logic                  r_hs;
  logic [ID_WIDTH-1:0]   b_id_q;
  logic [1:0]            b_resp_q;
  logic [ID_WIDTH-1:0]   r_id_q;
  logic [DATA_WIDTH-1:0] r_data_q;
  logic [1:0]            r_resp_q;
  logic                  r_last_q;

  always_ff @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      aw_hs    <= 1'b0;
      w_hs     <= 1'b0;
      b_hs     <= 1'b0;
      ar_hs    <= 1'b0;
      r_hs     <= 1'b0;
      b_id_q   <= {ID_WIDTH{1'b0}};
      b_resp_q <= 2'b00;
      r_id_q   <= {ID_WIDTH{1'b0}};
      r_data_q <= {DATA_WIDTH{1'b0}};
      r_resp_q <= 2'b00;
      r_last_q <= 1'b0;
    end else begin
      aw_hs <= m_axi_awvalid&&m_axi_awready;
      w_hs  <= m_axi_wvalid&&m_axi_wready;
      b_hs  <= m_axi_bvalid&&m_axi_bready;
      ar_hs <= m_axi_arvalid&&m_axi_arready;
      r_hs  <= m_axi_rvalid&&m_axi_rready;
      if( m_axi_bvalid&&m_axi_bready ) begin
        b_id_q   <= m_axi_bid;
        b_resp_q <= m_axi_bresp;
      end
      if( m_axi_rvalid&&m_axi_rready ) begin
        r_id_q   <= m_axi_rid;
        r_data_q <= m_axi_rdata;
        r_resp_q <= m_axi_rresp;
        r_last_q <= m_axi_rlast;
      end
    end
  end

  //---------------------------------------------------------------------------
  // 初期化
  //---------------------------------------------------------------------------
  task automatic init();
    begin
      m_axi_awid     = {ID_WIDTH{1'b0}};
      m_axi_awaddr   = {ADDR_WIDTH{1'b0}};
      m_axi_awlen    = 8'd0;
      m_axi_awsize   = 3'd0;
      m_axi_awburst  = 2'b01;
      m_axi_awlock   = 1'b0;
      m_axi_awcache  = 4'b0011;
      m_axi_awprot   = 3'b000;
      m_axi_awqos    = 4'd0;
      m_axi_awregion = 4'd0;
      m_axi_awvalid  = 1'b0;
      m_axi_wdata    = {DATA_WIDTH{1'b0}};
      m_axi_wstrb    = {STRB_WIDTH{1'b0}};
      m_axi_wlast    = 1'b0;
      m_axi_wvalid   = 1'b0;
      m_axi_bready   = 1'b0;
      m_axi_arid     = {ID_WIDTH{1'b0}};
      m_axi_araddr   = {ADDR_WIDTH{1'b0}};
      m_axi_arlen    = 8'd0;
      m_axi_arsize   = 3'd0;
      m_axi_arburst  = 2'b01;
      m_axi_arlock   = 1'b0;
      m_axi_arcache  = 4'b0011;
      m_axi_arprot   = 3'b000;
      m_axi_arqos    = 4'd0;
      m_axi_arregion = 4'd0;
      m_axi_arvalid  = 1'b0;
      m_axi_rready   = 1'b0;
      last_bid       = {ID_WIDTH{1'b0}};
      last_bresp     = 2'b00;
      last_rid       = {ID_WIDTH{1'b0}};
      last_rresp     = 2'b00;
      last_rlast_ok  = 1'b1;
      for( int unsigned i=0; i<256; i++ ) begin
        wr_buf[i]      = {DATA_WIDTH{1'b0}};
        wr_strb_buf[i] = {STRB_WIDTH{1'b1}};
        rd_buf[i]      = {DATA_WIDTH{1'b0}};
      end
    end
  endtask

  initial begin
    init();
  end

  task automatic wait_clk( input int unsigned n );
    begin
      for( int unsigned i=0; i<n; i++ ) begin
        @(posedge aclk);
      end
    end
  endtask

  //---------------------------------------------------------------------------
  // Write バースト (AW → W → B)
  //---------------------------------------------------------------------------
  task automatic write_burst
  (
    input logic [ADDR_WIDTH-1:0] addr
   ,input logic [7:0]            len
   ,input logic [2:0]            size
   ,input logic [1:0]            burst
   ,input logic [ID_WIDTH-1:0]   id
  );
    begin
      // --- AW channel ---
      @(negedge aclk);
      m_axi_awid    = id;
      m_axi_awaddr  = addr;
      m_axi_awlen   = len;
      m_axi_awsize  = size;
      m_axi_awburst = burst;
      m_axi_awvalid = 1'b1;
      @(negedge aclk);
      while( !aw_hs ) begin
        @(negedge aclk);
      end
      m_axi_awvalid = 1'b0;

      // --- W channel ---
      for( int unsigned i=0; i<=len; i++ ) begin
        m_axi_wdata  = wr_buf[i];
        m_axi_wstrb  = wr_strb_buf[i];
        m_axi_wlast  = (i=={24'd0,len});
        m_axi_wvalid = 1'b1;
        @(negedge aclk);
        while( !w_hs ) begin
          @(negedge aclk);
        end
      end
      m_axi_wvalid = 1'b0;
      m_axi_wlast  = 1'b0;

      // --- B channel ---
      m_axi_bready = 1'b1;
      @(negedge aclk);
      while( !b_hs ) begin
        @(negedge aclk);
      end
      m_axi_bready = 1'b0;
      last_bid     = b_id_q;
      last_bresp   = b_resp_q;
    end
  endtask

  //---------------------------------------------------------------------------
  // Read バースト (AR → R)
  //---------------------------------------------------------------------------
  task automatic read_burst
  (
    input logic [ADDR_WIDTH-1:0] addr
   ,input logic [7:0]            len
   ,input logic [2:0]            size
   ,input logic [1:0]            burst
   ,input logic [ID_WIDTH-1:0]   id
  );
    begin
      // --- AR channel ---
      @(negedge aclk);
      m_axi_arid    = id;
      m_axi_araddr  = addr;
      m_axi_arlen   = len;
      m_axi_arsize  = size;
      m_axi_arburst = burst;
      m_axi_arvalid = 1'b1;
      @(negedge aclk);
      while( !ar_hs ) begin
        @(negedge aclk);
      end
      m_axi_arvalid = 1'b0;

      // --- R channel ---
      last_rlast_ok = 1'b1;
      m_axi_rready  = 1'b1;
      for( int unsigned i=0; i<=len; i++ ) begin
        @(negedge aclk);
        while( !r_hs ) begin
          @(negedge aclk);
        end
        rd_buf[i]  = r_data_q;
        last_rid   = r_id_q;
        last_rresp = r_resp_q;
        if( r_last_q!=(i=={24'd0,len}) ) begin
          last_rlast_ok = 1'b0;
        end
      end
      m_axi_rready = 1'b0;
    end
  endtask

endmodule
