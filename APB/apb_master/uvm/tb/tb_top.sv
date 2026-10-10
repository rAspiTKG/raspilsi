//=============================================================================
// tb_top.sv
//-----------------------------------------------------------------------------
//  UVM テストベンチのトップ。
//    - クロック / リセット生成
//    - apb_if / usr_if と DUT (apb_master_mem) の接続
//    - virtual interface を config_db に登録して run_test()
//  テストは +UVM_TESTNAME=<name> で選択する (既定は apbm_smoke_test)。
//=============================================================================
`timescale 1ns / 1ps

module tb_top;

  import uvm_pkg::*;
  import apbm_params_pkg::*;
  import apbm_uvm_pkg::*;

  //---------------------------------------------------------------------------
  // クロック (100MHz) / リセット
  //---------------------------------------------------------------------------
  logic pclk;
  logic presetn;

  initial begin
    pclk = 1'b0;
    forever begin
      #5 pclk = ~pclk;
    end
  end

  initial begin
    presetn = 1'b0;
    repeat( 10 ) begin
      @(posedge pclk);
    end
    presetn = 1'b1;
  end

  //---------------------------------------------------------------------------
  // Interfaces
  //---------------------------------------------------------------------------
  apb_if u_apb_if (
    .pclk(pclk)
   ,.presetn(presetn)
  );

  usr_if u_usr_if (
    .pclk(pclk)
   ,.presetn(presetn)
  );

  //---------------------------------------------------------------------------
  // DUT
  //---------------------------------------------------------------------------
  apb_master_mem #(
    .ADDR_WIDTH(ADDR_W)
   ,.DATA_WIDTH(DATA_W)
   ,.NUM_SLAVES(NUM_SLAVES)
   ,.MEM_DEPTH(MEM_DEPTH)
   ,.TIMEOUT_CYCLES(TIMEOUT_CYCLES)
   ,.STOP_ON_ERROR(STOP_ON_ERROR)
  ) u_dut (
    .pclk(pclk)
   ,.presetn(presetn)
   ,.cmd_valid(u_usr_if.cmd_valid)
   ,.cmd_ready(u_usr_if.cmd_ready)
   ,.cmd_write(u_usr_if.cmd_write)
   ,.cmd_sel(u_usr_if.cmd_sel)
   ,.cmd_addr(u_usr_if.cmd_addr)
   ,.cmd_incr(u_usr_if.cmd_incr)
   ,.cmd_mem_addr(u_usr_if.cmd_mem_addr)
   ,.cmd_len(u_usr_if.cmd_len)
   ,.cmd_strb(u_usr_if.cmd_strb)
   ,.cmd_prot(u_usr_if.cmd_prot)
   ,.busy(u_usr_if.busy)
   ,.done(u_usr_if.done)
   ,.done_err(u_usr_if.done_err)
   ,.err_flags(u_usr_if.err_flags)
   ,.err_index(u_usr_if.err_index)
   ,.done_count(u_usr_if.done_count)
   ,.mem_valid(u_usr_if.mem_valid)
   ,.mem_ready(u_usr_if.mem_ready)
   ,.mem_write(u_usr_if.mem_write)
   ,.mem_addr(u_usr_if.mem_addr)
   ,.mem_wdata(u_usr_if.mem_wdata)
   ,.mem_rvalid(u_usr_if.mem_rvalid)
   ,.mem_rdata(u_usr_if.mem_rdata)
   ,.paddr(u_apb_if.paddr)
   ,.pprot(u_apb_if.pprot)
   ,.psel(u_apb_if.psel)
   ,.penable(u_apb_if.penable)
   ,.pwrite(u_apb_if.pwrite)
   ,.pwdata(u_apb_if.pwdata)
   ,.pstrb(u_apb_if.pstrb)
   ,.pready(u_apb_if.pready)
   ,.prdata(u_apb_if.prdata)
   ,.pslverr(u_apb_if.pslverr)
  );

  //---------------------------------------------------------------------------
  // 2 つの interface にまたがるチェック / DUT 内部の動作モデルのチェック
  //   - アイドル中はバスに何も出さない
  //   - 内部メモリの動作モデルが数えている範囲外アクセスを UVM のエラーにする
  //---------------------------------------------------------------------------
  int unsigned mem_oor_q;

  initial begin
    mem_oor_q = 0;
  end

  always @(posedge pclk) begin
    if( presetn&&!u_usr_if.busy&&((u_apb_if.psel!={NUM_SLAVES{1'b0}})||u_apb_if.penable) ) begin
      uvm_report_error("TOP_CHK", "bus activity (PSEL / PENABLE) while the DUT is idle");
    end
    if( u_dut.u_mem.sim_oor_cnt!=mem_oor_q ) begin
      uvm_report_error("MEM_CHK", "internal memory : access out of range");
    end
    mem_oor_q <= u_dut.u_mem.sim_oor_cnt;
  end

  //---------------------------------------------------------------------------
  // 波形 (make WAVES=1 で有効)
  //---------------------------------------------------------------------------
`ifdef WAVES
  initial begin
    $dumpfile("wave.fst");
    $dumpvars(0, tb_top);
  end
`endif

  //---------------------------------------------------------------------------
  // UVM 起動
  //---------------------------------------------------------------------------
  initial begin
    uvm_config_db#(apb_vif_t)::set(null, "uvm_test_top.*", "apb_vif", u_apb_if);
    uvm_config_db#(usr_vif_t)::set(null, "uvm_test_top.*", "usr_vif", u_usr_if);
    run_test("apbm_smoke_test");
  end

endmodule
