//=============================================================================
// cmd_if.sv
//-----------------------------------------------------------------------------
//  コピーエンジンのコマンド / ステータス interface。
//    cmd_valid / cmd_ready : valid/ready (cmd_valid は握手まで保持)
//    busy / done / done_err: DUT からのステータス (done は 1 サイクルパルス)
//=============================================================================
`timescale 1ns / 1ps

interface cmd_if (
  input logic aclk
 ,input logic aresetn
);

  import axi_params_pkg::*;

  logic              cmd_valid;
  logic              cmd_ready;
  logic [ADDR_W-1:0] cmd_src;
  logic [ADDR_W-1:0] cmd_dst;
  logic [LEN_W-1:0]  cmd_len;
  logic              busy;
  logic              done;
  logic              done_err;

  // driver : cmd_valid は inout にして握手を VALID && READY で判定する
  clocking drv_cb @(posedge aclk);
    default input #1step output #1;
    inout  cmd_valid;
    input  cmd_ready;
    output cmd_src, cmd_dst, cmd_len;
    input  busy, done, done_err;
  endclocking

  clocking mon_cb @(posedge aclk);
    default input #1step;
    input cmd_valid, cmd_ready, cmd_src, cmd_dst, cmd_len, busy, done, done_err;
  endclocking

  modport drv_mp ( clocking drv_cb, input aresetn );
  modport mon_mp ( clocking mon_cb, input aresetn );

`ifndef CMD_IF_NO_SVA
  // DUT : busy 中はコマンドを受け付けない
  a_ready_idle : assert property (
    @(posedge aclk) disable iff( !aresetn )
      busy |-> !cmd_ready
  ) else begin
    uvm_pkg::uvm_report_error("CMD_SVA", "cmd_ready asserted while busy");
  end

  // DUT : done は 1 サイクルのパルス
  a_done_pulse : assert property (
    @(posedge aclk) disable iff( !aresetn )
      done |=> !done
  ) else begin
    uvm_pkg::uvm_report_error("CMD_SVA", "done is longer than one cycle");
  end
`endif

endinterface
