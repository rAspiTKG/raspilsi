//=============================================================================
// tb_top.sv
//-----------------------------------------------------------------------------
//  UVM テストベンチのトップ。
//    - クロック / リセット生成
//    - axi_rd_if / axi_wr_if / cmd_if と DUT (axi4_master_linebuf) の接続
//    - virtual interface を config_db に登録して run_test()
//  テストは +UVM_TESTNAME=<name> で選択する (既定は lb_smoke_test)。
//=============================================================================
`timescale 1ns / 1ps

module tb_top;

  import uvm_pkg::*;
  import lb_params_pkg::*;
  import lb_uvm_pkg::*;

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
  axi_rd_if u_rd_if (
    .aclk(aclk)
   ,.aresetn(aresetn)
  );

  axi_wr_if u_wr_if (
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
  axi4_master_linebuf #(
    .IN_ADDR_WIDTH(IN_ADDR_W)
   ,.IN_DATA_WIDTH(IN_DATA_W)
   ,.IN_ID_WIDTH(IN_ID_W)
   ,.IN_AXI_ID(IN_AXI_ID)
   ,.IN_MAX_BURST(IN_MAX_BURST)
   ,.IN_FIFO_DEPTH(IN_FIFO_DEPTH)
   ,.IN_ARCACHE(ARCACHE_V)
   ,.IN_ARPROT(ARPROT_V)
   ,.IN_ARQOS(ARQOS_V)
   ,.IN_ARREGION(ARREGION_V)
   ,.OUT_ADDR_WIDTH(OUT_ADDR_W)
   ,.OUT_DATA_WIDTH(OUT_DATA_W)
   ,.OUT_ID_WIDTH(OUT_ID_W)
   ,.OUT_AXI_ID(OUT_AXI_ID)
   ,.OUT_MAX_BURST(OUT_MAX_BURST)
   ,.OUT_FIFO_DEPTH(OUT_FIFO_DEPTH)
   ,.OUT_AWCACHE(AWCACHE_V)
   ,.OUT_AWPROT(AWPROT_V)
   ,.OUT_AWQOS(AWQOS_V)
   ,.OUT_AWREGION(AWREGION_V)
   ,.PIXEL_BITS(PIXEL_BITS)
   ,.PIX_MEM_BITS(PIX_MEM_BITS)
   ,.PIX_ALIGN_MSB(PIX_ALIGN_MSB)
   ,.PIX_PER_WORD(PIX_PER_WORD)
   ,.MAX_LINE_PIXELS(MAX_LINE_PIXELS)
   ,.NUM_LINES(NUM_LINES)
   ,.HEIGHT_WIDTH(HEIGHT_W)
   ,.STRIDE_WIDTH(STRIDE_W)
  ) u_dut (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.cmd_valid(u_cmd_if.cmd_valid)
   ,.cmd_ready(u_cmd_if.cmd_ready)
   ,.cmd_src_addr(u_cmd_if.cmd_src_addr)
   ,.cmd_dst_addr(u_cmd_if.cmd_dst_addr)
   ,.cmd_src_stride(u_cmd_if.cmd_src_stride)
   ,.cmd_dst_stride(u_cmd_if.cmd_dst_stride)
   ,.cmd_width(u_cmd_if.cmd_width)
   ,.cmd_height(u_cmd_if.cmd_height)
   ,.busy(u_cmd_if.busy)
   ,.done(u_cmd_if.done)
   ,.done_err(u_cmd_if.done_err)
   ,.err_flags(u_cmd_if.err_flags)
   ,.line_in_done(u_cmd_if.line_in_done)
   ,.line_out_done(u_cmd_if.line_out_done)
   ,.sp_level(u_cmd_if.sp_level)
   ,.m_axi_in_arid(u_rd_if.arid)
   ,.m_axi_in_araddr(u_rd_if.araddr)
   ,.m_axi_in_arlen(u_rd_if.arlen)
   ,.m_axi_in_arsize(u_rd_if.arsize)
   ,.m_axi_in_arburst(u_rd_if.arburst)
   ,.m_axi_in_arlock(u_rd_if.arlock)
   ,.m_axi_in_arcache(u_rd_if.arcache)
   ,.m_axi_in_arprot(u_rd_if.arprot)
   ,.m_axi_in_arqos(u_rd_if.arqos)
   ,.m_axi_in_arregion(u_rd_if.arregion)
   ,.m_axi_in_arvalid(u_rd_if.arvalid)
   ,.m_axi_in_arready(u_rd_if.arready)
   ,.m_axi_in_rid(u_rd_if.rid)
   ,.m_axi_in_rdata(u_rd_if.rdata)
   ,.m_axi_in_rresp(u_rd_if.rresp)
   ,.m_axi_in_rlast(u_rd_if.rlast)
   ,.m_axi_in_rvalid(u_rd_if.rvalid)
   ,.m_axi_in_rready(u_rd_if.rready)
   ,.m_axi_out_awid(u_wr_if.awid)
   ,.m_axi_out_awaddr(u_wr_if.awaddr)
   ,.m_axi_out_awlen(u_wr_if.awlen)
   ,.m_axi_out_awsize(u_wr_if.awsize)
   ,.m_axi_out_awburst(u_wr_if.awburst)
   ,.m_axi_out_awlock(u_wr_if.awlock)
   ,.m_axi_out_awcache(u_wr_if.awcache)
   ,.m_axi_out_awprot(u_wr_if.awprot)
   ,.m_axi_out_awqos(u_wr_if.awqos)
   ,.m_axi_out_awregion(u_wr_if.awregion)
   ,.m_axi_out_awvalid(u_wr_if.awvalid)
   ,.m_axi_out_awready(u_wr_if.awready)
   ,.m_axi_out_wdata(u_wr_if.wdata)
   ,.m_axi_out_wstrb(u_wr_if.wstrb)
   ,.m_axi_out_wlast(u_wr_if.wlast)
   ,.m_axi_out_wvalid(u_wr_if.wvalid)
   ,.m_axi_out_wready(u_wr_if.wready)
   ,.m_axi_out_bid(u_wr_if.bid)
   ,.m_axi_out_bresp(u_wr_if.bresp)
   ,.m_axi_out_bvalid(u_wr_if.bvalid)
   ,.m_axi_out_bready(u_wr_if.bready)
  );

  //---------------------------------------------------------------------------
  // scratchpad の動作モデルが数えている異常を UVM のエラーにする
  //   sim_conflict_cnt  : 同じラインへの同時アクセス / 範囲外への書き込み
  //   sim_uninit_rd_cnt : そのラインにまだ書いていないワードの読み出し
  //---------------------------------------------------------------------------
  int unsigned sp_conflict_q;
  int unsigned sp_uninit_q;

  initial begin
    sp_conflict_q = 0;
    sp_uninit_q   = 0;
  end

  always @(posedge aclk) begin
    if( u_dut.u_scratchpad.sim_conflict_cnt!=sp_conflict_q ) begin
      uvm_report_error("SP_CHK", "scratchpad : write/read hit the same line, or write out of range");
    end
    if( u_dut.u_scratchpad.sim_uninit_rd_cnt!=sp_uninit_q ) begin
      uvm_report_error("SP_CHK", "scratchpad : read of a word that is not written");
    end
    sp_conflict_q <= u_dut.u_scratchpad.sim_conflict_cnt;
    sp_uninit_q   <= u_dut.u_scratchpad.sim_uninit_rd_cnt;
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
    uvm_config_db#(axi_rd_vif_t)::set(null, "uvm_test_top.*", "axi_rd_vif", u_rd_if);
    uvm_config_db#(axi_wr_vif_t)::set(null, "uvm_test_top.*", "axi_wr_vif", u_wr_if);
    uvm_config_db#(cmd_vif_t)::set(null, "uvm_test_top.*", "cmd_vif", u_cmd_if);
    run_test("lb_smoke_test");
  end

endmodule
