// ============================================================================
// BAYER2RGB_SYNC2_BHV : 2段同期化セルの振る舞いモデル(シミュレーション専用)
//   量産時はスタンダードセルライブラリの同期化専用セルに置き換える。
//   +define+BAYER2RGB_CDC_RANDOM_DELAY を付けると、入力が変化したときに
//   1段目の取り込みをランダムに1クロック遅らせる(メタステーブル後の
//   収束先が旧値になる場合を模擬し、CDC回路の検証に使う)。
// ============================================================================
module BAYER2RGB_SYNC2_BHV #(
  parameter int            DW   = 1
 ,parameter logic [DW-1:0] INIT = '0
) (
  input  logic          clk
 ,input  logic          rst_n
 ,input  logic [DW-1:0] i_d
 ,output logic [DW-1:0] o_q
);

  logic [DW-1:0] r_m;   // 1段目
  logic [DW-1:0] r_q;   // 2段目

  assign o_q = r_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      r_m <= INIT;
      r_q <= INIT;
    end else begin
`ifdef BAYER2RGB_CDC_RANDOM_DELAY
      for( int i=0; i<DW; i++ ) begin
        if( (i_d[i]!=r_m[i])&&($urandom_range(1,0)==0) ) begin
          r_m[i] <= r_m[i];
        end else begin
          r_m[i] <= i_d[i];
        end
      end
`else
      r_m <= i_d;
`endif
      r_q <= r_m;
    end
  end

endmodule
