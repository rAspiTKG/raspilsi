//=============================================================================
// axlm_uvm_pkg.sv
//-----------------------------------------------------------------------------
//  axil_master_mem (+ axil_to_axi4) 検証用 UVM パッケージ。
//  DUT が AXI マスタなので、テストベンチ側は
//    - ユーザ側 agent      : 書き込みコマンド / 読み出しコマンド / ローカルポートを別々に駆動
//    - AXI スレーブ agent  : 応答 (メモリ / READY の待ち / 応答の遅延 / エラー応答)
//  の 2 つで構成する。
//
//  コンパイル順 : uvm_pkg.sv -> axlm_params_pkg.sv -> axi_if.sv -> usr_if.sv
//                 -> axlm_uvm_pkg.sv -> tb_top.sv
//=============================================================================
`timescale 1ns / 1ps

package axlm_uvm_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axlm_params_pkg::*;

  //---------------------------------------------------------------------------
  // 型
  //---------------------------------------------------------------------------
  // virtual interface の型 (uvm_config_db の set / get で同じ名前を使う)
  typedef virtual axi_if axi_vif_t;
  typedef virtual usr_if usr_vif_t;

  //---------------------------------------------------------------------------
  // 共通の計算
  //---------------------------------------------------------------------------
  // ワード位置 → アドレス
  function automatic bit [63:0] axlm_waddr(input longint unsigned w);
    return w * 64'(STRB_W);
  endfunction

  //---------------------------------------------------------------------------
  // クラス
  //---------------------------------------------------------------------------
  `include "axi_item.svh"
  `include "axi_slv_mem.svh"
  `include "axi_slv_agent.svh"
  `include "usr_items.svh"
  `include "usr_agent.svh"
  `include "axlm_scoreboard.svh"
  `include "axlm_coverage.svh"
  `include "axlm_env.svh"
  `include "axlm_seq_lib.svh"
  `include "axlm_test_lib.svh"

endpackage
