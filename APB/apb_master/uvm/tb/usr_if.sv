//=============================================================================
// usr_if.sv
//-----------------------------------------------------------------------------
//  apb_master_mem のユーザ側 interface。
//    cmd_*  : コマンド (valid/ready)
//    busy / done / done_err / err_flags / err_index / done_count : ステータス
//    mem_*  : 内部メモリのローカルポート (valid/ready、読み出しは次サイクルに mem_rvalid)
//
//  SVA:
//    DUT          : busy と cmd_ready / mem_ready の関係、done は 1 サイクル、
//                   done_err == |err_flags、ステータスは次のコマンド受付まで保持、
//                   mem_rvalid は読み出しを受け付けた次のサイクルだけ 1
//    テストベンチ : cmd_valid / mem_valid は握手まで下げず、内容も変えない
//=============================================================================
`timescale 1ns / 1ps

interface usr_if (
  input logic pclk
 ,input logic presetn
);

  import apbm_params_pkg::*;

  //---------------------------------------------------------------------------
  // コマンド
  //---------------------------------------------------------------------------
  logic              cmd_valid;
  logic              cmd_ready;
  logic              cmd_write;
  logic [SEL_W-1:0]  cmd_sel;
  logic [ADDR_W-1:0] cmd_addr;
  logic              cmd_incr;
  logic [MEM_AW-1:0] cmd_mem_addr;
  logic [LEN_W-1:0]  cmd_len;
  logic [STRB_W-1:0] cmd_strb;
  logic [2:0]        cmd_prot;
  //---------------------------------------------------------------------------
  // ステータス
  //---------------------------------------------------------------------------
  logic              busy;
  logic              done;
  logic              done_err;
  logic [2:0]        err_flags;
  logic [LEN_W-1:0]  err_index;
  logic [LEN_W-1:0]  done_count;
  //---------------------------------------------------------------------------
  // 内部メモリのローカルポート
  //---------------------------------------------------------------------------
  logic              mem_valid;
  logic              mem_ready;
  logic              mem_write;
  logic [MEM_AW-1:0] mem_addr;
  logic [DATA_W-1:0] mem_wdata;
  logic              mem_rvalid;
  logic [DATA_W-1:0] mem_rdata;

  //---------------------------------------------------------------------------
  // Clocking blocks
  //---------------------------------------------------------------------------
  // driver : valid は inout にして、握手を VALID && READY のサンプル値で判定する
  clocking drv_cb @(posedge pclk);
    default input #1step output #1;
    inout  cmd_valid;
    input  cmd_ready;
    output cmd_write, cmd_sel, cmd_addr, cmd_incr, cmd_mem_addr, cmd_len, cmd_strb, cmd_prot;
    input  busy, done, done_err, err_flags, err_index, done_count;
    inout  mem_valid;
    input  mem_ready;
    output mem_write, mem_addr, mem_wdata;
    input  mem_rvalid, mem_rdata;
  endclocking

  // monitor (観測のみ)
  clocking mon_cb @(posedge pclk);
    default input #1step;
    input cmd_valid, cmd_ready, cmd_write, cmd_sel, cmd_addr, cmd_incr, cmd_mem_addr, cmd_len, cmd_strb, cmd_prot;
    input busy, done, done_err, err_flags, err_index, done_count;
    input mem_valid, mem_ready, mem_write, mem_addr, mem_wdata, mem_rvalid, mem_rdata;
  endclocking

  modport drv_mp ( clocking drv_cb, input presetn );
  modport mon_mp ( clocking mon_cb, input presetn );

`ifndef USR_IF_NO_SVA
  logic cmd_fire;
  logic mem_rd_fire;

  assign cmd_fire    = cmd_valid&&cmd_ready;
  assign mem_rd_fire = mem_valid&&mem_ready&&!mem_write;

  // DUT : busy のときだけ cmd_ready=0
  a_ready_busy : assert property (
    @(posedge pclk) disable iff( !presetn )
      (cmd_ready==!busy)
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "cmd_ready is not the inverse of busy");
  end

  // DUT : ローカルポートはアイドル時だけ受け付ける
  a_mem_ready : assert property (
    @(posedge pclk) disable iff( !presetn )
      (mem_ready==!busy)
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "mem_ready is not the inverse of busy");
  end

  // DUT : done は busy の最後の 1 サイクル
  a_done_pulse : assert property (
    @(posedge pclk) disable iff( !presetn )
      done |=> !done&&!busy
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "done is not a 1-cycle pulse at the end of busy");
  end

  a_done_busy : assert property (
    @(posedge pclk) disable iff( !presetn )
      done |-> busy
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "done is asserted while busy is low");
  end

  // DUT : done_err は err_flags のどれかが立っているときだけ 1
  a_err_flags : assert property (
    @(posedge pclk) disable iff( !presetn )
      done |-> (done_err==(|err_flags))
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "done_err does not match err_flags");
  end

  // DUT : ステータスは done から次のコマンド受付まで変わらない
  a_status_hold_done : assert property (
    @(posedge pclk) disable iff( !presetn )
      done |=> $stable({done_err, err_flags, err_index, done_count})
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "status changed right after done");
  end

  a_status_hold_idle : assert property (
    @(posedge pclk) disable iff( !presetn )
      !busy&&!cmd_fire |=> $stable({done_err, err_flags, err_index, done_count})
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "status changed while idle");
  end

  // DUT : mem_rvalid は読み出しを受け付けた次のサイクルだけ 1
  a_rvalid_on : assert property (
    @(posedge pclk) disable iff( !presetn )
      mem_rd_fire |=> mem_rvalid
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "mem_rvalid is low in the cycle after a local read");
  end

  a_rvalid_off : assert property (
    @(posedge pclk) disable iff( !presetn )
      !mem_rd_fire |=> !mem_rvalid
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "mem_rvalid is high without a local read");
  end

  // テストベンチ : cmd_valid / mem_valid は握手まで下げず、内容も変えない
  a_cmd_hold : assert property (
    @(posedge pclk) disable iff( !presetn )
      cmd_valid&&!cmd_ready |=> cmd_valid&&$stable({cmd_write, cmd_sel, cmd_addr, cmd_incr, cmd_mem_addr, cmd_len, cmd_strb, cmd_prot})
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "command changed before handshake (testbench)");
  end

  a_mem_hold : assert property (
    @(posedge pclk) disable iff( !presetn )
      mem_valid&&!mem_ready |=> mem_valid&&$stable({mem_write, mem_addr, mem_wdata})
  ) else begin
    uvm_pkg::uvm_report_error("USR_SVA", "local access changed before handshake (testbench)");
  end
`endif

endinterface
