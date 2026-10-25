// ============================================================================
// BAYER2RGB_SYNC2 : 2段同期化(論理合成用、Foundry のプロセス。雛形)
//   rtl/BAYER2RGB_SYNC2.sv(振る舞いモデルを呼ぶ)の代わりに読む。
//   スタンダードセルライブラリの同期化専用セル(2段の FF を1つにしたセル)を1ビットずつ置く。
//
//   ★ セル名と端子名は記入例。PDK のセルに合わせて書き換える
//       B2R_SYNC2_RCELL  非同期リセットで 0 になる同期化セル(CLK, RN, D, Q)
//       B2R_SYNC2_SCELL  非同期セットで 1 になる同期化セル  (CLK, SN, D, Q)
//     同じ名前を pd/commercial/setup/foundry_setup.tcl の B2R_SYNC2_CELLS に書く
//     (合成・配置配線で最適化しないようにするため)
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

  for( genvar i=0; i<DW; i++ ) begin : g_bit
    if( INIT[i]==1'b0 ) begin : g_r
      B2R_SYNC2_RCELL u_sync (
        .CLK (clk)
       ,.RN  (rst_n)
       ,.D   (i_d[i])
       ,.Q   (o_q[i])
      );
    end else begin : g_s
      B2R_SYNC2_SCELL u_sync (
        .CLK (clk)
       ,.SN  (rst_n)
       ,.D   (i_d[i])
       ,.Q   (o_q[i])
      );
    end
  end

endmodule
