//=============================================================================
// axi_if.sv
//-----------------------------------------------------------------------------
//  AXI4 interface (axil_to_axi4 のマスタ側)。DUT (+ 変換) がマスタ (Manager)、
//  テストベンチがスレーブ (Subordinate)。AXI5 の AWAKEUP も含む。
//
//    - clocking block で駆動・サンプルのタイミングを固定する
//        input  #1step : クロックエッジ直前の値をサンプル
//        output #1     : クロックエッジの 1ns 後に駆動 (DUT は次のエッジで取り込む)
//    - SVA (AMBA AXI Protocol Specification, Arm IHI 0022)
//        * リセット中と、リセット解除後の最初のエッジまでは AWVALID / WVALID / ARVALID = 0
//        * VALID は READY まで下げず、その間ペイロードを変えない (AW / W / AR、B / R はスレーブ側)
//        * AXI4-Lite 相当であること: AxLEN=0、AxSIZE=データ幅、AxBURST=INCR、AxLOCK=0、
//          AxCACHE=0000、AxID=0、WLAST=1、AxQOS=パラメータ、アドレスはデータ幅にアライン
//        * BREADY / RREADY は常に 1 (この DUT の作り)
//        * AWAKEUP : AWVALID / WVALID / ARVALID が 1、または未完了のトランザクションがあれば 1
//        * バス上の未完了数 (AW / W / AR を受けてから B / R まで) が MAX_WR / MAX_RD 以下
//=============================================================================
`timescale 1ns / 1ps

interface axi_if (
  input logic aclk
 ,input logic aresetn
);

  import axlm_params_pkg::*;

  //---------------------------------------------------------------------------
  // 書き込みアドレス / データ / 応答
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
  logic              awvalid;
  logic              awready;
  logic [DATA_W-1:0] wdata;
  logic [STRB_W-1:0] wstrb;
  logic              wlast;
  logic              wvalid;
  logic              wready;
  logic [ID_W-1:0]   bid;
  logic [1:0]        bresp;
  logic              bvalid;
  logic              bready;
  //---------------------------------------------------------------------------
  // 読み出しアドレス / データ
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
  logic              arvalid;
  logic              arready;
  logic [ID_W-1:0]   rid;
  logic [DATA_W-1:0] rdata;
  logic [1:0]        rresp;
  logic              rlast;
  logic              rvalid;
  logic              rready;
  //---------------------------------------------------------------------------
  // AXI5 wakeup
  //---------------------------------------------------------------------------
  logic              awakeup;

  //---------------------------------------------------------------------------
  // Clocking blocks
  //---------------------------------------------------------------------------
  // スレーブ (responder)
  clocking slv_cb @(posedge aclk);
    default input #1step output #1;
    input  awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid;
    output awready;
    input  wdata, wstrb, wlast, wvalid;
    output wready;
    output bid, bresp, bvalid;
    input  bready;
    input  arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid;
    output arready;
    output rid, rdata, rresp, rlast, rvalid;
    input  rready;
    input  awakeup;
  endclocking

  // monitor (観測のみ)
  clocking mon_cb @(posedge aclk);
    default input #1step;
    input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid, awready;
    input wdata, wstrb, wlast, wvalid, wready;
    input bid, bresp, bvalid, bready;
    input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid, arready;
    input rid, rdata, rresp, rlast, rvalid, rready;
    input awakeup;
  endclocking

  modport slv_mp ( clocking slv_cb, input aresetn );
  modport mon_mp ( clocking mon_cb, input aresetn );

  //---------------------------------------------------------------------------
  // バス上の未完了数 (SVA と AWAKEUP の確認用)
  //---------------------------------------------------------------------------
  int unsigned wr_out;      // AW を受けてから B を返し終えるまで
  int unsigned w_out;       // W を受けてから B を返し終えるまで
  int unsigned rd_out;      // AR を受けてから R を返し終えるまで

  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      wr_out <= 0;
      w_out  <= 0;
      rd_out <= 0;
    end else begin
      wr_out <= wr_out + 32'(awvalid&&awready) - 32'(bvalid&&bready);
      w_out  <= w_out + 32'(wvalid&&wready) - 32'(bvalid&&bready);
      rd_out <= rd_out + 32'(arvalid&&arready) - 32'(rvalid&&rready);
    end
  end

  //---------------------------------------------------------------------------
  // プロトコルチェック
  //   失敗は UVM のエラーとして数え、テストを FAIL にする
  //---------------------------------------------------------------------------
`ifndef AXI_IF_NO_SVA
  a_reset_valid : assert property (
    @(posedge aclk)
      !aresetn |-> !awvalid&&!wvalid&&!arvalid
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "AWVALID / WVALID / ARVALID is high during reset");
  end

  a_first_valid : assert property (
    @(posedge aclk)
      $rose(aresetn) |-> !awvalid&&!wvalid&&!arvalid
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "AWVALID / WVALID / ARVALID is high at the first edge after reset");
  end

  // VALID は READY まで下げず、ペイロードも変えない
  a_aw_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      awvalid&&!awready |=> awvalid&&$stable({awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos})
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "AWVALID dropped or AW payload changed before AWREADY");
  end

  a_w_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      wvalid&&!wready |=> wvalid&&$stable({wdata, wstrb, wlast})
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "WVALID dropped or W payload changed before WREADY");
  end

  a_ar_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      arvalid&&!arready |=> arvalid&&$stable({arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos})
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "ARVALID dropped or AR payload changed before ARREADY");
  end

  // スレーブ側 (テストベンチ) の規則
  a_b_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      bvalid&&!bready |=> bvalid&&$stable({bid, bresp})
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "BVALID dropped or B payload changed before BREADY (testbench)");
  end

  a_r_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      rvalid&&!rready |=> rvalid&&$stable({rid, rdata, rresp, rlast})
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "RVALID dropped or R payload changed before RREADY (testbench)");
  end

  // AXI4-Lite 相当の固定値
  a_aw_lite : assert property (
    @(posedge aclk) disable iff( !aresetn )
      awvalid |-> (awid=={ID_W{1'b0}})&&(awlen==8'd0)&&(awsize==SIZE_FULL)&&(awburst==2'b01)&&!awlock&&(awcache==4'b0000)&&(awqos==QOS)
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "AW is not an AXI4-Lite style transaction (ID / LEN / SIZE / BURST / LOCK / CACHE / QOS)");
  end

  a_w_last : assert property (
    @(posedge aclk) disable iff( !aresetn )
      wvalid |-> wlast
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "WLAST is low (every write has one beat)");
  end

  a_ar_lite : assert property (
    @(posedge aclk) disable iff( !aresetn )
      arvalid |-> (arid=={ID_W{1'b0}})&&(arlen==8'd0)&&(arsize==SIZE_FULL)&&(arburst==2'b01)&&!arlock&&(arcache==4'b0000)&&(arqos==QOS)
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "AR is not an AXI4-Lite style transaction (ID / LEN / SIZE / BURST / LOCK / CACHE / QOS)");
  end

  a_aw_aligned : assert property (
    @(posedge aclk) disable iff( !aresetn )
      awvalid |-> ((awaddr&ADDR_W'(STRB_W-1))=={ADDR_W{1'b0}})
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "AWADDR is not aligned to the data width");
  end

  a_ar_aligned : assert property (
    @(posedge aclk) disable iff( !aresetn )
      arvalid |-> ((araddr&ADDR_W'(STRB_W-1))=={ADDR_W{1'b0}})
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "ARADDR is not aligned to the data width");
  end

  // この DUT は応答を待たせない
  a_resp_ready : assert property (
    @(posedge aclk) disable iff( !aresetn )
      bready&&rready
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "BREADY / RREADY is low");
  end

  // AWAKEUP
  a_wakeup_valid : assert property (
    @(posedge aclk) disable iff( !aresetn )
      awvalid||wvalid||arvalid |-> awakeup
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "AWAKEUP is low while AWVALID / WVALID / ARVALID is high");
  end

  a_wakeup_out : assert property (
    @(posedge aclk) disable iff( !aresetn )
      (wr_out!=0)||(w_out!=0)||(rd_out!=0) |-> awakeup
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "AWAKEUP is low while transactions are outstanding");
  end

  // 未完了数
  a_wr_outstanding : assert property (
    @(posedge aclk) disable iff( !aresetn )
      (wr_out<=MAX_WR)&&(w_out<=MAX_WR)
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", $sformatf("too many outstanding writes on the bus : AW %0d / W %0d (max %0d)", wr_out, w_out, MAX_WR));
  end

  a_rd_outstanding : assert property (
    @(posedge aclk) disable iff( !aresetn )
      rd_out<=MAX_RD
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", $sformatf("too many outstanding reads on the bus : %0d (max %0d)", rd_out, MAX_RD));
  end

  a_no_x : assert property (
    @(posedge aclk) disable iff( !aresetn )
      !$isunknown({awvalid, wvalid, arvalid, bready, rready, awakeup})
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "VALID / READY / AWAKEUP is X");
  end
`endif

endinterface
