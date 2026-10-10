//=============================================================================
// apbm_params_pkg.sv
//-----------------------------------------------------------------------------
//  interface と UVM 環境で共有するパラメータ。DUT (apb_master_mem) にも
//  tb_top でこの値を渡す。
//
//  構成を変えるときは、コンパイル時に +define+APBM_xxx=値 で上書きする
//  (sim/Makefile の CFG_* を参照)。
//=============================================================================
`timescale 1ns / 1ps

`ifndef APBM_ADDR_W
  `define APBM_ADDR_W 32
`endif
`ifndef APBM_DATA_W
  `define APBM_DATA_W 32
`endif
`ifndef APBM_NUM_SLAVES
  `define APBM_NUM_SLAVES 3
`endif
`ifndef APBM_MEM_DEPTH
  `define APBM_MEM_DEPTH 16
`endif
`ifndef APBM_TIMEOUT_CYCLES
  `define APBM_TIMEOUT_CYCLES 6
`endif
`ifndef APBM_STOP_ON_ERROR
  `define APBM_STOP_ON_ERROR 1
`endif

package apbm_params_pkg;

  //---------------------------------------------------------------------------
  // DUT のパラメータ
  //---------------------------------------------------------------------------
  parameter int unsigned ADDR_W         = `APBM_ADDR_W;
  parameter int unsigned DATA_W         = `APBM_DATA_W;
  parameter int unsigned NUM_SLAVES     = `APBM_NUM_SLAVES;
  parameter int unsigned MEM_DEPTH      = `APBM_MEM_DEPTH;
  parameter int unsigned TIMEOUT_CYCLES = `APBM_TIMEOUT_CYCLES;
  parameter bit          STOP_ON_ERROR  = (`APBM_STOP_ON_ERROR!=0);

  //---------------------------------------------------------------------------
  // 派生値
  //---------------------------------------------------------------------------
  parameter int unsigned STRB_W = DATA_W / 8;
  parameter int unsigned SEL_W  = (NUM_SLAVES<2) ? 1 : $clog2(NUM_SLAVES);
  parameter int unsigned MEM_AW = (MEM_DEPTH<2) ? 1 : $clog2(MEM_DEPTH);
  parameter int unsigned LEN_W  = $clog2(MEM_DEPTH+1);

  // アドレス空間の大きさ
  parameter longint unsigned SPACE_BYTES = 64'd1 << ADDR_W;
  parameter longint unsigned SPACE_WORDS = SPACE_BYTES / 64'(STRB_W);
  // 有効なコマンドで使える最大ワード数
  parameter int unsigned LMAX = (SPACE_WORDS<64'(MEM_DEPTH)) ? int'(SPACE_WORDS) : MEM_DEPTH;

  // 存在しないスレーブ番号 / 範囲外のメモリアドレスをポートのビット幅で表せるか
  parameter bit HAS_BAD_SEL = ((1<<SEL_W)>NUM_SLAVES);
  parameter bit HAS_BAD_MEM = ((1<<MEM_AW)>MEM_DEPTH);

  // タイムアウトさせない範囲でのウェイトの上限
  parameter int unsigned WAIT_MAX = (TIMEOUT_CYCLES==0) ? 4 : ((TIMEOUT_CYCLES>4) ? 4 : (TIMEOUT_CYCLES-1));

endpackage
