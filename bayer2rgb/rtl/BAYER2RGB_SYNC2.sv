// ============================================================================
// BAYER2RGB_SYNC2 : 2段同期化のラッパ
//   1ビットのトグル・レベル信号の同期化だけに使う(多ビットのデータは通さない)。
//   このファイルはシミュレーション用で、振る舞いモデル BAYER2RGB_SYNC2_BHV を使う。
//   論理合成では syn/rtl/<PDK>/BAYER2RGB_SYNC2.sv を代わりに読み、
//   スタンダードセルライブラリの同期化専用セル(Foundry のプロセス)や FF 2段(ASAP7)を置く。
// ============================================================================
module BAYER2RGB_SYNC2 #(
  parameter int            DW   = 1
 ,parameter logic [DW-1:0] INIT = '0
) (
  input  logic          clk
 ,input  logic          rst_n
 ,input  logic [DW-1:0] i_d
 ,output logic [DW-1:0] o_q
);

  BAYER2RGB_SYNC2_BHV #(
    .DW   (DW)
   ,.INIT (INIT)
  ) u_sync (
    .clk   (clk)
   ,.rst_n (rst_n)
   ,.i_d   (i_d)
   ,.o_q   (o_q)
  );

endmodule
