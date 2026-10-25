// ============================================================================
// BAYER2RGB_SRAM_1R1W : 1R1W SRAMのラッパ
//   読み出しレイテンシ1。i_ren=0 のとき o_rdata は前の値を保持する。
//   同一アドレスの同時読み書きはしない(呼び出し側で保証する)。
//
//   このファイルはシミュレーション用で、振る舞いモデル BAYER2RGB_SRAM_1R1W_BHV を使う。
//   論理合成では syn/rtl/<PDK>/BAYER2RGB_SRAM_1R1W.sv(同じ名前・同じ端子のラッパ)を
//   代わりに読み、SRAM コンパイラ(Foundry のプロセス)や仮マクロ(ASAP7)のマクロを置く。
// ============================================================================
module BAYER2RGB_SRAM_1R1W #(
  parameter int DEPTH = 480
 ,parameter int DW    = 112
 ,parameter int AW    = $clog2(DEPTH)
) (
  input  logic          clk
 ,input  logic          i_ren
 ,input  logic [AW-1:0] i_raddr
 ,output logic [DW-1:0] o_rdata
 ,input  logic          i_wen
 ,input  logic [AW-1:0] i_waddr
 ,input  logic [DW-1:0] i_wdata
);

  BAYER2RGB_SRAM_1R1W_BHV #(
    .DEPTH (DEPTH)
   ,.DW    (DW)
   ,.AW    (AW)
  ) u_mem (
    .clk     (clk)
   ,.i_ren   (i_ren)
   ,.i_raddr (i_raddr)
   ,.o_rdata (o_rdata)
   ,.i_wen   (i_wen)
   ,.i_waddr (i_waddr)
   ,.i_wdata (i_wdata)
  );

endmodule
