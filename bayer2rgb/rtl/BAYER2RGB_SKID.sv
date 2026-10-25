// ============================================================================
// BAYER2RGB_SKID : 2段スキッドバッファ(vld/busy/data)
//   出力の o_vld / o_data と入力側への o_busy をすべてFFから出す。
//   出力が止まっていても1ビート受けられるので、連続転送で1ビート/クロック。
// ============================================================================
module BAYER2RGB_SKID #(
  parameter int DW = 8
) (
  input  logic          clk
 ,input  logic          rst_n
 // 入力側
 ,input  logic          i_vld
 ,output logic          o_busy
 ,input  logic [DW-1:0] i_data
 // 出力側
 ,output logic          o_vld
 ,input  logic          i_busy
 ,output logic [DW-1:0] o_data
);

  logic          r_vld;       // 出力段が有効
  logic [DW-1:0] r_data;
  logic          r_skd_vld;   // スキッド段が有効
  logic [DW-1:0] r_skd_data;
  logic          s_out_free;  // 出力段を更新できる

  assign s_out_free = (!r_vld)||(!i_busy);
  assign o_vld      = r_vld;
  assign o_data     = r_data;
  assign o_busy     = r_skd_vld;

  // 制御(リセットあり)
  always_ff @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      r_vld     <= 1'b0;
      r_skd_vld <= 1'b0;
    end else begin
      if( s_out_free ) begin
        r_vld     <= r_skd_vld||i_vld;
        r_skd_vld <= 1'b0;
      end else if( i_vld&&!r_skd_vld ) begin
        r_skd_vld <= 1'b1;
      end
    end
  end

  // データ(リセットなし)
  always_ff @(posedge clk) begin
    if( s_out_free ) begin
      if( r_skd_vld ) begin
        r_data <= r_skd_data;
      end else if( i_vld ) begin
        r_data <= i_data;
      end
    end else if( i_vld&&!r_skd_vld ) begin
      r_skd_data <= i_data;
    end
  end

endmodule
