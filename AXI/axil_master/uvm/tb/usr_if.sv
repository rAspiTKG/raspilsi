//=============================================================================
// usr_if.sv
//-----------------------------------------------------------------------------
//  axil_master_mem のユーザ側 interface。
//    wcmd_* / wr_* : 書き込みコマンド (valid/ready) とステータス
//    rcmd_* / rd_* : 読み出しコマンド (valid/ready) とステータス
//    mem_w_* / mem_r_* : 内部メモリのローカルポート (読み出しは次サイクルに mem_r_rvalid)
//
//  SVA:
//    DUT          : busy と ready の関係 (コマンド / ローカルポート)、done は 1 サイクル、
//                   done_err == |err_flags、ステータスは次のコマンド受付まで保持、
//                   mem_r_rvalid は読み出しを受け付けた次のサイクルだけ 1
//    テストベンチ : valid は握手まで下げず、内容も変えない
//=============================================================================
`timescale 1ns / 1ps

interface usr_if (
  input logic aclk
 ,input logic aresetn
);

  import axlm_params_pkg::*;

  //---------------------------------------------------------------------------
  // 書き込みコマンド / ステータス
  //---------------------------------------------------------------------------
  logic              wcmd_valid;
  logic              wcmd_ready;
  logic [ADDR_W-1:0] wcmd_addr;
  logic              wcmd_incr;
  logic [MEM_AW-1:0] wcmd_mem_addr;
  logic [LEN_W-1:0]  wcmd_len;
  logic [STRB_W-1:0] wcmd_strb;
  logic [2:0]        wcmd_prot;
  logic              wr_busy;
  logic              wr_done;
  logic              wr_done_err;
  logic [3:0]        wr_err_flags;
  logic [LEN_W-1:0]  wr_err_index;
  logic [LEN_W-1:0]  wr_done_count;
  //---------------------------------------------------------------------------
  // 読み出しコマンド / ステータス
  //---------------------------------------------------------------------------
  logic              rcmd_valid;
  logic              rcmd_ready;
  logic [ADDR_W-1:0] rcmd_addr;
  logic              rcmd_incr;
  logic [MEM_AW-1:0] rcmd_mem_addr;
  logic [LEN_W-1:0]  rcmd_len;
  logic [2:0]        rcmd_prot;
  logic              rd_busy;
  logic              rd_done;
  logic              rd_done_err;
  logic [3:0]        rd_err_flags;
  logic [LEN_W-1:0]  rd_err_index;
  logic [LEN_W-1:0]  rd_done_count;
  //---------------------------------------------------------------------------
  // 内部メモリのローカルポート
  //---------------------------------------------------------------------------
  logic              mem_w_valid;
  logic              mem_w_ready;
  logic [MEM_AW-1:0] mem_w_addr;
  logic [DATA_W-1:0] mem_w_data;
  logic              mem_r_valid;
  logic              mem_r_ready;
  logic [MEM_AW-1:0] mem_r_addr;
  logic              mem_r_rvalid;
  logic [DATA_W-1:0] mem_r_rdata;

  //---------------------------------------------------------------------------
  // Clocking blocks
  //   driver の valid は inout にして、握手を VALID && READY のサンプル値で判定する
  //---------------------------------------------------------------------------
  // 書き込みコマンドの driver
  clocking wdrv_cb @(posedge aclk);
    default input #1step output #1;
    inout  wcmd_valid;
    input  wcmd_ready;
    output wcmd_addr, wcmd_incr, wcmd_mem_addr, wcmd_len, wcmd_strb, wcmd_prot;
    input  wr_busy, wr_done, wr_done_err, wr_err_flags, wr_err_index, wr_done_count;
  endclocking

  // 読み出しコマンドの driver
  clocking rdrv_cb @(posedge aclk);
    default input #1step output #1;
    inout  rcmd_valid;
    input  rcmd_ready;
    output rcmd_addr, rcmd_incr, rcmd_mem_addr, rcmd_len, rcmd_prot;
    input  rd_busy, rd_done, rd_done_err, rd_err_flags, rd_err_index, rd_done_count;
  endclocking

  // ローカルポートの driver
  clocking ldrv_cb @(posedge aclk);
    default input #1step output #1;
    inout  mem_w_valid;
    input  mem_w_ready;
    output mem_w_addr, mem_w_data;
    inout  mem_r_valid;
    input  mem_r_ready;
    output mem_r_addr;
    input  mem_r_rvalid, mem_r_rdata;
  endclocking

  // monitor (観測のみ)
  clocking mon_cb @(posedge aclk);
    default input #1step;
    input wcmd_valid, wcmd_ready, wcmd_addr, wcmd_incr, wcmd_mem_addr, wcmd_len, wcmd_strb, wcmd_prot;
    input wr_busy, wr_done, wr_done_err, wr_err_flags, wr_err_index, wr_done_count;
    input rcmd_valid, rcmd_ready, rcmd_addr, rcmd_incr, rcmd_mem_addr, rcmd_len, rcmd_prot;
    input rd_busy, rd_done, rd_done_err, rd_err_flags, rd_err_index, rd_done_count;
    input mem_w_valid, mem_w_ready, mem_w_addr, mem_w_data;
    input mem_r_valid, mem_r_ready, mem_r_addr, mem_r_rvalid, mem_r_rdata;
  endclocking

  modport wdrv_mp ( clocking wdrv_cb, input aresetn );
  modport rdrv_mp ( clocking rdrv_cb, input aresetn );
  modport ldrv_mp ( clocking ldrv_cb, input aresetn );
  modport mon_mp ( clocking mon_cb, input aresetn );

`ifndef USR_IF_NO_SVA
  logic wcmd_fire;
  logic rcmd_fire;
  logic mem_r_fire;

  assign wcmd_fire  = wcmd_valid&&wcmd_ready;
  assign rcmd_fire  = rcmd_valid&&rcmd_ready;
  assign mem_r_fire = mem_r_valid&&mem_r_ready;

  // DUT : ready / busy
  a_wready_busy : assert property (
    @(posedge aclk) disable iff( !aresetn )
      (wcmd_ready==!wr_busy)
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "wcmd_ready is not the inverse of wr_busy");
  end

  a_rready_busy : assert property (
    @(posedge aclk) disable iff( !aresetn )
      (rcmd_ready==!rd_busy)
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "rcmd_ready is not the inverse of rd_busy");
  end

  // DUT : ローカル書き込みは読み出しコマンドの実行中だけ、ローカル読み出しは書き込みコマンドの実行中だけ待たせる
  a_mem_w_ready : assert property (
    @(posedge aclk) disable iff( !aresetn )
      (mem_w_ready==!rd_busy)
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "mem_w_ready is not the inverse of rd_busy");
  end

  a_mem_r_ready : assert property (
    @(posedge aclk) disable iff( !aresetn )
      (mem_r_ready==!wr_busy)
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "mem_r_ready is not the inverse of wr_busy");
  end

  // DUT : done は busy の最後の 1 サイクル
  a_wdone_busy : assert property (
    @(posedge aclk) disable iff( !aresetn )
      wr_done |-> wr_busy
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "wr_done is asserted while wr_busy is low");
  end

  a_wdone_pulse : assert property (
    @(posedge aclk) disable iff( !aresetn )
      wr_done |=> !wr_done&&!wr_busy
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "wr_done is not a 1-cycle pulse at the end of wr_busy");
  end

  a_rdone_busy : assert property (
    @(posedge aclk) disable iff( !aresetn )
      rd_done |-> rd_busy
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "rd_done is asserted while rd_busy is low");
  end

  a_rdone_pulse : assert property (
    @(posedge aclk) disable iff( !aresetn )
      rd_done |=> !rd_done&&!rd_busy
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "rd_done is not a 1-cycle pulse at the end of rd_busy");
  end

  // DUT : done_err は err_flags のどれかが立っているときだけ 1
  a_werr_flags : assert property (
    @(posedge aclk) disable iff( !aresetn )
      wr_done |-> (wr_done_err==(|wr_err_flags))
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "wr_done_err does not match wr_err_flags");
  end

  a_rerr_flags : assert property (
    @(posedge aclk) disable iff( !aresetn )
      rd_done |-> (rd_done_err==(|rd_err_flags))
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "rd_done_err does not match rd_err_flags");
  end

  // DUT : ステータスは done から次のコマンド受付まで変わらない
  a_wstatus_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      (wr_done||!wr_busy)&&!wcmd_fire |=> $stable({wr_done_err, wr_err_flags, wr_err_index, wr_done_count})
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "write status changed between done and the next command");
  end

  a_rstatus_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      (rd_done||!rd_busy)&&!rcmd_fire |=> $stable({rd_done_err, rd_err_flags, rd_err_index, rd_done_count})
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "read status changed between done and the next command");
  end

  // DUT : mem_r_rvalid は読み出しを受け付けた次のサイクルだけ 1
  a_rvalid_on : assert property (
    @(posedge aclk) disable iff( !aresetn )
      mem_r_fire |=> mem_r_rvalid
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "mem_r_rvalid is low in the cycle after a local read");
  end

  a_rvalid_off : assert property (
    @(posedge aclk) disable iff( !aresetn )
      !mem_r_fire |=> !mem_r_rvalid
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "mem_r_rvalid is high without a local read");
  end

  // テストベンチ : valid は握手まで下げず、内容も変えない
  a_wcmd_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      wcmd_valid&&!wcmd_ready |=> wcmd_valid&&$stable({wcmd_addr, wcmd_incr, wcmd_mem_addr, wcmd_len, wcmd_strb, wcmd_prot})
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "write command changed before handshake (testbench)");
  end

  a_rcmd_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      rcmd_valid&&!rcmd_ready |=> rcmd_valid&&$stable({rcmd_addr, rcmd_incr, rcmd_mem_addr, rcmd_len, rcmd_prot})
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "read command changed before handshake (testbench)");
  end

  a_mem_w_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      mem_w_valid&&!mem_w_ready |=> mem_w_valid&&$stable({mem_w_addr, mem_w_data})
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "local write changed before handshake (testbench)");
  end

  a_mem_r_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      mem_r_valid&&!mem_r_ready |=> mem_r_valid&&$stable(mem_r_addr)
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "local read changed before handshake (testbench)");
  end
`endif

endinterface
