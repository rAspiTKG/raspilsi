// ============================================================================
// BAYER2RGB_GAMMA : 折れ線ガンマ / 線形変換(14bit → 8bit)(レイテンシ3)
//   gamma_en=1: 37点の折れ線。折れ点の入力値は固定で
//                 0,16,32,48, 64,80,96,112, 128,160,192,224, ..., 8192,10240,12288,14336, 16384
//               (64以上は2のべき乗ごとに4区間)。折れ点の出力値 knot[0..36] は12bit(8.4固定小数点)
//               区間 s、区間内の位置 f(0..2047)として
//                 y   = knot[s] + ((knot[s+1] - knot[s]) × f + 1024) >>> 11
//                 out = min(255, (y + 8) >> 4)
//   gamma_en=0: out = min(255, (x + 32) >> 6)
//   1段目: 区間と位置  2段目: 折れ点の選択  3段目: 補間と丸め
// ============================================================================
module BAYER2RGB_GAMMA
  import BAYER2RGB_PKG::*;
(
  input  logic clk
 ,input  logic rst_n
 ,input  logic i_clr
 ,input  cfg_t i_cfg
 ,input  fc_t  i_fc
 ,output gm_t  o_gm
);

  localparam int NCH = PPC*3;   // 色チャネルの数

  typedef logic [IN_BITS-1:0]   pix_t;
  typedef logic [GM_SEG_W-1:0]  seg_t;
  typedef logic [GM_FRAC_W-1:0] frac_t;
  typedef logic [GM_KW-1:0]     knot_t;
  typedef logic [OUT_BITS-1:0]  out_t;

  // 1段目のレジスタ
  logic                r_vld1;
  logic                r_sof1;
  logic                r_eol1;
  logic                r_eof1;
  logic [HEIGHT_W-1:0] r_y1;
  logic [COL_W-1:0]    r_oc1;
  seg_t  [NCH-1:0]     r_seg1;
  frac_t [NCH-1:0]     r_frac1;
  out_t  [NCH-1:0]     r_lin1;        // 線形変換の結果
  // 2段目のレジスタ
  logic                r_vld2;
  logic                r_sof2;
  logic                r_eol2;
  logic                r_eof2;
  logic [HEIGHT_W-1:0] r_y2;
  logic [COL_W-1:0]    r_oc2;
  knot_t [NCH-1:0]     r_k0_2;
  logic signed [GM_KW:0] r_dk2 [NCH];  // knot[s+1] - knot[s]
  frac_t [NCH-1:0]     r_frac2;
  out_t  [NCH-1:0]     r_lin2;
  // 3段目のレジスタ
  logic                r_vld3;
  gm_t                 r_gm;

  pix_t  [NCH-1:0]     s_x;
  seg_t  [NCH-1:0]     s_seg;
  frac_t [NCH-1:0]     s_frac;
  out_t  [NCH-1:0]     s_lin;
  logic [IN_BITS-6:0]  s_lsum [NCH];   // (x+32)>>6 (9bit)
  knot_t [NCH-1:0]     s_k0;
  knot_t [NCH-1:0]     s_k1;
  logic signed [GM_KW+GM_FRAC_W+1:0] s_mul [NCH];  // dk × f
  logic signed [GM_KW+1:0]           s_yv  [NCH];  // 補間結果(12bit + 符号)
  logic [GM_KW+1:0]                  s_yr  [NCH];  // (y+8)>>4 の前
  out_t  [NCH-1:0]     s_out;

  // --------------------------------------------------------------------------
  // 1段目: 区間と位置
  // --------------------------------------------------------------------------
  always_comb begin
    for( int n=0; n<NCH; n++ ) begin
      s_x[n] = i_fc.rgb[n/3][n%3];
      // 64未満: 16ごとに4区間
      s_seg[n]  = seg_t'(s_x[n][5:4]);
      s_frac[n] = {s_x[n][3:0], 7'b000_0000};
      // 64以上: 最上位ビットの位置 p(6..13)ごとに4区間。上の p ほど優先する
      for( int p=6; p<IN_BITS; p++ ) begin
        if( s_x[n][p] ) begin
          s_seg[n]  = seg_t'(4+(4*(p-6)))+seg_t'(s_x[n][p-1-:2]);
          s_frac[n] = frac_t'((32'(s_x[n])&((32'd1<<(p-2))-32'd1))<<(13-p));
        end
      end
      // 線形変換
      s_lsum[n] = (IN_BITS-5)'(((IN_BITS+1)'(s_x[n])+(IN_BITS+1)'(32))>>6);
      if( s_lsum[n]>(IN_BITS-5)'(255) ) begin
        s_lin[n] = 8'd255;
      end else begin
        s_lin[n] = out_t'(s_lsum[n]);
      end
    end
  end

  // --------------------------------------------------------------------------
  // 2段目: 折れ点の選択
  //   knot[s] と knot[s+1] を選ぶ(s = 0..35)。
  //   添字が変数の配列読み出しは、合成ツールによっては cfg 全体のシフタになって
  //   大きくなるので、区間番号との比較と AND-OR で選ぶ
  // --------------------------------------------------------------------------
  always_comb begin
    for( int n=0; n<NCH; n++ ) begin
      s_k0[n] = '0;
      s_k1[n] = '0;
      for( int k=0; k<GM_KNOTS-1; k++ ) begin
        s_k0[n] = s_k0[n]|(i_cfg.gm_knot[k]&{GM_KW{r_seg1[n]==seg_t'(k)}});
        s_k1[n] = s_k1[n]|(i_cfg.gm_knot[k+1]&{GM_KW{r_seg1[n]==seg_t'(k)}});
      end
    end
  end

  // --------------------------------------------------------------------------
  // 3段目: 補間と丸め
  // --------------------------------------------------------------------------
  always_comb begin
    for( int n=0; n<NCH; n++ ) begin
      s_mul[n] = r_dk2[n]*$signed({1'b0, r_frac2[n]});
      s_yv[n]  = $signed({2'b00, r_k0_2[n]})+(GM_KW+2)'((s_mul[n]+(GM_KW+GM_FRAC_W+2)'(1024))>>>GM_FRAC_W);
      if( s_yv[n]<0 ) begin
        s_yr[n] = '0;
      end else begin
        s_yr[n] = (GM_KW+2)'(s_yv[n])+(GM_KW+2)'(8);
      end
      if( !i_cfg.gamma_en ) begin
        s_out[n] = r_lin2[n];
      end else if( (s_yr[n]>>4)>(GM_KW+2)'(255) ) begin
        s_out[n] = 8'd255;
      end else begin
        s_out[n] = out_t'(s_yr[n]>>4);
      end
    end
  end

  // --------------------------------------------------------------------------
  // 制御(リセットあり)
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      r_vld1 <= 1'b0;
      r_vld2 <= 1'b0;
      r_vld3 <= 1'b0;
    end else begin
      r_vld1 <= i_fc.vld&&!i_clr;
      r_vld2 <= r_vld1&&!i_clr;
      r_vld3 <= r_vld2&&!i_clr;
    end
  end

  // --------------------------------------------------------------------------
  // データ(リセットなし)
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if( i_fc.vld ) begin
      r_sof1  <= i_fc.sof;
      r_eol1  <= i_fc.eol;
      r_eof1  <= i_fc.eof;
      r_y1    <= i_fc.y;
      r_oc1   <= i_fc.oc;
      r_seg1  <= s_seg;
      r_frac1 <= s_frac;
      r_lin1  <= s_lin;
    end
    if( r_vld1 ) begin
      r_sof2  <= r_sof1;
      r_eol2  <= r_eol1;
      r_eof2  <= r_eof1;
      r_y2    <= r_y1;
      r_oc2   <= r_oc1;
      r_k0_2  <= s_k0;
      r_frac2 <= r_frac1;
      r_lin2  <= r_lin1;
      for( int n=0; n<NCH; n++ ) begin
        r_dk2[n] <= $signed({1'b0, s_k1[n]})-$signed({1'b0, s_k0[n]});
      end
    end
    if( r_vld2 ) begin
      r_gm.vld <= 1'b0;   // vld は r_vld3 を使う
      r_gm.sof <= r_sof2;
      r_gm.eol <= r_eol2;
      r_gm.eof <= r_eof2;
      r_gm.y   <= r_y2;
      r_gm.oc  <= r_oc2;
      for( int n=0; n<NCH; n++ ) begin
        r_gm.rgb[n/3][n%3] <= s_out[n];
      end
    end
  end

  always_comb begin
    o_gm     = r_gm;
    o_gm.vld = r_vld3;
  end

endmodule
