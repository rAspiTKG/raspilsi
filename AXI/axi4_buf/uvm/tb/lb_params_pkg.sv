//=============================================================================
// lb_params_pkg.sv
//-----------------------------------------------------------------------------
//  interface と UVM 環境で共有するパラメータ。DUT (axi4_master_linebuf) にも
//  tb_top でこの値を渡す。
//
//  構成を変えるときは、コンパイル時に +define+LB_xxx=値 で上書きする
//  (sim/Makefile の CFG_* を参照)。
//=============================================================================
`timescale 1ns / 1ps

`ifndef LB_IN_ADDR_W
  `define LB_IN_ADDR_W 32
`endif
`ifndef LB_IN_DATA_W
  `define LB_IN_DATA_W 64
`endif
`ifndef LB_IN_ID_W
  `define LB_IN_ID_W 4
`endif
`ifndef LB_IN_AXI_ID
  `define LB_IN_AXI_ID 2
`endif
`ifndef LB_IN_MAX_BURST
  `define LB_IN_MAX_BURST 16
`endif
`ifndef LB_IN_FIFO_DEPTH
  `define LB_IN_FIFO_DEPTH 32
`endif
`ifndef LB_OUT_ADDR_W
  `define LB_OUT_ADDR_W 32
`endif
`ifndef LB_OUT_DATA_W
  `define LB_OUT_DATA_W 64
`endif
`ifndef LB_OUT_ID_W
  `define LB_OUT_ID_W 4
`endif
`ifndef LB_OUT_AXI_ID
  `define LB_OUT_AXI_ID 5
`endif
`ifndef LB_OUT_MAX_BURST
  `define LB_OUT_MAX_BURST 16
`endif
`ifndef LB_OUT_FIFO_DEPTH
  `define LB_OUT_FIFO_DEPTH 32
`endif
`ifndef LB_PIXEL_BITS
  `define LB_PIXEL_BITS 8
`endif
`ifndef LB_PIX_MEM_BITS
  `define LB_PIX_MEM_BITS (((`LB_PIXEL_BITS + 7) / 8) * 8)
`endif
`ifndef LB_PIX_ALIGN_MSB
  `define LB_PIX_ALIGN_MSB 0
`endif
`ifndef LB_PIX_PER_WORD
  `define LB_PIX_PER_WORD 2
`endif
`ifndef LB_MAX_LINE_PIXELS
  `define LB_MAX_LINE_PIXELS 200
`endif
`ifndef LB_NUM_LINES
  `define LB_NUM_LINES 4
`endif

package lb_params_pkg;

  //---------------------------------------------------------------------------
  // DUT のパラメータ
  //---------------------------------------------------------------------------
  parameter int unsigned IN_ADDR_W       = `LB_IN_ADDR_W;
  parameter int unsigned IN_DATA_W       = `LB_IN_DATA_W;
  parameter int unsigned IN_ID_W         = `LB_IN_ID_W;
  parameter int unsigned IN_AXI_ID       = `LB_IN_AXI_ID;
  parameter int unsigned IN_MAX_BURST    = `LB_IN_MAX_BURST;
  parameter int unsigned IN_FIFO_DEPTH   = `LB_IN_FIFO_DEPTH;
  parameter int unsigned OUT_ADDR_W      = `LB_OUT_ADDR_W;
  parameter int unsigned OUT_DATA_W      = `LB_OUT_DATA_W;
  parameter int unsigned OUT_ID_W        = `LB_OUT_ID_W;
  parameter int unsigned OUT_AXI_ID      = `LB_OUT_AXI_ID;
  parameter int unsigned OUT_MAX_BURST   = `LB_OUT_MAX_BURST;
  parameter int unsigned OUT_FIFO_DEPTH  = `LB_OUT_FIFO_DEPTH;
  parameter int unsigned PIXEL_BITS      = `LB_PIXEL_BITS;
  parameter int unsigned PIX_MEM_BITS    = `LB_PIX_MEM_BITS;
  parameter bit          PIX_ALIGN_MSB   = `LB_PIX_ALIGN_MSB;
  parameter int unsigned PIX_PER_WORD    = `LB_PIX_PER_WORD;
  parameter int unsigned MAX_LINE_PIXELS = `LB_MAX_LINE_PIXELS;
  parameter int unsigned NUM_LINES       = `LB_NUM_LINES;
  parameter int unsigned HEIGHT_W        = 16;
  parameter int unsigned STRIDE_W        = 20;

  // DUT に渡す AXI 属性 (既定値と違う値にして、出力に反映されることを確認する)
  parameter bit [3:0] ARCACHE_V  = 4'b1011;
  parameter bit [2:0] ARPROT_V   = 3'b010;
  parameter bit [3:0] ARQOS_V    = 4'd3;
  parameter bit [3:0] ARREGION_V = 4'd6;
  parameter bit [3:0] AWCACHE_V  = 4'b0111;
  parameter bit [2:0] AWPROT_V   = 3'b001;
  parameter bit [3:0] AWQOS_V    = 4'd9;
  parameter bit [3:0] AWREGION_V = 4'd12;

  //---------------------------------------------------------------------------
  // 派生値
  //---------------------------------------------------------------------------
  parameter int unsigned IN_STRB_W   = IN_DATA_W / 8;
  parameter int unsigned OUT_STRB_W  = OUT_DATA_W / 8;
  parameter int unsigned XW          = $clog2(MAX_LINE_PIXELS+1);
  parameter int unsigned LVL_W       = $clog2(NUM_LINES+1);
  parameter int unsigned PIX_OFS     = PIX_ALIGN_MSB ? (PIX_MEM_BITS - PIXEL_BITS) : 0;
  parameter int unsigned MAX_DATA_W  = (IN_DATA_W>OUT_DATA_W) ? IN_DATA_W : OUT_DATA_W;
  parameter int unsigned MAX_STRB_W  = MAX_DATA_W / 8;

  // テストで使うライン数の上限 (scratchpad を 3 周以上回す)
  parameter int unsigned MAX_H       = (3 * NUM_LINES) + 2;

endpackage
