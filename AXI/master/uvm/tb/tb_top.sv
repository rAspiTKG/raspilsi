//=============================================================================
// tb_top.sv
//-----------------------------------------------------------------------------
//  UVM テストベンチのトップ。
//    - クロック / リセット生成
//    - axi_if / cmd_if と DUT (axi4_full_master_copy) の接続
//    - virtual interface を config_db に登録して run_test()
//  テストは +UVM_TESTNAME=<name> で選択する (既定は copy_smoke_test)。
//=============================================================================
`timescale 1ns / 1ps

module tb_top;

  import uvm_pkg::*;
  import axi_params_pkg::*;
  import copy_uvm_pkg::*;

  //---------------------------------------------------------------------------
  // クロック (100MHz) / リセット
  //---------------------------------------------------------------------------
  logic aclk;
  logic aresetn;

  initial begin
    aclk = 1'b0;
    forever begin
      #5 aclk = ~aclk;
    end
  end

  initial begin
    aresetn = 1'b0;
    repeat( 10 ) begin
      @(posedge aclk);
    end
    aresetn = 1'b1;
  end

  //---------------------------------------------------------------------------
  // Interfaces
  //---------------------------------------------------------------------------
  axi_if u_axi_if (
    .aclk(aclk)
   ,.aresetn(aresetn)
  );

  cmd_if u_cmd_if (
    .aclk(aclk)
   ,.aresetn(aresetn)
  );

  //---------------------------------------------------------------------------
  // DUT
  //---------------------------------------------------------------------------
  axi4_full_master_copy #(
    .ADDR_WIDTH(ADDR_W)
   ,.DATA_WIDTH(DATA_W)
   ,.ID_WIDTH(ID_W)
   ,.RD_ID(RD_ID)
   ,.WR_ID(WR_ID)
   ,.LEN_WIDTH(LEN_W)
   ,.MAX_BURST(MAX_BURST)
   ,.BUF_DEPTH(BUF_DEPTH)
  ) u_dut (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.cmd_valid(u_cmd_if.cmd_valid)
   ,.cmd_ready(u_cmd_if.cmd_ready)
   ,.cmd_src(u_cmd_if.cmd_src)
   ,.cmd_dst(u_cmd_if.cmd_dst)
   ,.cmd_len(u_cmd_if.cmd_len)
   ,.busy(u_cmd_if.busy)
   ,.done(u_cmd_if.done)
   ,.done_err(u_cmd_if.done_err)
   ,.m_axi_awid(u_axi_if.awid)
   ,.m_axi_awaddr(u_axi_if.awaddr)
   ,.m_axi_awlen(u_axi_if.awlen)
   ,.m_axi_awsize(u_axi_if.awsize)
   ,.m_axi_awburst(u_axi_if.awburst)
   ,.m_axi_awlock(u_axi_if.awlock)
   ,.m_axi_awcache(u_axi_if.awcache)
   ,.m_axi_awprot(u_axi_if.awprot)
   ,.m_axi_awqos(u_axi_if.awqos)
   ,.m_axi_awregion(u_axi_if.awregion)
   ,.m_axi_awvalid(u_axi_if.awvalid)
   ,.m_axi_awready(u_axi_if.awready)
   ,.m_axi_wdata(u_axi_if.wdata)
   ,.m_axi_wstrb(u_axi_if.wstrb)
   ,.m_axi_wlast(u_axi_if.wlast)
   ,.m_axi_wvalid(u_axi_if.wvalid)
   ,.m_axi_wready(u_axi_if.wready)
   ,.m_axi_bid(u_axi_if.bid)
   ,.m_axi_bresp(u_axi_if.bresp)
   ,.m_axi_bvalid(u_axi_if.bvalid)
   ,.m_axi_bready(u_axi_if.bready)
   ,.m_axi_arid(u_axi_if.arid)
   ,.m_axi_araddr(u_axi_if.araddr)
   ,.m_axi_arlen(u_axi_if.arlen)
   ,.m_axi_arsize(u_axi_if.arsize)
   ,.m_axi_arburst(u_axi_if.arburst)
   ,.m_axi_arlock(u_axi_if.arlock)
   ,.m_axi_arcache(u_axi_if.arcache)
   ,.m_axi_arprot(u_axi_if.arprot)
   ,.m_axi_arqos(u_axi_if.arqos)
   ,.m_axi_arregion(u_axi_if.arregion)
   ,.m_axi_arvalid(u_axi_if.arvalid)
   ,.m_axi_arready(u_axi_if.arready)
   ,.m_axi_rid(u_axi_if.rid)
   ,.m_axi_rdata(u_axi_if.rdata)
   ,.m_axi_rresp(u_axi_if.rresp)
   ,.m_axi_rlast(u_axi_if.rlast)
   ,.m_axi_rvalid(u_axi_if.rvalid)
   ,.m_axi_rready(u_axi_if.rready)
  );

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
    uvm_config_db#(axi_vif_t)::set(null, "uvm_test_top.*", "axi_vif", u_axi_if);
    uvm_config_db#(cmd_vif_t)::set(null, "uvm_test_top.*", "cmd_vif", u_cmd_if);
    run_test("copy_smoke_test");
  end

endmodule
