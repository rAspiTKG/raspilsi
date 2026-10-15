//=============================================================================
// tb_axil_uvm.sv
//-----------------------------------------------------------------------------
//  axil_if を UVM で使う例 (uvm_config_db で virtual interface を渡す)。
//    - TB のトップで axil_if を TB_ROLE=1 で置き、axil_smp_regs (サブオーディネート) をつなぐ
//    - virtual interface の型は、interface の parameter (TB_ROLE / CHECK も) を全てそろえる。
//      typedef にしておき、set と get で同じ型を使う
//    - テストが mgr_cb で書き込み 1 回と読み出し 2 回 (OKAY / SLVERR) を行い、結果を確かめる
//  必要なもの : UVM 1800.2-2020.3.2 (sim/Makefile の make uvm UVM_HOME=...)
//=============================================================================
`timescale 1ns / 1ps
`include "uvm_macros.svh"

package axil_uvm_pkg;
  import uvm_pkg::*;

  // interface の parameter (TB_ROLE / CHECK も) を全部そろえた virtual interface の型
  typedef virtual axil_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .TB_ROLE(1)).mgr_tb axil_mgr_vif;

  class axil_wr_rd_test extends uvm_test;
    `uvm_component_utils(axil_wr_rd_test)

    axil_mgr_vif vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if( !uvm_config_db#(axil_mgr_vif)::get(this,"","vif",vif) ) begin
        `uvm_fatal("NOVIF", "axil_mgr_vif is not set")
      end
    endfunction

    task write(input logic [31:0] addr, input logic [31:0] data, output logic [1:0] resp);
      vif.mgr_cb.awaddr  <= addr;
      vif.mgr_cb.awprot  <= 3'b000;
      vif.mgr_cb.awvalid <= 1'b1;
      vif.mgr_cb.wdata   <= data;
      vif.mgr_cb.wstrb   <= 4'hF;
      vif.mgr_cb.wvalid  <= 1'b1;
      vif.mgr_cb.bready  <= 1'b1;
      fork
        begin
          do begin
            @(vif.mgr_cb);
          end while( !vif.mgr_cb.awready );
          vif.mgr_cb.awvalid <= 1'b0;
        end
        begin
          do begin
            @(vif.mgr_cb);
          end while( !vif.mgr_cb.wready );
          vif.mgr_cb.wvalid <= 1'b0;
        end
      join
      do begin
        @(vif.mgr_cb);
      end while( !vif.mgr_cb.bvalid );
      resp = vif.mgr_cb.bresp;
    endtask

    task read(input logic [31:0] addr, output logic [31:0] data, output logic [1:0] resp);
      vif.mgr_cb.araddr  <= addr;
      vif.mgr_cb.arprot  <= 3'b000;
      vif.mgr_cb.arvalid <= 1'b1;
      vif.mgr_cb.rready  <= 1'b1;
      do begin
        @(vif.mgr_cb);
      end while( !vif.mgr_cb.arready );
      vif.mgr_cb.arvalid <= 1'b0;
      do begin
        @(vif.mgr_cb);
      end while( !vif.mgr_cb.rvalid );
      data = vif.mgr_cb.rdata;
      resp = vif.mgr_cb.rresp;
    endtask

    task run_phase(uvm_phase phase);
      logic [31:0] d;
      logic [1:0]  r;
      phase.raise_objection(this);
      wait( vif.aresetn===1'b1 );
      @(vif.mgr_cb);
      write(32'h4, 32'hCAFE_0001, r);
      if( r!==2'b00 ) begin
        `uvm_error("WR", $sformatf("addr 0x4 : bresp %0d", r))
      end
      read(32'h4, d, r);
      if( (d!==32'hCAFE_0001)||(r!==2'b00) ) begin
        `uvm_error("RD", $sformatf("addr 0x4 : data 0x%08h rresp %0d", d, r))
      end else begin
        `uvm_info("RD", $sformatf("addr 0x4 : data 0x%08h OKAY", d), UVM_LOW)
      end
      read(32'h40, d, r);
      if( r!==2'b10 ) begin
        `uvm_error("RD", $sformatf("addr 0x40 : rresp %0d (expected SLVERR)", r))
      end else begin
        `uvm_info("RD", "addr 0x40 : SLVERR", UVM_LOW)
      end
      repeat( 3 ) begin
        @(vif.mgr_cb);
      end
      phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
      uvm_report_server rs;
      rs = uvm_report_server::get_server();
      if( (rs.get_severity_count(UVM_ERROR)==0)&&(rs.get_severity_count(UVM_FATAL)==0) ) begin
        `uvm_info("TEST", "TEST PASSED", UVM_NONE)
      end else begin
        `uvm_info("TEST", "TEST FAILED", UVM_NONE)
      end
    endfunction
  endclass

endpackage

module tb_axil_uvm;
  import uvm_pkg::*;
  import axil_uvm_pkg::*;

  logic aclk;
  logic aresetn;

  initial begin
    aclk = 1'b0;
    forever begin
      #5;
      aclk = ~aclk;
    end
  end

  initial begin
    aresetn = 1'b0;
    repeat( 3 ) begin
      @(posedge aclk);
    end
    #1;
    aresetn = 1'b1;
  end

  axil_if #(
    .ADDR_WIDTH ( 32 )
   ,.DATA_WIDTH ( 32 )
   ,.TB_ROLE    ( 1  )
  ) u_axi (
    .aclk    ( aclk    )
   ,.aresetn ( aresetn )
  );

  axil_smp_regs #(
    .ADDR_WIDTH ( 32 )
   ,.DATA_WIDTH ( 32 )
   ,.NREG       ( 4  )
   ,.READY_DLY  ( 1  )
  ) u_dut (
    .aclk    ( aclk    )
   ,.aresetn ( aresetn )
   ,.s_axi   ( u_axi   )
  );

  initial begin
    uvm_config_db#(axil_mgr_vif)::set(null, "uvm_test_top", "vif", u_axi);
    run_test("axil_wr_rd_test");
  end

endmodule
