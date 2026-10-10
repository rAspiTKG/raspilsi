//=============================================================================
// apb_if.sv
//-----------------------------------------------------------------------------
//  APB interface。DUT がマスタ (Requester)、テストベンチがスレーブ (Completer)。
//  PADDR / PWDATA などは全スレーブ共通、PSEL / PREADY / PRDATA / PSLVERR はスレーブごと
//  (スレーブ s の PRDATA は prdata[s*DATA_W +: DATA_W])。
//
//    - clocking block で駆動・サンプルのタイミングを固定する
//        input  #1step : クロックエッジ直前の値をサンプル
//        output #1     : クロックエッジの 1ns 後に駆動 (DUT は次のエッジで取り込む)
//    - SVA (AMBA APB Protocol Specification, Arm IHI 0024E)
//        * PSEL は同時に 2 本以上立たない。PENABLE=1 のときはちょうど 1 本
//        * SETUP (PSEL=1, PENABLE=0) は 1 サイクルで、次は同じ PSEL の ACCESS
//        * SETUP から完了まで PADDR / PPROT / PWRITE / PSTRB / PWDATA (書き込み) を変えない
//        * PREADY=0 の間は PSEL / PENABLE を保つ
//          (TIMEOUT_CYCLES > 0 のときは、ちょうど上限のサイクルでだけ打ち切ってよく、
//           そのサイクルでは必ず打ち切る)
//        * 完了の次のサイクルは PENABLE=0
//        * 読み出しでは PSTRB=0
//        * PADDR はデータ幅にアライン (DUT が非アラインのコマンドを断るため)
//=============================================================================
`timescale 1ns / 1ps

interface apb_if (
  input logic pclk
 ,input logic presetn
);

  import apbm_params_pkg::*;

  //---------------------------------------------------------------------------
  // マスタ → スレーブ
  //---------------------------------------------------------------------------
  logic [ADDR_W-1:0]              paddr;
  logic [2:0]                     pprot;
  logic [NUM_SLAVES-1:0]          psel;
  logic                           penable;
  logic                           pwrite;
  logic [DATA_W-1:0]              pwdata;
  logic [STRB_W-1:0]              pstrb;
  //---------------------------------------------------------------------------
  // スレーブ → マスタ
  //---------------------------------------------------------------------------
  logic [NUM_SLAVES-1:0]          pready;
  logic [(NUM_SLAVES*DATA_W)-1:0] prdata;
  logic [NUM_SLAVES-1:0]          pslverr;

  //---------------------------------------------------------------------------
  // Clocking blocks
  //---------------------------------------------------------------------------
  // スレーブ (全スレーブぶんをまとめて応答する)
  clocking slv_cb @(posedge pclk);
    default input #1step output #1;
    input  paddr, pprot, psel, penable, pwrite, pwdata, pstrb;
    output pready, prdata, pslverr;
  endclocking

  // monitor (観測のみ)
  clocking mon_cb @(posedge pclk);
    default input #1step;
    input paddr, pprot, psel, penable, pwrite, pwdata, pstrb, pready, prdata, pslverr;
  endclocking

  modport slv_mp ( clocking slv_cb, input presetn );
  modport mon_mp ( clocking mon_cb, input presetn );

  //---------------------------------------------------------------------------
  // プロトコルチェック
  //   失敗は UVM のエラーとして数え、テストを FAIL にする
  //---------------------------------------------------------------------------
`ifndef APB_IF_NO_SVA
  logic        sel_any;       // どれかのスレーブが選択されている
  logic        pready_sel;    // 選択中のスレーブの PREADY
  logic        at_limit;      // タイムアウトの上限のサイクル
  int unsigned acc_cnt;       // ACCESS に入ってからのサイクル数 (最初の ACCESS サイクルで 0)

  assign sel_any    = |psel;
  assign pready_sel = |(psel&pready);
  assign at_limit   = (TIMEOUT_CYCLES>0)&&(acc_cnt==(TIMEOUT_CYCLES-1));

  always @(posedge pclk or negedge presetn) begin
    if( !presetn ) begin
      acc_cnt <= 0;
    end else begin
      if( sel_any&&penable ) begin
        acc_cnt <= acc_cnt + 1;
      end else begin
        acc_cnt <= 0;
      end
    end
  end

  a_psel_onehot : assert property (
    @(posedge pclk) disable iff( !presetn )
      $onehot0(psel)
  ) else begin
    uvm_pkg::uvm_report_error("APB_SVA", "more than one PSEL is asserted");
  end

  a_penable_psel : assert property (
    @(posedge pclk) disable iff( !presetn )
      penable |-> $onehot(psel)
  ) else begin
    uvm_pkg::uvm_report_error("APB_SVA", "PENABLE is asserted without PSEL");
  end

  // SETUP の次は、同じ PSEL のままの ACCESS
  a_setup_access : assert property (
    @(posedge pclk) disable iff( !presetn )
      sel_any&&!penable |=> penable&&$stable(psel)
  ) else begin
    uvm_pkg::uvm_report_error("APB_SVA", "SETUP was not followed by ACCESS of the same slave");
  end

  a_setup_stable : assert property (
    @(posedge pclk) disable iff( !presetn )
      sel_any&&!penable |=> $stable({paddr, pprot, pwrite, pstrb})
  ) else begin
    uvm_pkg::uvm_report_error("APB_SVA", "PADDR / PPROT / PWRITE / PSTRB changed between SETUP and ACCESS");
  end

  a_setup_wdata : assert property (
    @(posedge pclk) disable iff( !presetn )
      sel_any&&!penable&&pwrite |=> $stable(pwdata)
  ) else begin
    uvm_pkg::uvm_report_error("APB_SVA", "PWDATA changed between SETUP and ACCESS");
  end

  // ウェイト中は PSEL / PENABLE と制御を保つ (タイムアウトの上限のサイクルを除く)
  a_wait_hold : assert property (
    @(posedge pclk) disable iff( !presetn )
      sel_any&&penable&&!pready_sel&&!at_limit |=> penable&&$stable({psel, paddr, pprot, pwrite, pstrb})
  ) else begin
    uvm_pkg::uvm_report_error("APB_SVA", "PSEL / PENABLE / PADDR / PPROT / PWRITE / PSTRB changed while PREADY is low");
  end

  a_wait_wdata : assert property (
    @(posedge pclk) disable iff( !presetn )
      sel_any&&penable&&!pready_sel&&!at_limit&&pwrite |=> $stable(pwdata)
  ) else begin
    uvm_pkg::uvm_report_error("APB_SVA", "PWDATA changed while PREADY is low");
  end

  // タイムアウトの上限のサイクルで PREADY が来なければ、次のサイクルは PENABLE=0 (打ち切り)
  a_timeout_abort : assert property (
    @(posedge pclk) disable iff( !presetn )
      sel_any&&penable&&!pready_sel&&at_limit |=> !penable
  ) else begin
    uvm_pkg::uvm_report_error("APB_SVA", "the transfer was not aborted at the timeout limit");
  end

  // 完了の次のサイクルは PENABLE=0
  a_done_penable : assert property (
    @(posedge pclk) disable iff( !presetn )
      sel_any&&penable&&pready_sel |=> !penable
  ) else begin
    uvm_pkg::uvm_report_error("APB_SVA", "PENABLE was not deasserted after the transfer completed");
  end

  a_pstrb_read : assert property (
    @(posedge pclk) disable iff( !presetn )
      sel_any&&!pwrite |-> (pstrb=={STRB_W{1'b0}})
  ) else begin
    uvm_pkg::uvm_report_error("APB_SVA", "PSTRB is not 0 on a read transfer");
  end

  a_paddr_aligned : assert property (
    @(posedge pclk) disable iff( !presetn )
      sel_any |-> ((paddr&ADDR_W'(STRB_W-1))=={ADDR_W{1'b0}})
  ) else begin
    uvm_pkg::uvm_report_error("APB_SVA", "PADDR is not aligned to the data width");
  end

  a_no_x : assert property (
    @(posedge pclk) disable iff( !presetn )
      !$isunknown({psel, penable})
  ) else begin
    uvm_pkg::uvm_report_error("APB_SVA", "PSEL / PENABLE is X");
  end
`endif

endinterface
