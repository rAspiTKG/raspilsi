//=============================================================================
// axlm_params_pkg.sv
//-----------------------------------------------------------------------------
//  interface と UVM 環境で共有するパラメータ。DUT (axil_master_mem) と
//  axil_to_axi4 にも tb_top でこの値を渡す。
//
//  構成を変えるときは、コンパイル時に +define+AXLM_xxx=値 で上書きする
//  (sim/Makefile の CFG_* を参照)。
//=============================================================================
`timescale 1ns / 1ps

`ifndef AXLM_ADDR_W
  `define AXLM_ADDR_W 32
`endif
`ifndef AXLM_DATA_W
  `define AXLM_DATA_W 32
`endif
`ifndef AXLM_MEM_DEPTH
  `define AXLM_MEM_DEPTH 16
`endif
`ifndef AXLM_MAX_WR
  `define AXLM_MAX_WR 4
`endif
`ifndef AXLM_MAX_RD
  `define AXLM_MAX_RD 4
`endif
`ifndef AXLM_STOP_ON_ERROR
  `define AXLM_STOP_ON_ERROR 1
`endif

package axlm_params_pkg;

  //---------------------------------------------------------------------------
  // DUT のパラメータ
  //---------------------------------------------------------------------------
  parameter int unsigned ADDR_W        = `AXLM_ADDR_W;
  parameter int unsigned DATA_W        = `AXLM_DATA_W;
  parameter int unsigned MEM_DEPTH     = `AXLM_MEM_DEPTH;
  parameter int unsigned MAX_WR        = `AXLM_MAX_WR;
  parameter int unsigned MAX_RD        = `AXLM_MAX_RD;
  parameter bit          STOP_ON_ERROR = (`AXLM_STOP_ON_ERROR!=0);
  // axil_to_axi4
  parameter int unsigned ID_W          = 4;
  parameter logic [3:0]  QOS           = 4'b0101;

  //---------------------------------------------------------------------------
  // 派生値
  //---------------------------------------------------------------------------
  parameter int unsigned     STRB_W      = DATA_W / 8;
  parameter int unsigned     STRB_LSB    = $clog2(STRB_W);
  parameter logic [2:0]      SIZE_FULL   = 3'(STRB_LSB);
  parameter int unsigned     MEM_AW      = (MEM_DEPTH<2) ? 1 : $clog2(MEM_DEPTH);
  parameter int unsigned     LEN_W       = $clog2(MEM_DEPTH+1);
  parameter int unsigned     LEN_MAXV    = (1<<LEN_W) - 1;
  // アドレス空間のワード数
  parameter longint unsigned SPACE_WORDS = 64'd1 << (ADDR_W-STRB_LSB);
  // 書き込みコマンド用 / 読み出しコマンド用の窓 (スレーブのワード位置)。
  //   同時に動く書き込みと読み出しが、同じアドレスを触らないように分ける。
  //   アドレス空間が広ければ、上位ビットが 1 になる位置 (空間の中央) に置く
  parameter longint unsigned WIN         = ((SPACE_WORDS/2)<64'(MEM_DEPTH)) ? (SPACE_WORDS/2) : 64'(MEM_DEPTH);
  parameter longint unsigned WB          = (SPACE_WORDS>=(4*WIN)) ? (SPACE_WORDS/2) : 64'd0;
  parameter longint unsigned RB          = WB + WIN;
  parameter int unsigned     LWIN        = int'(WIN);
  // ローカルポートのアドレスで、範囲外 (MEM_DEPTH 以上) を表せるか
  parameter bit              HAS_BAD_MEM = ((64'd1<<MEM_AW)>64'(MEM_DEPTH));

endpackage
