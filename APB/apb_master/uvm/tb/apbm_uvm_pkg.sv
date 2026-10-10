//=============================================================================
// apbm_uvm_pkg.sv
//-----------------------------------------------------------------------------
//  apb_master_mem 検証用 UVM パッケージ。
//  DUT が APB マスタなので、テストベンチ側は
//    - ユーザ側 agent      : コマンドの発行と、内部メモリのローカルポートの読み書き
//    - APB スレーブ agent  : 全スレーブぶんの応答 (メモリ / ウェイト / PSLVERR / ハング)
//  の 2 つで構成する。
//
//  コンパイル順 : uvm_pkg.sv -> apbm_params_pkg.sv -> apb_if.sv -> usr_if.sv
//                 -> apbm_uvm_pkg.sv -> tb_top.sv
//=============================================================================
`timescale 1ns / 1ps

package apbm_uvm_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import apbm_params_pkg::*;

  //---------------------------------------------------------------------------
  // 型
  //---------------------------------------------------------------------------
  // virtual interface の型 (uvm_config_db の set / get で同じ名前を使う)
  typedef virtual apb_if apb_vif_t;
  typedef virtual usr_if usr_vif_t;

  // ユーザ側 driver への操作
  typedef enum {
    OP_MEM_WR
   ,OP_MEM_RD
   ,OP_CMD
  } usr_op_e;

  //---------------------------------------------------------------------------
  // コマンドの計算 (DUT と同じ定義)
  //---------------------------------------------------------------------------
  // ワード位置 → アドレス
  function automatic bit [63:0] apbm_waddr(input longint unsigned w);
    return w * 64'(STRB_W);
  endfunction

  // コマンドの i 番目の転送のアドレス
  function automatic bit [63:0] apbm_xaddr(input bit [63:0] addr, input bit incr, input int unsigned i);
    if( incr ) begin
      return addr + (64'(i) * 64'(STRB_W));
    end
    return addr;
  endfunction

  // DUT が err_flags[2] で断る条件
  function automatic bit apbm_sel_bad(input int unsigned sel);
    return (sel>=NUM_SLAVES);
  endfunction

  function automatic bit apbm_mem_bad(input int unsigned maddr, input int unsigned len);
    return ((maddr+len)>MEM_DEPTH);
  endfunction

  function automatic bit apbm_align_bad(input bit [63:0] addr);
    return ((addr % 64'(STRB_W))!=64'd0);
  endfunction

  function automatic bit apbm_range_bad(input bit [63:0] addr, input bit incr, input int unsigned len);
    return incr&&((addr + (64'(len) * 64'(STRB_W)))>SPACE_BYTES);
  endfunction

  //---------------------------------------------------------------------------
  // クラス
  //---------------------------------------------------------------------------
  `include "apb_item.svh"
  `include "apb_slv_mem.svh"
  `include "apb_slv_agent.svh"
  `include "usr_agent.svh"
  `include "apbm_scoreboard.svh"
  `include "apbm_coverage.svh"
  `include "apbm_env.svh"
  `include "apbm_seq_lib.svh"
  `include "apbm_test_lib.svh"

endpackage
