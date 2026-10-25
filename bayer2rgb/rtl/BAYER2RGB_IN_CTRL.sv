// ============================================================================
// BAYER2RGB_IN_CTRL : ステップの発行(COREの入口)
//   1フレーム = (H+1)ライン × (K+1)ステップ
//     ライン 0..H-1 : 列 0..K-1 は入力ビート、列 K は行末の掃き出し
//     ライン H      : 掃き出しライン(入力なし)。列 K は行末の掃き出し
//   クレジット: (出力FIFOの使用数 + 直近 CREDIT_WIN クロックの発行数) < 32 のときだけ発行する
//              後段は固定レイテンシで止まらないので、出力FIFOはあふれない
//   設定とソフトリセットを1段受け直して後段へ配る
// ============================================================================
module BAYER2RGB_IN_CTRL
  import BAYER2RGB_PKG::*;
(
  input  logic                clk
 ,input  logic                rst_n
 ,input  ctl_t                i_ctl       // フレームの設定 + start + sw_rst
 ,BAYER2RGB_VBD_IF.dst        pix         // RD_DMAからの画素
 ,input  logic [OFIFO_CW-1:0] i_fifo_cnt  // 出力FIFOの使用数
 ,output cfg_t                o_cfg       // 後段へ配る設定
 ,output logic                o_clr       // 後段へ配るクリア(ソフトリセット)
 ,output stp_t                o_stp
);

  cfg_t                   r_cfg;
  logic                   r_clr;
  logic                   r_start;
  logic                   r_act;      // ステップを発行中
  logic [HEIGHT_W-1:0]    r_line;
  logic [COL_W-1:0]       r_col;
  logic [HEIGHT_W-1:0]    r_h;        // 高さ
  logic [COL_W-1:0]       r_k;        // 1ラインのビート数
  logic [CREDIT_WIN-1:0]  r_hist;     // 直近の発行の履歴
  logic [CREDIT_CW-1:0]   r_infl;     // r_hist の1の数
  logic                   r_stp_vld;
  stp_t                   r_stp;

  logic                   s_frow;
  logic                   s_fcol;
  logic                   s_need;     // 入力ビートが必要なステップ
  logic                   s_credit;
  logic                   s_run;
  logic                   s_issue;

  assign s_frow   = (r_line==r_h);
  assign s_fcol   = (r_col==r_k);
  assign s_need   = (!s_frow)&&(!s_fcol);
  assign s_credit = ((OFIFO_CW+1)'(i_fifo_cnt)+(OFIFO_CW+1)'(r_infl))<(OFIFO_CW+1)'(OFIFO_DEPTH);
  assign s_run    = r_act&&(!r_clr)&&s_credit;
  assign pix.busy = !(s_run&&s_need);
  assign s_issue  = s_run&&((!s_need)||pix.vld);

  // 制御(リセットあり)
  always_ff @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      r_cfg     <= f_cfg_default();
      r_clr     <= 1'b0;
      r_start   <= 1'b0;
      r_act     <= 1'b0;
      r_line    <= '0;
      r_col     <= '0;
      r_h       <= HEIGHT_W'(MAX_HEIGHT);
      r_k       <= COL_W'(K_MAX);
      r_hist    <= '0;
      r_infl    <= '0;
      r_stp_vld <= 1'b0;
    end else begin
      r_cfg     <= i_ctl.cfg;
      r_clr     <= i_ctl.sw_rst;
      r_start   <= i_ctl.start;
      r_stp_vld <= s_issue;
      r_hist    <= {r_hist[CREDIT_WIN-2:0], s_issue};
      r_infl    <= r_infl+CREDIT_CW'(s_issue)-CREDIT_CW'(r_hist[CREDIT_WIN-1]);
      if( s_issue ) begin
        if( s_fcol ) begin
          r_col <= '0;
          if( s_frow ) begin
            r_act <= 1'b0;
          end else begin
            r_line <= r_line+HEIGHT_W'(1);
          end
        end else begin
          r_col <= r_col+COL_W'(1);
        end
      end
      if( r_start ) begin
        r_act  <= 1'b1;
        r_line <= '0;
        r_col  <= '0;
        r_h    <= f_height(r_cfg.height);
        r_k    <= f_kbeats(r_cfg.width);
      end
      if( r_clr ) begin
        r_act     <= 1'b0;
        r_hist    <= '0;
        r_infl    <= '0;
        r_stp_vld <= 1'b0;
      end
    end
  end

  // データ(リセットなし)
  always_ff @(posedge clk) begin
    if( s_issue ) begin
      r_stp.vld  <= 1'b0;   // vld は r_stp_vld を使う
      r_stp.fcol <= s_fcol;
      r_stp.frow <= s_frow;
      r_stp.line <= r_line;
      r_stp.col  <= r_col;
      r_stp.pix  <= pix.data;
    end
  end

  always_comb begin
    o_stp     = r_stp;
    o_stp.vld = r_stp_vld;
  end

  assign o_cfg = r_cfg;
  assign o_clr = r_clr;

`ifndef SYNTHESIS
  // 開始は前のフレームの発行が終わってから
  always @(posedge clk) begin
    if( rst_n&&r_start&&r_act ) begin
      $error("%m: ステップの発行中に開始を受けた");
    end
  end
`endif

endmodule
