// ============================================================================
// BAYER2RGB_SYNC2 : 2段同期化のラッパ
//   1ビットのトグル・レベル信号の同期化だけに使う(多ビットのデータは通さない)。
//   量産時はスタンダードセルライブラリの同期化専用セルに置き換える。
//   シミュレーションでは振る舞いモデル BAYER2RGB_SYNC2_BHV を使う。
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
