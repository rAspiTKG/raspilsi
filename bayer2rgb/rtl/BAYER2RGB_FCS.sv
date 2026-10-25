// ============================================================================
// BAYER2RGB_FCS : エッジ部の彩度抑制(偽色対策)(レイテンシ3)
//   Y  = (R + 2G + B + 2) >> 2
//   ex = max(E - th, 0)                      E: エッジ量、th: しきい値
//   ks = min(256, (ex × gain) >> 6)
//   k  = 256 - ks                            (fcs_en=0 またはバイパス時は k = 256)
//   X' = clip(Y + ((X - Y) × k + 128) >>> 8, 0, 16383)    X = R, G, B
//   k = 256 のとき X' = X になる
//   1段目: Y と ex  2段目: k と X-Y  3段目: 補間とクリップ
// ============================================================================
module BAYER2RGB_FCS
  import BAYER2RGB_PKG::*;
(
  input  logic clk
 ,input  logic rst_n
 ,input  logic i_clr
 ,input  cfg_t i_cfg
 ,input  dm_t  i_dm
 ,output fc_t  o_fc
);

  typedef logic [IN_BITS-1:0] pix_t;

  // 1段目のレジスタ
  logic                r_vld1;
  logic                r_sof1;
  logic                r_eol1;
  logic                r_eof1;
  logic [HEIGHT_W-1:0] r_y1;
  logic [COL_W-1:0]    r_oc1;
  logic [PPC-1:0][2:0][IN_BITS-1:0] r_rgb1;
  pix_t [PPC-1:0]      r_lum1;        // Y
  pix_t [PPC-1:0]      r_ex1;         // しきい値を超えた分
  // 2段目のレジスタ
  logic                r_vld2;
  logic                r_sof2;
  logic                r_eol2;
  logic                r_eof2;
  logic [HEIGHT_W-1:0] r_y2;
  logic [COL_W-1:0]    r_oc2;
  pix_t [PPC-1:0]      r_lum2;
  logic [PPC-1:0][8:0] r_k2;          // 0..256
  logic signed [IN_BITS:0] r_d2 [PPC][3]; // X - Y
  // 3段目のレジスタ
  logic                r_vld3;
  fc_t                 r_fc;

  logic                s_en;
  pix_t [PPC-1:0]      s_lum;
  pix_t [PPC-1:0]      s_ex;
  logic [PPC-1:0][IN_BITS+FCS_GAIN_W-1:0] s_t; // ex × gain
  logic [PPC-1:0][8:0] s_k;
  logic signed [IN_BITS:0]    s_d   [PPC][3];
  logic signed [IN_BITS+10:0] s_mul [PPC][3];  // (X-Y) × k
  logic signed [IN_BITS+2:0]  s_out [PPC][3];  // Y + 補正
  logic [PPC-1:0][2:0][IN_BITS-1:0] s_rgb;

  assign s_en = i_cfg.fcs_en&&!i_cfg.bypass;

  // --------------------------------------------------------------------------
  // 1段目: Y と ex
  // --------------------------------------------------------------------------
  always_comb begin
    for( int i=0; i<PPC; i++ ) begin
      s_lum[i] = pix_t'(((IN_BITS+2)'(i_dm.rgb[i][0])+((IN_BITS+2)'(i_dm.rgb[i][1])<<1)+(IN_BITS+2)'(i_dm.rgb[i][2])+(IN_BITS+2)'(2))>>2);
      if( i_dm.edg[i]>i_cfg.fcs_th ) begin
        s_ex[i] = i_dm.edg[i]-i_cfg.fcs_th;
      end else begin
        s_ex[i] = '0;
      end
    end
  end

  // --------------------------------------------------------------------------
  // 2段目: k と X-Y
  // --------------------------------------------------------------------------
  always_comb begin
    for( int i=0; i<PPC; i++ ) begin
      s_t[i] = (IN_BITS+FCS_GAIN_W)'(r_ex1[i])*(IN_BITS+FCS_GAIN_W)'(i_cfg.fcs_gain);
      if( !s_en ) begin
        s_k[i] = 9'd256;
      end else if( (s_t[i]>>6)>=(IN_BITS+FCS_GAIN_W)'(256) ) begin
        s_k[i] = 9'd0;
      end else begin
        s_k[i] = 9'd256-9'(s_t[i]>>6);
      end
      for( int c=0; c<3; c++ ) begin
        s_d[i][c] = $signed({1'b0, r_rgb1[i][c]})-$signed({1'b0, r_lum1[i]});
      end
    end
  end

  // --------------------------------------------------------------------------
  // 3段目: 補間とクリップ
  // --------------------------------------------------------------------------
  always_comb begin
    for( int i=0; i<PPC; i++ ) begin
      for( int c=0; c<3; c++ ) begin
        s_mul[i][c] = r_d2[i][c]*$signed({1'b0, r_k2[i]});
        s_out[i][c] = $signed({3'b000, r_lum2[i]})+(IN_BITS+3)'((s_mul[i][c]+(IN_BITS+11)'(128))>>>8);
        if( s_out[i][c]<0 ) begin
          s_rgb[i][c] = '0;
        end else if( s_out[i][c]>(IN_BITS+3)'(PIX_MAX) ) begin
          s_rgb[i][c] = pix_t'(PIX_MAX);
        end else begin
          s_rgb[i][c] = pix_t'(s_out[i][c]);
        end
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
      r_vld1 <= i_dm.vld&&!i_clr;
      r_vld2 <= r_vld1&&!i_clr;
      r_vld3 <= r_vld2&&!i_clr;
    end
  end

  // --------------------------------------------------------------------------
  // データ(リセットなし)
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if( i_dm.vld ) begin
      r_sof1 <= i_dm.sof;
      r_eol1 <= i_dm.eol;
      r_eof1 <= i_dm.eof;
      r_y1   <= i_dm.y;
      r_oc1  <= i_dm.oc;
      r_rgb1 <= i_dm.rgb;
      r_lum1 <= s_lum;
      r_ex1  <= s_ex;
    end
    if( r_vld1 ) begin
      r_sof2 <= r_sof1;
      r_eol2 <= r_eol1;
      r_eof2 <= r_eof1;
      r_y2   <= r_y1;
      r_oc2  <= r_oc1;
      r_lum2 <= r_lum1;
      r_k2   <= s_k;
      for( int i=0; i<PPC; i++ ) begin
        for( int c=0; c<3; c++ ) begin
          r_d2[i][c] <= s_d[i][c];
        end
      end
    end
    if( r_vld2 ) begin
      r_fc.vld <= 1'b0;   // vld は r_vld3 を使う
      r_fc.sof <= r_sof2;
      r_fc.eol <= r_eol2;
      r_fc.eof <= r_eof2;
      r_fc.y   <= r_y2;
      r_fc.oc  <= r_oc2;
      r_fc.rgb <= s_rgb;
    end
  end

  always_comb begin
    o_fc     = r_fc;
    o_fc.vld = r_vld3;
  end

endmodule
