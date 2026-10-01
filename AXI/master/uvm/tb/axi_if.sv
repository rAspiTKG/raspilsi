//=============================================================================
// axi_if.sv
//-----------------------------------------------------------------------------
//  AXI4-Full interface (DUT がマスタ、テストベンチがスレーブ)。
//    - clocking block で駆動・サンプルのタイミングを固定する
//        input  #1step : クロックエッジ直前の値をサンプル
//        output #1     : クロックエッジの 1ns 後に駆動 (DUT は次のエッジで取り込む)
//      スレーブ側が出す READY / VALID は inout にして「自分が出した値」もサンプルし、
//      握手は VALID と READY の両方のサンプル値で判定する
//    - SVA でマスタ (DUT) 側の義務をチェックする (AXI4 spec A3.2.1 / A3.4.1)
//        * VALID は握手成立まで下げない、握手待ちの間はペイロードを変えない
//        * INCR バーストは 4KB 境界を跨がない
//        * バースト長は MAX_BURST 以下
//      テストベンチ (スレーブ) 側の B / R も同じ規則でチェックする
//=============================================================================
`timescale 1ns / 1ps

interface axi_if (
  input logic aclk
 ,input logic aresetn
);

  import axi_params_pkg::*;

  //---------------------------------------------------------------------------
  // Write address channel
  //---------------------------------------------------------------------------
  logic [ID_W-1:0]   awid;
  logic [ADDR_W-1:0] awaddr;
  logic [7:0]        awlen;
  logic [2:0]        awsize;
  logic [1:0]        awburst;
  logic              awlock;
  logic [3:0]        awcache;
  logic [2:0]        awprot;
  logic [3:0]        awqos;
  logic [3:0]        awregion;
  logic              awvalid;
  logic              awready;
  //---------------------------------------------------------------------------
  // Write data channel
  //---------------------------------------------------------------------------
  logic [DATA_W-1:0] wdata;
  logic [STRB_W-1:0] wstrb;
  logic              wlast;
  logic              wvalid;
  logic              wready;
  //---------------------------------------------------------------------------
  // Write response channel
  //---------------------------------------------------------------------------
  logic [ID_W-1:0]   bid;
  logic [1:0]        bresp;
  logic              bvalid;
  logic              bready;
  //---------------------------------------------------------------------------
  // Read address channel
  //---------------------------------------------------------------------------
  logic [ID_W-1:0]   arid;
  logic [ADDR_W-1:0] araddr;
  logic [7:0]        arlen;
  logic [2:0]        arsize;
  logic [1:0]        arburst;
  logic              arlock;
  logic [3:0]        arcache;
  logic [2:0]        arprot;
  logic [3:0]        arqos;
  logic [3:0]        arregion;
  logic              arvalid;
  logic              arready;
  //---------------------------------------------------------------------------
  // Read data channel
  //---------------------------------------------------------------------------
  logic [ID_W-1:0]   rid;
  logic [DATA_W-1:0] rdata;
  logic [1:0]        rresp;
  logic              rlast;
  logic              rvalid;
  logic              rready;

  //---------------------------------------------------------------------------
  // Clocking blocks
  //---------------------------------------------------------------------------
  // スレーブ Write 側 (AW / W を受け、B を返す)
  clocking wr_cb @(posedge aclk);
    default input #1step output #1;
    input  awid, awaddr, awlen, awsize, awburst, awvalid;
    inout  awready;
    input  wdata, wstrb, wlast, wvalid;
    inout  wready;
    output bid, bresp;
    inout  bvalid;
    input  bready;
  endclocking

  // スレーブ Read 側 (AR を受け、R を返す)
  clocking rd_cb @(posedge aclk);
    default input #1step output #1;
    input  arid, araddr, arlen, arsize, arburst, arvalid;
    inout  arready;
    output rid, rdata, rresp, rlast;
    inout  rvalid;
    input  rready;
  endclocking

  // monitor (観測のみ)
  clocking mon_cb @(posedge aclk);
    default input #1step;
    input awid, awaddr, awlen, awsize, awburst, awvalid, awready;
    input wdata, wstrb, wlast, wvalid, wready;
    input bid, bresp, bvalid, bready;
    input arid, araddr, arlen, arsize, arburst, arvalid, arready;
    input rid, rdata, rresp, rlast, rvalid, rready;
  endclocking

  modport wr_slv_mp ( clocking wr_cb, input aresetn );
  modport rd_slv_mp ( clocking rd_cb, input aresetn );
  modport mon_mp    ( clocking mon_cb, input aresetn );

  //---------------------------------------------------------------------------
  // プロトコルチェック
  //   失敗は UVM のエラーとして数え、テストを FAIL にする
  //---------------------------------------------------------------------------
`ifndef AXI_IF_NO_SVA
  // VALID 保持 / ペイロード安定 (A3.2.1)
  a_aw_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      awvalid&&!awready |=> awvalid&&$stable({awid, awaddr, awlen, awsize, awburst})
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "AW changed before handshake (master)");
  end

  a_w_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      wvalid&&!wready |=> wvalid&&$stable({wdata, wstrb, wlast})
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "W changed before handshake (master)");
  end

  a_ar_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      arvalid&&!arready |=> arvalid&&$stable({arid, araddr, arlen, arsize, arburst})
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "AR changed before handshake (master)");
  end

  a_b_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      bvalid&&!bready |=> bvalid&&$stable({bid, bresp})
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "B changed before handshake (slave model)");
  end

  a_r_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      rvalid&&!rready |=> rvalid&&$stable({rid, rdata, rresp, rlast})
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "R changed before handshake (slave model)");
  end

  // INCR バーストは 4KB 境界を跨がない (A3.4.1)
  a_aw_4k : assert property (
    @(posedge aclk) disable iff( !aresetn )
      awvalid&&(awburst==2'b01) |-> ((13'(awaddr[11:0])+((13'(awlen)+13'd1) << awsize))<=13'h1000)
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "AW INCR burst crosses 4KB boundary");
  end

  a_ar_4k : assert property (
    @(posedge aclk) disable iff( !aresetn )
      arvalid&&(arburst==2'b01) |-> ((13'(araddr[11:0])+((13'(arlen)+13'd1) << arsize))<=13'h1000)
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "AR INCR burst crosses 4KB boundary");
  end

  // バースト長 <= MAX_BURST
  a_aw_len : assert property (
    @(posedge aclk) disable iff( !aresetn )
      awvalid |-> (32'(awlen)<MAX_BURST)
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "AWLEN exceeds MAX_BURST");
  end

  a_ar_len : assert property (
    @(posedge aclk) disable iff( !aresetn )
      arvalid |-> (32'(arlen)<MAX_BURST)
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "ARLEN exceeds MAX_BURST");
  end
`endif

endinterface
