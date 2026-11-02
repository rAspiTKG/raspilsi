// ============================================================================
// BAYER2RGB_SYNC2 : 2段同期化(論理合成用、ASAP7)
//   rtl/BAYER2RGB_SYNC2.sv(振る舞いモデルを呼ぶ)の代わりに読む。
//   ASAP7 には同期化専用のセルがないので、非同期リセット付きの FF を2段つなぐ。
//   keep で最適化から外す。量産では同期化専用セルに置き換える(仕様書 12章)。
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

  (* keep *) logic [DW-1:0] r_m;   // 1段目
  (* keep *) logic [DW-1:0] r_q;   // 2段目

  always_ff @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      r_m <= INIT;
      r_q <= INIT;
    end else begin
      r_m <= i_d;
      r_q <= r_m;
    end
  end

  assign o_q = r_q;

endmodule
