//=============================================================================
// cmd_if.sv
//-----------------------------------------------------------------------------
//  axi4_master_linebuf のコマンド / ステータス interface。
//    cmd_valid / cmd_ready : valid/ready (cmd_valid は握手まで保持)
//    busy / done / done_err / err_flags : DUT からのステータス (done は 1 サイクル)
//    line_in_done / line_out_done / sp_level : scratchpad の状況
//=============================================================================
`timescale 1ns / 1ps

interface cmd_if (
  input logic aclk
 ,input logic aresetn
);

  import lb_params_pkg::*;

  logic                  cmd_valid;
  logic                  cmd_ready;
  logic [IN_ADDR_W-1:0]  cmd_src_addr;
  logic [OUT_ADDR_W-1:0] cmd_dst_addr;
  logic [STRIDE_W-1:0]   cmd_src_stride;
  logic [STRIDE_W-1:0]   cmd_dst_stride;
  logic [XW-1:0]         cmd_width;
  logic [HEIGHT_W-1:0]   cmd_height;
  logic                  busy;
  logic                  done;
  logic                  done_err;
  logic [2:0]            err_flags;
  logic                  line_in_done;
  logic                  line_out_done;
  logic [LVL_W-1:0]      sp_level;

  // driver : cmd_valid は inout にして握手を VALID && READY で判定する
  clocking drv_cb @(posedge aclk);
    default input #1step output #1;
    inout  cmd_valid;
    input  cmd_ready;
    output cmd_src_addr, cmd_dst_addr, cmd_src_stride, cmd_dst_stride, cmd_width, cmd_height;
    input  busy, done, done_err, err_flags;
  endclocking

  clocking mon_cb @(posedge aclk);
    default input #1step;
    input cmd_valid, cmd_ready, cmd_src_addr, cmd_dst_addr, cmd_src_stride, cmd_dst_stride, cmd_width, cmd_height;
    input busy, done, done_err, err_flags, line_in_done, line_out_done, sp_level;
  endclocking

  modport drv_mp ( clocking drv_cb, input aresetn );
  modport mon_mp ( clocking mon_cb, input aresetn );

`ifndef CMD_IF_NO_SVA
  // DUT : busy 中はコマンドを受け付けない
  a_ready_idle : assert property (
    @(posedge aclk) disable iff( !aresetn )
      busy |-> !cmd_ready
  ) else begin
    uvm_pkg::uvm_report_error("CMD_SVA", "cmd_ready is high while busy");
  end

  // DUT : done は 1 サイクル
  a_done_pulse : assert property (
    @(posedge aclk) disable iff( !aresetn )
      done |=> !done
  ) else begin
    uvm_pkg::uvm_report_error("CMD_SVA", "done is longer than 1 cycle");
  end

  // DUT : done_err は err_flags のどれかが立っているときだけ 1
  a_err_flags : assert property (
    @(posedge aclk) disable iff( !aresetn )
      done |-> (done_err==(|err_flags))
  ) else begin
    uvm_pkg::uvm_report_error("CMD_SVA", "done_err does not match err_flags");
  end

  // DUT : scratchpad の格納ライン数は NUM_LINES 以下
  a_sp_level : assert property (
    @(posedge aclk) disable iff( !aresetn )
      (32'(sp_level)<=NUM_LINES)
  ) else begin
    uvm_pkg::uvm_report_error("CMD_SVA", "sp_level exceeds NUM_LINES");
  end

  // テストベンチ : cmd_valid は握手まで下げず、内容も変えない
  a_cmd_hold : assert property (
    @(posedge aclk) disable iff( !aresetn )
      cmd_valid&&!cmd_ready |=> cmd_valid&&$stable({cmd_src_addr, cmd_dst_addr, cmd_src_stride, cmd_dst_stride, cmd_width, cmd_height})
  ) else begin
    uvm_pkg::uvm_report_error("CMD_SVA", "command changed before handshake (testbench)");
  end
`endif

endinterface
