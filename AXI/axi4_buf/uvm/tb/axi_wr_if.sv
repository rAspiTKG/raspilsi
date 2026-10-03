//=============================================================================
// axi_wr_if.sv
//-----------------------------------------------------------------------------
//  出力側 AXI4 interface (AW / W / B)。DUT がマスタ、テストベンチがスレーブ。
//    - clocking block の考え方は axi_rd_if と同じ
//    - SVA
//        * AWVALID / WVALID は握手成立まで下げない、握手待ちの間はペイロードを変えない
//        * INCR バーストは 4KB 境界を跨がない、バースト長は OUT_MAX_BURST 以下
//        * (設計意図) AW 握手後、WLAST まで WVALID を途切れさせない
//        * テストベンチ側の B も握手まで保持されていること
//=============================================================================
`timescale 1ns / 1ps

interface axi_wr_if (
  input logic aclk
 ,input logic aresetn
);

  import lb_params_pkg::*;

  //---------------------------------------------------------------------------
  // Write address channel
  //---------------------------------------------------------------------------
  logic [OUT_ID_W-1:0]   awid;
  logic [OUT_ADDR_W-1:0] awaddr;
  logic [7:0]            awlen;
  logic [2:0]            awsize;
  logic [1:0]            awburst;
  logic                  awlock;
  logic [3:0]            awcache;
  logic [2:0]            awprot;
  logic [3:0]            awqos;
  logic [3:0]            awregion;
  logic                  awvalid;
  logic                  awready;
  //---------------------------------------------------------------------------
  // Write data channel
  //---------------------------------------------------------------------------
  logic [OUT_DATA_W-1:0] wdata;
  logic [OUT_STRB_W-1:0] wstrb;
  logic                  wlast;
  logic                  wvalid;
  logic                  wready;
  //---------------------------------------------------------------------------
  // Write response channel
  //---------------------------------------------------------------------------
  logic [OUT_ID_W-1:0]   bid;
  logic [1:0]            bresp;
  logic                  bvalid;
  logic                  bready;

  //---------------------------------------------------------------------------
  // Clocking blocks
  //---------------------------------------------------------------------------
  // スレーブ (AW / W を受け、B を返す)
  clocking slv_cb @(posedge aclk);
    default input #1step output #1;
    input  awid, awaddr, awlen, awsize, awburst, awvalid;
    inout  awready;
    input  wdata, wstrb, wlast, wvalid;
    inout  wready;
    output bid, bresp;
    inout  bvalid;
    input  bready;
  endclocking

  // monitor (観測のみ)
  clocking mon_cb @(posedge aclk);
    default input #1step;
    input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion, awvalid, awready;
    input wdata, wstrb, wlast, wvalid, wready;
    input bid, bresp, bvalid, bready;
  endclocking

  modport slv_mp ( clocking slv_cb, input aresetn );
  modport mon_mp ( clocking mon_cb, input aresetn );

  //---------------------------------------------------------------------------
  // プロトコルチェック
  //   失敗は UVM のエラーとして数え、テストを FAIL にする
  //---------------------------------------------------------------------------
`ifndef AXI_IF_NO_SVA
  // バースト送出中の印 (AW 握手の次のサイクルから WLAST 握手まで)
  logic w_open;

  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      w_open <= 1'b0;
    end else begin
      if( awvalid&&awready ) begin
        w_open <= 1'b1;
      end else if( wvalid&&wready&&wlast ) begin
        w_open <= 1'b0;
      end
    end
  end

  // VALID 保持 / ペイロード安定
  a_aw_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      awvalid&&!awready |=> awvalid&&$stable({awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion})
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "AW changed before handshake (master)");
  end

  a_w_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      wvalid&&!wready |=> wvalid&&$stable({wdata, wstrb, wlast})
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "W changed before handshake (master)");
  end

  a_b_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      bvalid&&!bready |=> bvalid&&$stable({bid, bresp})
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "B changed before handshake (slave model)");
  end

  // INCR バーストは 4KB 境界を跨がない
  a_aw_4k : assert property (
    @(posedge aclk) disable iff( !aresetn )
      awvalid&&(awburst==2'b01) |-> ((13'(awaddr[11:0])+((13'(awlen)+13'd1) << awsize))<=13'h1000)
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "AW INCR burst crosses 4KB boundary");
  end

  // バースト長 <= OUT_MAX_BURST
  a_aw_len : assert property (
    @(posedge aclk) disable iff( !aresetn )
      awvalid |-> (32'(awlen)<OUT_MAX_BURST)
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "AWLEN exceeds OUT_MAX_BURST");
  end

  // 設計意図: AW を出したら W を止めない (書き込みチャネルを塞がない)
  a_wvalid_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      w_open |-> wvalid
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "WVALID is low during a write burst");
  end
`endif

endinterface
