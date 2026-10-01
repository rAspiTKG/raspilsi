//=============================================================================
// copy_uvm_pkg.sv
//-----------------------------------------------------------------------------
//  axi4_full_master_copy (AXI4-Full マスタ) 検証用 UVM パッケージ。
//  DUT がマスタなので、テストベンチ側は
//    - コマンド agent        : copy コマンドを発行し、done を待つ
//    - AXI スレーブ agent    : 共有メモリモデルで AW/W/B, AR/R に応答する
//  の 2 つで構成する。
//
//  コンパイル順 : uvm_pkg.sv -> axi_params_pkg.sv -> axi_if.sv -> cmd_if.sv
//                 -> copy_uvm_pkg.sv -> tb_top.sv
//=============================================================================
`timescale 1ns / 1ps

package copy_uvm_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi_params_pkg::*;

  //---------------------------------------------------------------------------
  // 型 / 定数
  //---------------------------------------------------------------------------
  typedef enum bit {
     AXI_WRITE = 1'b0
    ,AXI_READ  = 1'b1
  } axi_dir_e;

  typedef enum bit [1:0] {
     AXI_FIXED = 2'b00
    ,AXI_INCR  = 2'b01
    ,AXI_WRAP  = 2'b10
  } axi_burst_e;

  // virtual interface の型 (uvm_config_db の set / get で同じ名前を使う)
  typedef virtual axi_if axi_vif_t;
  typedef virtual cmd_if cmd_vif_t;

  parameter bit [1:0] AXI_OKAY   = 2'b00;
  parameter bit [1:0] AXI_SLVERR = 2'b10;

  parameter bit [STRB_W-1:0] STRB_ALL = {STRB_W{1'b1}};

  //---------------------------------------------------------------------------
  // バースト内 beat 番目の転送アドレス (AXI4 spec A3.4.1)
  //---------------------------------------------------------------------------
  function automatic bit [ADDR_W-1:0] axi_beat_addr
  (
    input bit [ADDR_W-1:0] start
   ,input bit [7:0]        len
   ,input bit [2:0]        size
   ,input axi_burst_e      burst
   ,input int unsigned     beat
  );
    bit [ADDR_W-1:0] nbytes;
    bit [ADDR_W-1:0] total;
    bit [ADDR_W-1:0] lo;
    bit [ADDR_W-1:0] a;
    nbytes = ADDR_W'(1) << size;
    case( burst )
      AXI_FIXED : begin
        a = start;
      end
      AXI_WRAP : begin
        total = nbytes * (ADDR_W'(len) + ADDR_W'(1));
        lo    = start & ~(total - ADDR_W'(1));
        a     = lo + ((start - lo + (nbytes * ADDR_W'(beat))) % total);
      end
      default : begin
        if( beat==0 ) begin
          a = start;
        end else begin
          a = (start & ~(nbytes - ADDR_W'(1))) + (nbytes * ADDR_W'(beat));
        end
      end
    endcase
    return a;
  endfunction

  //---------------------------------------------------------------------------
  // クラス
  //---------------------------------------------------------------------------
  `include "axi_burst_item.svh"
  `include "axi_mem.svh"
  `include "axi_slv_agent.svh"
  `include "cmd_agent.svh"
  `include "copy_scoreboard.svh"
  `include "copy_coverage.svh"
  `include "copy_env.svh"
  `include "copy_seq_lib.svh"
  `include "copy_test_lib.svh"

endpackage
