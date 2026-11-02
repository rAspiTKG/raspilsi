// ============================================================================
// tb_top : BAYER2RGB の検証環境のトップ
//   プラスアーグ
//     +CLK_PS=<ps>       clk の周期(既定 2500ps = 400MHz)
//     +CTRL_CLK_PS=<ps>  ctrl_clk の周期(既定 10000ps = 100MHz)
//     +WAVES             波形を出す(Verilator: waves.fst(TRACE=vcd でビルドしたときは waves.vcd)、
//                        その他: waves.vcd)
//                        GTKWave で開ける。Xcelium の SHM は sim/xrun_waves.tcl を使う
// ============================================================================
`timescale 1ns/1ps

module tb_top;
  import uvm_pkg::*;
  import b2r_tb_pkg::*;

  logic    clk;
  logic    rst_n;
  logic    ctrl_clk;
  logic    ctrl_rst_n;
  int      clk_ps;
  int      ctrl_ps;
  realtime clk_half;
  realtime ctrl_half;

  // --------------------------------------------------------------------------
  // クロックとリセット(非同期アサート・同期解除)
  // --------------------------------------------------------------------------
  initial begin
    if( !$value$plusargs("CLK_PS=%d",clk_ps) ) begin
      clk_ps = 2500;
    end
    if( !$value$plusargs("CTRL_CLK_PS=%d",ctrl_ps) ) begin
      ctrl_ps = 10000;
    end
    clk_half  = clk_ps/2000.0;
    ctrl_half = ctrl_ps/2000.0;
    clk       = 1'b0;
    ctrl_clk  = 1'b0;
  end

  initial begin
    #0.1;
    forever begin
      #(clk_half);
      clk = ~clk;
    end
  end

  initial begin
    #0.3;
    forever begin
      #(ctrl_half);
      ctrl_clk = ~ctrl_clk;
    end
  end

  // 最初のクロックの前に立ち下がりを作り、非同期リセットを確実にかける
  // (2値のシミュレータでは初期値が0だと時刻0の代入で立ち下がりが起きないため)
  initial begin
    rst_n = 1'b1;
    #0.05;
    rst_n = 1'b0;
    repeat( 20 ) begin
      @(posedge clk);
    end
    rst_n <= 1'b1;
  end

  initial begin
    ctrl_rst_n = 1'b1;
    #0.05;
    ctrl_rst_n = 1'b0;
    repeat( 10 ) begin
      @(posedge ctrl_clk);
    end
    ctrl_rst_n <= 1'b1;
  end

  // --------------------------------------------------------------------------
  // インタフェースとDUT
  // --------------------------------------------------------------------------
  b2r_axil_if axil (
    .clk   (ctrl_clk)
   ,.rst_n (ctrl_rst_n)
  );

  b2r_axi4_if axim (
    .clk   (clk)
   ,.rst_n (rst_n)
  );

  b2r_misc_if misc (
    .clk        (clk)
   ,.rst_n      (rst_n)
   ,.ctrl_clk   (ctrl_clk)
   ,.ctrl_rst_n (ctrl_rst_n)
  );

  BAYER2RGB u_dut (
    .clk                   (clk)
   ,.rst_n                 (rst_n)
   ,.ctrl_clk              (ctrl_clk)
   ,.ctrl_rst_n            (ctrl_rst_n)
   ,.irq                   (misc.irq)
   ,.BAYER2RGB_REG_AWADDR  (axil.awaddr)
   ,.BAYER2RGB_REG_AWPROT  (axil.awprot)
   ,.BAYER2RGB_REG_AWVALID (axil.awvalid)
   ,.BAYER2RGB_REG_AWREADY (axil.awready)
   ,.BAYER2RGB_REG_WDATA   (axil.wdata)
   ,.BAYER2RGB_REG_WSTRB   (axil.wstrb)
   ,.BAYER2RGB_REG_WVALID  (axil.wvalid)
   ,.BAYER2RGB_REG_WREADY  (axil.wready)
   ,.BAYER2RGB_REG_BRESP   (axil.bresp)
   ,.BAYER2RGB_REG_BVALID  (axil.bvalid)
   ,.BAYER2RGB_REG_BREADY  (axil.bready)
   ,.BAYER2RGB_REG_ARADDR  (axil.araddr)
   ,.BAYER2RGB_REG_ARPROT  (axil.arprot)
   ,.BAYER2RGB_REG_ARVALID (axil.arvalid)
   ,.BAYER2RGB_REG_ARREADY (axil.arready)
   ,.BAYER2RGB_REG_RDATA   (axil.rdata)
   ,.BAYER2RGB_REG_RRESP   (axil.rresp)
   ,.BAYER2RGB_REG_RVALID  (axil.rvalid)
   ,.BAYER2RGB_REG_RREADY  (axil.rready)
   ,.BAYER2RGB_MEM_AWID    (axim.awid)
   ,.BAYER2RGB_MEM_AWADDR  (axim.awaddr)
   ,.BAYER2RGB_MEM_AWLEN   (axim.awlen)
   ,.BAYER2RGB_MEM_AWSIZE  (axim.awsize)
   ,.BAYER2RGB_MEM_AWBURST (axim.awburst)
   ,.BAYER2RGB_MEM_AWLOCK  (axim.awlock)
   ,.BAYER2RGB_MEM_AWCACHE (axim.awcache)
   ,.BAYER2RGB_MEM_AWPROT  (axim.awprot)
   ,.BAYER2RGB_MEM_AWQOS   (axim.awqos)
   ,.BAYER2RGB_MEM_AWVALID (axim.awvalid)
   ,.BAYER2RGB_MEM_AWREADY (axim.awready)
   ,.BAYER2RGB_MEM_WDATA   (axim.wdata)
   ,.BAYER2RGB_MEM_WSTRB   (axim.wstrb)
   ,.BAYER2RGB_MEM_WLAST   (axim.wlast)
   ,.BAYER2RGB_MEM_WVALID  (axim.wvalid)
   ,.BAYER2RGB_MEM_WREADY  (axim.wready)
   ,.BAYER2RGB_MEM_BID     (axim.bid)
   ,.BAYER2RGB_MEM_BRESP   (axim.bresp)
   ,.BAYER2RGB_MEM_BVALID  (axim.bvalid)
   ,.BAYER2RGB_MEM_BREADY  (axim.bready)
   ,.BAYER2RGB_MEM_ARID    (axim.arid)
   ,.BAYER2RGB_MEM_ARADDR  (axim.araddr)
   ,.BAYER2RGB_MEM_ARLEN   (axim.arlen)
   ,.BAYER2RGB_MEM_ARSIZE  (axim.arsize)
   ,.BAYER2RGB_MEM_ARBURST (axim.arburst)
   ,.BAYER2RGB_MEM_ARLOCK  (axim.arlock)
   ,.BAYER2RGB_MEM_ARCACHE (axim.arcache)
   ,.BAYER2RGB_MEM_ARPROT  (axim.arprot)
   ,.BAYER2RGB_MEM_ARQOS   (axim.arqos)
   ,.BAYER2RGB_MEM_ARVALID (axim.arvalid)
   ,.BAYER2RGB_MEM_ARREADY (axim.arready)
   ,.BAYER2RGB_MEM_RID     (axim.rid)
   ,.BAYER2RGB_MEM_RDATA   (axim.rdata)
   ,.BAYER2RGB_MEM_RRESP   (axim.rresp)
   ,.BAYER2RGB_MEM_RLAST   (axim.rlast)
   ,.BAYER2RGB_MEM_RVALID  (axim.rvalid)
   ,.BAYER2RGB_MEM_RREADY  (axim.rready)
  );

`ifdef B2R_DEBUG
  // デバッグ用: フレーム開始と各リンクの最初のビートを表示する
  int dbg_pix;
  int dbg_rgb;
  int dbg_w;
  always @(posedge clk) begin
    if( u_dut.s_ctl_v.start ) begin
      $display("%t DBG start W=%0d H=%0d src=%h dst=%h", $time, u_dut.s_ctl_v.cfg.width, u_dut.s_ctl_v.cfg.height, u_dut.s_ctl_v.cfg.src_addr, u_dut.s_ctl_v.cfg.dst_addr);
      dbg_pix = 0;
      dbg_rgb = 0;
      dbg_w   = 0;
    end
    if( u_dut.s_ctl_v.sw_rst ) begin
      $display("%t DBG sw_rst avail=%0d ost=%0d lq=%0d wbuf=%0d cnt=%0d", $time, u_dut.u_wr_dma.r_avail, u_dut.u_wr_dma.r_ost,
              u_dut.u_wr_dma.s_lq_rvld, u_dut.u_wr_dma.u_wbuf.o_cnt, u_dut.u_wr_dma.r_cnt);
    end
    if( u_dut.u_wr_dma.r_abort ) begin
      $display("%t DBG abort clr=%0d ost=%0d lq=%0d wbuf=%0d push=%0d wtake=%0d", $time, u_dut.u_wr_dma.s_wbuf_clr, u_dut.u_wr_dma.r_ost,
              u_dut.u_wr_dma.s_lq_rvld, u_dut.u_wr_dma.u_wbuf.o_cnt, u_dut.u_wr_dma.s_push, u_dut.u_wr_dma.s_w_take);
    end
    if( u_dut.s_pix.vld&&!u_dut.s_pix.busy&&(dbg_pix<3) ) begin
      $display("%t DBG pix[%0d] %h", $time, dbg_pix, u_dut.s_pix.data);
      dbg_pix++;
    end
    if( u_dut.s_rgb.vld&&!u_dut.s_rgb.busy&&(dbg_rgb<3) ) begin
      $display("%t DBG rgb[%0d] %h", $time, dbg_rgb, u_dut.s_rgb.data);
      dbg_rgb++;
    end
    if( u_dut.s_w.vld&&!u_dut.s_w.busy&&(dbg_w<3) ) begin
      $display("%t DBG w[%0d] %h", $time, dbg_w, u_dut.s_w.data);
      dbg_w++;
    end
  end
`endif

  // --------------------------------------------------------------------------
  // 波形
  // --------------------------------------------------------------------------
  initial begin
    if( $test$plusargs("WAVES") ) begin
`ifdef B2R_VCD
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
    uvm_config_db#(virtual b2r_axil_if)::set(null, "*", "vif", axil);
    uvm_config_db#(virtual b2r_axi4_if)::set(null, "*", "vif", axim);
    uvm_config_db#(virtual b2r_misc_if)::set(null, "*", "mvif", misc);
    uvm_root::get().set_timeout(1s, 1);
`ifdef UVM_NO_DPI
    // DPIなしでは部品名の正規表現検査ができず、全部品に警告が出るので止める
    uvm_root::get().set_report_id_action("UVM/COMP/NAME", UVM_NO_ACTION);
`endif
    run_test();
  end

endmodule
