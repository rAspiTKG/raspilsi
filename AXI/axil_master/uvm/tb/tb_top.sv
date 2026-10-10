//=============================================================================
// tb_top.sv
//-----------------------------------------------------------------------------
//  UVM テストベンチのトップ。
//    - クロック / リセット生成
//    - usr_if / axi_if と DUT (axil_master_mem) + axil_to_axi4 の接続
//        DUT --(AXI4-Lite)--> axil_to_axi4 --(AXI4 + AWAKEUP)--> axi_if (テストベンチのスレーブ)
//    - virtual interface を config_db に登録して run_test()
//  テストは +UVM_TESTNAME=<name> で選択する (既定は axlm_smoke_test)。
//=============================================================================
`timescale 1ns / 1ps

module tb_top;

  import uvm_pkg::*;
  import axlm_params_pkg::*;
  import axlm_uvm_pkg::*;

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
  usr_if u_usr_if (
    .aclk(aclk)
   ,.aresetn(aresetn)
  );

  axi_if u_axi_if (
    .aclk(aclk)
   ,.aresetn(aresetn)
  );

  //---------------------------------------------------------------------------
  // DUT (AXI4-Lite マスタ) と axil_to_axi4 の間の AXI4-Lite
  //---------------------------------------------------------------------------
  logic [ADDR_W-1:0] l_awaddr;
  logic [2:0]        l_awprot;
  logic              l_awvalid;
  logic              l_awready;
  logic [DATA_W-1:0] l_wdata;
  logic [STRB_W-1:0] l_wstrb;
  logic              l_wvalid;
  logic              l_wready;
  logic [1:0]        l_bresp;
  logic              l_bvalid;
  logic              l_bready;
  logic [ADDR_W-1:0] l_araddr;
  logic [2:0]        l_arprot;
  logic              l_arvalid;
  logic              l_arready;
  logic [DATA_W-1:0] l_rdata;
  logic [1:0]        l_rresp;
  logic              l_rvalid;
  logic              l_rready;
  logic              axi_wakeup;

  axil_master_mem #(
    .ADDR_WIDTH(ADDR_W)
   ,.DATA_WIDTH(DATA_W)
   ,.MEM_DEPTH(MEM_DEPTH)
   ,.MAX_WR_OUTSTANDING(MAX_WR)
   ,.MAX_RD_OUTSTANDING(MAX_RD)
   ,.STOP_ON_ERROR(STOP_ON_ERROR)
  ) u_dut (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.wcmd_valid(u_usr_if.wcmd_valid)
   ,.wcmd_ready(u_usr_if.wcmd_ready)
   ,.wcmd_addr(u_usr_if.wcmd_addr)
   ,.wcmd_incr(u_usr_if.wcmd_incr)
   ,.wcmd_mem_addr(u_usr_if.wcmd_mem_addr)
   ,.wcmd_len(u_usr_if.wcmd_len)
   ,.wcmd_strb(u_usr_if.wcmd_strb)
   ,.wcmd_prot(u_usr_if.wcmd_prot)
   ,.wr_busy(u_usr_if.wr_busy)
   ,.wr_done(u_usr_if.wr_done)
   ,.wr_done_err(u_usr_if.wr_done_err)
   ,.wr_err_flags(u_usr_if.wr_err_flags)
   ,.wr_err_index(u_usr_if.wr_err_index)
   ,.wr_done_count(u_usr_if.wr_done_count)
   ,.rcmd_valid(u_usr_if.rcmd_valid)
   ,.rcmd_ready(u_usr_if.rcmd_ready)
   ,.rcmd_addr(u_usr_if.rcmd_addr)
   ,.rcmd_incr(u_usr_if.rcmd_incr)
   ,.rcmd_mem_addr(u_usr_if.rcmd_mem_addr)
   ,.rcmd_len(u_usr_if.rcmd_len)
   ,.rcmd_prot(u_usr_if.rcmd_prot)
   ,.rd_busy(u_usr_if.rd_busy)
   ,.rd_done(u_usr_if.rd_done)
   ,.rd_done_err(u_usr_if.rd_done_err)
   ,.rd_err_flags(u_usr_if.rd_err_flags)
   ,.rd_err_index(u_usr_if.rd_err_index)
   ,.rd_done_count(u_usr_if.rd_done_count)
   ,.mem_w_valid(u_usr_if.mem_w_valid)
   ,.mem_w_ready(u_usr_if.mem_w_ready)
   ,.mem_w_addr(u_usr_if.mem_w_addr)
   ,.mem_w_data(u_usr_if.mem_w_data)
   ,.mem_r_valid(u_usr_if.mem_r_valid)
   ,.mem_r_ready(u_usr_if.mem_r_ready)
   ,.mem_r_addr(u_usr_if.mem_r_addr)
   ,.mem_r_rvalid(u_usr_if.mem_r_rvalid)
   ,.mem_r_rdata(u_usr_if.mem_r_rdata)
   ,.axi_wakeup(axi_wakeup)
   ,.m_axi_awaddr(l_awaddr)
   ,.m_axi_awprot(l_awprot)
   ,.m_axi_awvalid(l_awvalid)
   ,.m_axi_awready(l_awready)
   ,.m_axi_wdata(l_wdata)
   ,.m_axi_wstrb(l_wstrb)
   ,.m_axi_wvalid(l_wvalid)
   ,.m_axi_wready(l_wready)
   ,.m_axi_bresp(l_bresp)
   ,.m_axi_bvalid(l_bvalid)
   ,.m_axi_bready(l_bready)
   ,.m_axi_araddr(l_araddr)
   ,.m_axi_arprot(l_arprot)
   ,.m_axi_arvalid(l_arvalid)
   ,.m_axi_arready(l_arready)
   ,.m_axi_rdata(l_rdata)
   ,.m_axi_rresp(l_rresp)
   ,.m_axi_rvalid(l_rvalid)
   ,.m_axi_rready(l_rready)
  );

  axil_to_axi4 #(
    .ADDR_WIDTH(ADDR_W)
   ,.DATA_WIDTH(DATA_W)
   ,.ID_WIDTH(ID_W)
   ,.QOS(QOS)
  ) u_conv (
    .s_axi_awaddr(l_awaddr)
   ,.s_axi_awprot(l_awprot)
   ,.s_axi_awvalid(l_awvalid)
   ,.s_axi_awready(l_awready)
   ,.s_axi_wdata(l_wdata)
   ,.s_axi_wstrb(l_wstrb)
   ,.s_axi_wvalid(l_wvalid)
   ,.s_axi_wready(l_wready)
   ,.s_axi_bresp(l_bresp)
   ,.s_axi_bvalid(l_bvalid)
   ,.s_axi_bready(l_bready)
   ,.s_axi_araddr(l_araddr)
   ,.s_axi_arprot(l_arprot)
   ,.s_axi_arvalid(l_arvalid)
   ,.s_axi_arready(l_arready)
   ,.s_axi_rdata(l_rdata)
   ,.s_axi_rresp(l_rresp)
   ,.s_axi_rvalid(l_rvalid)
   ,.s_axi_rready(l_rready)
   ,.s_axi_wakeup(axi_wakeup)
   ,.m_axi_awid(u_axi_if.awid)
   ,.m_axi_awaddr(u_axi_if.awaddr)
   ,.m_axi_awlen(u_axi_if.awlen)
   ,.m_axi_awsize(u_axi_if.awsize)
   ,.m_axi_awburst(u_axi_if.awburst)
   ,.m_axi_awlock(u_axi_if.awlock)
   ,.m_axi_awcache(u_axi_if.awcache)
   ,.m_axi_awprot(u_axi_if.awprot)
   ,.m_axi_awqos(u_axi_if.awqos)
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
   ,.m_axi_arvalid(u_axi_if.arvalid)
   ,.m_axi_arready(u_axi_if.arready)
   ,.m_axi_rid(u_axi_if.rid)
   ,.m_axi_rdata(u_axi_if.rdata)
   ,.m_axi_rresp(u_axi_if.rresp)
   ,.m_axi_rlast(u_axi_if.rlast)
   ,.m_axi_rvalid(u_axi_if.rvalid)
   ,.m_axi_rready(u_axi_if.rready)
   ,.m_axi_awakeup(u_axi_if.awakeup)
  );

  //---------------------------------------------------------------------------
  // 2 つの interface にまたがるチェック / DUT 内部の動作モデルのチェック
  //   - コマンドがアイドルの方向は、バスに何も出さない
  //   - 両方アイドルなら AWAKEUP=0
  //   - 内部メモリの動作モデルが数えている範囲外アクセス / 同じアドレスの同時読み書きを UVM のエラーにする
  //---------------------------------------------------------------------------
  int unsigned mem_oor_q;
  int unsigned mem_same_q;

  initial begin
    mem_oor_q  = 0;
    mem_same_q = 0;
  end

  always @(posedge aclk) begin
    if( aresetn&&!u_usr_if.wr_busy&&(u_axi_if.awvalid||u_axi_if.wvalid) ) begin
      uvm_report_error("TOP_CHK", "AWVALID / WVALID while no write command is running");
    end
    if( aresetn&&!u_usr_if.rd_busy&&u_axi_if.arvalid ) begin
      uvm_report_error("TOP_CHK", "ARVALID while no read command is running");
    end
    if( aresetn&&!u_usr_if.wr_busy&&!u_usr_if.rd_busy&&u_axi_if.awakeup ) begin
      uvm_report_error("TOP_CHK", "AWAKEUP=1 while both commands are idle");
    end
    if( u_dut.u_mem.sim_oor_cnt!=mem_oor_q ) begin
      uvm_report_error("MEM_CHK", "internal memory : access out of range");
    end
    if( u_dut.u_mem.sim_same_cnt!=mem_same_q ) begin
      uvm_report_error("MEM_CHK", "internal memory : read and write of the same address in the same cycle");
    end
    mem_oor_q  <= u_dut.u_mem.sim_oor_cnt;
    mem_same_q <= u_dut.u_mem.sim_same_cnt;
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
    uvm_config_db#(axi_vif_t)::set(null, "uvm_test_top.*", "axi_vif", u_axi_if);
    uvm_config_db#(usr_vif_t)::set(null, "uvm_test_top.*", "usr_vif", u_usr_if);
    run_test("axlm_smoke_test");
  end

endmodule
