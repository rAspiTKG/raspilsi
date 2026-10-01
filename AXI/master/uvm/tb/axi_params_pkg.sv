//=============================================================================
// axi_params_pkg.sv
//-----------------------------------------------------------------------------
//  interface と UVM 環境で共有するパラメータ。
//  DUT (axi4_full_master_copy) のパラメータと一致させること。
//=============================================================================
`timescale 1ns / 1ps

package axi_params_pkg;

  parameter int ADDR_W    = 32;
  parameter int DATA_W    = 64;
  parameter int ID_W      = 4;
  parameter int STRB_W    = DATA_W / 8;
  parameter int ADDR_LSB  = $clog2(STRB_W);

  // DUT
  parameter int LEN_W     = 16;     // cmd_len のビット幅 (ビート数)
  parameter int MAX_BURST = 16;     // 1 バーストの最大ビート数
  parameter int BUF_DEPTH = 32;     // 内部バッファ深さ (>= 2*MAX_BURST)
  parameter int RD_ID     = 0;
  parameter int WR_ID     = 1;

  // テストで使うアドレス窓 (src と dst が重ならないように分ける)
  parameter bit [ADDR_W-1:0] SRC_LO = 32'h0000_0000;
  parameter bit [ADDR_W-1:0] SRC_HI = 32'h000F_FFFF;
  parameter bit [ADDR_W-1:0] DST_LO = 32'h0010_0000;
  parameter bit [ADDR_W-1:0] DST_HI = 32'h001F_FFFF;

endpackage
