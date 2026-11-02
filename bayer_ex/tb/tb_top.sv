// ============================================================================
// tb_top : BAYER_EX の検証環境のトップ
//   DUT は BAYER_EX_CORE(既定)。+define+BEX_DUT_TOP で BAYER_EX(合成のトップ)にする。
//   プラスアーグ
//     +CLK_PS=<ps>   clk の周期(既定 2500ps = 400MHz)
//     +WAVES         波形を出す(Verilator: waves.fst(TRACE=vcd でビルドしたときは waves.vcd)、
//                    その他のシミュレータ: waves.vcd)。どれも GTKWave で開ける
// ============================================================================
`timescale 1ns/1ps

module tb_top;
  import uvm_pkg::*;
  import BAYER_EX_PKG::*;
  import bex_tb_pkg::*;

  logic    clk;
  logic    rst_n;
  int      clk_ps;
  realtime clk_half;

  // --------------------------------------------------------------------------
  // クロック
  // --------------------------------------------------------------------------
  initial begin
    if( !$value$plusargs("CLK_PS=%d",clk_ps) ) begin
      clk_ps = 2500;
    end
    clk_half = clk_ps/2000.0;
    clk      = 1'b0;
  end

  initial begin
    #0.1;
    forever begin
      #(clk_half);
      clk = ~clk;
    end
  end

  // --------------------------------------------------------------------------
  // インタフェース
  // --------------------------------------------------------------------------
  bex_vbd_if in_if (
    .clk   (clk)
   ,.rst_n (rst_n)
  );

  bex_vbd_if out_if (
    .clk   (clk)
   ,.rst_n (rst_n)
  );

  bex_misc_if misc (
    .clk   (clk)
   ,.rst_n (rst_n)
  );

  // --------------------------------------------------------------------------
  // リセット(非同期アサート・同期解除)
  //   時刻0から20クロック。テストの要求(misc.rst_req の立ち上がり)でも、
  //   クロックと関係のない時刻にかけ、5クロック後の立ち上がりで解除する。
  //   最初のクロックの前に立ち下がりを作り、非同期リセットを確実にかける
  //   (2値のシミュレータでは、初期値が0だと時刻0の代入で立ち下がりが起きないため)
  // --------------------------------------------------------------------------
  initial begin
    misc.rst_req = 1'b0;
    rst_n        = 1'b1;
    #0.05;
    rst_n = 1'b0;
    repeat( 20 ) begin
      @(posedge clk);
    end
    rst_n <= 1'b1;
    forever begin
      @(posedge misc.rst_req);
      #(clk_half/2.0);
      rst_n = 1'b0;
      repeat( 5 ) begin
        @(posedge clk);
      end
      rst_n <= 1'b1;
    end
  end

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
`ifdef BEX_DUT_TOP
  BAYER_EX u_dut (
    .clk    (clk)
   ,.rst_n  (rst_n)
   ,.i_cfg  (misc.cfg)
   ,.i_vld  (in_if.vld)
   ,.o_busy (in_if.busy)
   ,.i_data (in_if.data)
   ,.o_vld  (out_if.vld)
   ,.i_busy (out_if.busy)
   ,.o_data (out_if.data)
  );
`else
  BAYER_EX_DATA_IF s_i_pix ();  // DUT の入力の data
  BAYER_EX_DATA_IF s_o_pix ();  // DUT の出力の data

  assign s_i_pix.data = in_if.data;
  assign out_if.data  = s_o_pix.data;

  BAYER_EX_CORE u_dut (
    .clk    (clk)
   ,.rst_n  (rst_n)
   ,.i_cfg  (misc.cfg)
   ,.i_vld  (in_if.vld)
   ,.o_busy (in_if.busy)
   ,.i_pix  (s_i_pix)
   ,.o_vld  (out_if.vld)
   ,.i_busy (out_if.busy)
   ,.o_pix  (s_o_pix)
  );
`endif

  // --------------------------------------------------------------------------
  // 波形
  // --------------------------------------------------------------------------
  initial begin
    if( $test$plusargs("WAVES") ) begin
`ifdef BEX_VCD
      $dumpfile("waves.vcd");
`elsif VERILATOR
      $dumpfile("waves.fst");
`else
      $dumpfile("waves.vcd");
`endif
      $dumpvars(0, tb_top);
    end
  end

  // --------------------------------------------------------------------------
  // UVM
  // --------------------------------------------------------------------------
  initial begin
    uvm_config_db#(virtual bex_vbd_if)::set(null, "*", "in_vif", in_if);
    uvm_config_db#(virtual bex_vbd_if)::set(null, "*", "out_vif", out_if);
    uvm_config_db#(virtual bex_misc_if)::set(null, "*", "misc_vif", misc);
    uvm_root::get().set_timeout(100ms, 1);
`ifdef UVM_NO_DPI
    // DPI なしでは部品名の正規表現の検査ができず、全部品に警告が出るので止める
    uvm_root::get().set_report_id_action("UVM/COMP/NAME", UVM_NO_ACTION);
`endif
    run_test();
  end

endmodule
