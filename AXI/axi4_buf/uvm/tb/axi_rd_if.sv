//=============================================================================
// axi_rd_if.sv
//-----------------------------------------------------------------------------
//  入力側 AXI4 interface (AR / R)。DUT がマスタ、テストベンチがスレーブ。
//    - clocking block で駆動・サンプルのタイミングを固定する
//        input  #1step : クロックエッジ直前の値をサンプル
//        output #1     : クロックエッジの 1ns 後に駆動 (DUT は次のエッジで取り込む)
//      スレーブが出す ARREADY / RVALID は inout にして「自分が出した値」も
//      サンプルし、握手は VALID と READY の両方のサンプル値で判定する
//    - SVA
//        * ARVALID は握手成立まで下げない、握手待ちの間はペイロードを変えない
//        * INCR バーストは 4KB 境界を跨がない、バースト長は IN_MAX_BURST 以下
//        * (設計意図) バーストの途中で RREADY を下げない
//        * テストベンチ側の R も握手まで保持されていること
//=============================================================================
`timescale 1ns / 1ps

interface axi_rd_if (
  input logic aclk
 ,input logic aresetn
);

  import lb_params_pkg::*;

  //---------------------------------------------------------------------------
  // Read address channel
  //---------------------------------------------------------------------------
  logic [IN_ID_W-1:0]   arid;
  logic [IN_ADDR_W-1:0] araddr;
  logic [7:0]           arlen;
  logic [2:0]           arsize;
  logic [1:0]           arburst;
  logic                 arlock;
  logic [3:0]           arcache;
  logic [2:0]           arprot;
  logic [3:0]           arqos;
  logic [3:0]           arregion;
  logic                 arvalid;
  logic                 arready;
  //---------------------------------------------------------------------------
  // Read data channel
  //---------------------------------------------------------------------------
  logic [IN_ID_W-1:0]   rid;
  logic [IN_DATA_W-1:0] rdata;
  logic [1:0]           rresp;
  logic                 rlast;
  logic                 rvalid;
  logic                 rready;

  //---------------------------------------------------------------------------
  // Clocking blocks
  //---------------------------------------------------------------------------
  // スレーブ (AR を受け、R を返す)
  clocking slv_cb @(posedge aclk);
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
    input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion, arvalid, arready;
    input rid, rdata, rresp, rlast, rvalid, rready;
  endclocking

  modport slv_mp ( clocking slv_cb, input aresetn );
  modport mon_mp ( clocking mon_cb, input aresetn );

  //---------------------------------------------------------------------------
  // プロトコルチェック
  //   失敗は UVM のエラーとして数え、テストを FAIL にする
  //---------------------------------------------------------------------------
`ifndef AXI_IF_NO_SVA
  // バースト受信中の印 (AR 握手の次のサイクルから RLAST 握手まで)
  logic r_open;

  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      r_open <= 1'b0;
    end else begin
      if( arvalid&&arready ) begin
        r_open <= 1'b1;
      end else if( rvalid&&rready&&rlast ) begin
        r_open <= 1'b0;
      end
    end
  end

  // VALID 保持 / ペイロード安定
  a_ar_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      arvalid&&!arready |=> arvalid&&$stable({arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion})
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "AR changed before handshake (master)");
  end

  a_r_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      rvalid&&!rready |=> rvalid&&$stable({rid, rdata, rresp, rlast})
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "R changed before handshake (slave model)");
  end

  // INCR バーストは 4KB 境界を跨がない
  a_ar_4k : assert property (
    @(posedge aclk) disable iff( !aresetn )
      arvalid&&(arburst==2'b01) |-> ((13'(araddr[11:0])+((13'(arlen)+13'd1) << arsize))<=13'h1000)
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "AR INCR burst crosses 4KB boundary");
  end

  // バースト長 <= IN_MAX_BURST
  a_ar_len : assert property (
    @(posedge aclk) disable iff( !aresetn )
      arvalid |-> (32'(arlen)<IN_MAX_BURST)
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "ARLEN exceeds IN_MAX_BURST");
  end

  // 設計意図: バーストの途中で RREADY を下げない (読み出しチャネルを塞がない)
  a_rready_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      r_open |-> rready
  ) else begin
    uvm_pkg::uvm_report_error("AXI_SVA", "RREADY is low during a read burst");
  end
`endif

endinterface
