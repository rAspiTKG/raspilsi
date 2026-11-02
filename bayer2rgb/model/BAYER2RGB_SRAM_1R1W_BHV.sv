// ============================================================================
// BAYER2RGB_SRAM_1R1W_BHV : 1R1W SRAMの振る舞いモデル(シミュレーション専用)
//   - 書き込み: i_wen=1 のクロックで mem[i_waddr] <= i_wdata
//   - 読み出し: i_ren=1 のクロックで o_rdata <= mem[i_raddr](レイテンシ1)
//               i_ren=0 のとき o_rdata は前の値を保持する
//   - 同一アドレスの同時読み書き、範囲外アドレスは X を出してエラーを報告する
//   - 中身の初期値は不定(4値シミュレータでは X)
// ============================================================================
module BAYER2RGB_SRAM_1R1W_BHV #(
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

  logic [DW-1:0] r_mem [DEPTH];
  logic          s_rw_hit;    // 同一アドレスの同時読み書き
  logic          s_rd_over;   // 読み出しアドレスが範囲外
  logic          s_wr_over;   // 書き込みアドレスが範囲外

  assign s_rw_hit  = i_ren&&i_wen&&(i_raddr==i_waddr);
  assign s_rd_over = i_ren&&({1'b0, i_raddr}>=(AW+1)'(DEPTH));
  assign s_wr_over = i_wen&&({1'b0, i_waddr}>=(AW+1)'(DEPTH));

  always_ff @(posedge clk) begin
    if( i_wen&&!s_wr_over ) begin
      r_mem[i_waddr] <= i_wdata;
    end
    if( i_ren ) begin
      if( s_rw_hit||s_rd_over ) begin
        o_rdata <= 'x;
      end else begin
        o_rdata <= r_mem[i_raddr];
      end
    end
  end

  // 使い方の誤りを報告する
  always @(posedge clk) begin
    if( s_rw_hit ) begin
      $error("%m: 同一アドレス(%0d)の同時読み書き", i_raddr);
    end
    if( s_rd_over ) begin
      $error("%m: 読み出しアドレスが範囲外(%0d)", i_raddr);
    end
    if( s_wr_over ) begin
      $error("%m: 書き込みアドレスが範囲外(%0d)", i_waddr);
    end
  end

endmodule
