// ============================================================================
// BAYER2RGB_DMSC : バイリニア補間によるデモザイクとエッジ量(レイテンシ2)
//   窓の中心 c、上下左右 N/S/W/E、斜め NW/NE/SW/SE として
//     G4 = (N+S+W+E+2)>>2   D4 = (NW+NE+SW+SE+2)>>2
//     H2 = (W+E+1)>>1       V2 = (N+S+1)>>1
//   R の位置 : (R,G,B) = (c, G4, D4)    B の位置 : (D4, G4, c)
//   Gr の位置: (H2, c, V2)              Gb の位置: (V2, c, H2)
//   エッジ量(同じ色どうしの差): R/B の位置 max(|N-S|,|W-E|)、G の位置 max(|NW-SE|,|NE-SW|)
//   バイパス時: (R,G,B) = (c, c, c)、エッジ量 0
//   1段目: 平均と差  2段目: 色位置による選択
// ============================================================================
module BAYER2RGB_DMSC
  import BAYER2RGB_PKG::*;
(
  input  logic clk
 ,input  logic rst_n
 ,input  logic i_clr
 ,input  cfg_t i_cfg
 ,input  win_t i_win
 ,output dm_t  o_dm
);

  typedef logic [IN_BITS-1:0] pix_t;

  // 差の絶対値
  function automatic pix_t f_absdiff( input pix_t a, input pix_t b );
    begin
      if( a>b ) begin
        f_absdiff = a-b;
      end else begin
        f_absdiff = b-a;
      end
    end
  endfunction

  // 大きい方
  function automatic pix_t f_max( input pix_t a, input pix_t b );
    begin
      if( a>b ) begin
        f_max = a;
      end else begin
        f_max = b;
      end
    end
  endfunction

  // 4画素の平均(四捨五入)
  function automatic pix_t f_avg4( input pix_t a, input pix_t b, input pix_t c, input pix_t d );
    logic [IN_BITS+1:0] t;
    begin
      t = (IN_BITS+2)'(a)+(IN_BITS+2)'(b)+(IN_BITS+2)'(c)+(IN_BITS+2)'(d)+(IN_BITS+2)'(2);
      f_avg4 = pix_t'(t>>2);
    end
  endfunction

  // 2画素の平均(四捨五入)
  function automatic pix_t f_avg2( input pix_t a, input pix_t b );
    logic [IN_BITS:0] t;
    begin
      t = (IN_BITS+1)'(a)+(IN_BITS+1)'(b)+(IN_BITS+1)'(1);
      f_avg2 = pix_t'(t>>1);
    end
  endfunction

  // 1段目のレジスタ
  logic                r_vld1;
  logic                r_sof1;
  logic                r_eol1;
  logic                r_eof1;
  logic [HEIGHT_W-1:0] r_y1;
  logic [COL_W-1:0]    r_oc1;
  logic [PPC-1:0][1:0] r_site1;
  pix_t [PPC-1:0]      r_c1;
  pix_t [PPC-1:0]      r_g4;
  pix_t [PPC-1:0]      r_d4;
  pix_t [PPC-1:0]      r_h2;
  pix_t [PPC-1:0]      r_v2;
  pix_t [PPC-1:0]      r_erb;         // R/B の位置のエッジ量
  pix_t [PPC-1:0]      r_eg;          // G の位置のエッジ量
  // 2段目のレジスタ
  logic                r_vld2;
  dm_t                 r_dm;

  // 窓から取り出した画素
  pix_t [PPC-1:0]      s_c;
  pix_t [PPC-1:0]      s_n;
  pix_t [PPC-1:0]      s_s;
  pix_t [PPC-1:0]      s_w;
  pix_t [PPC-1:0]      s_e;
  pix_t [PPC-1:0]      s_nw;
  pix_t [PPC-1:0]      s_ne;
  pix_t [PPC-1:0]      s_sw;
  pix_t [PPC-1:0]      s_se;
  logic [PPC-1:0][1:0] s_site;
  logic [PPC-1:0][2:0][IN_BITS-1:0] s_rgb;
  pix_t [PPC-1:0]      s_edg;

  // --------------------------------------------------------------------------
  // 1段目: 平均と差
  // --------------------------------------------------------------------------
  always_comb begin
    for( int i=0; i<PPC; i++ ) begin
      s_c[i]    = i_win.win[1][i+1];
      s_n[i]    = i_win.win[0][i+1];
      s_s[i]    = i_win.win[2][i+1];
      s_w[i]    = i_win.win[1][i];
      s_e[i]    = i_win.win[1][i+2];
      s_nw[i]   = i_win.win[0][i];
      s_ne[i]   = i_win.win[0][i+2];
      s_sw[i]   = i_win.win[2][i];
      s_se[i]   = i_win.win[2][i+2];
      s_site[i] = f_site(i_cfg.phase, i_win.y[0], f_xpar(i_win.oc[0], 1'(i)));
    end
  end

  // --------------------------------------------------------------------------
  // 2段目: 色位置による選択
  // --------------------------------------------------------------------------
  always_comb begin
    for( int i=0; i<PPC; i++ ) begin
      if( i_cfg.bypass ) begin
        s_rgb[i][0] = r_c1[i];
        s_rgb[i][1] = r_c1[i];
        s_rgb[i][2] = r_c1[i];
        s_edg[i]    = '0;
      end else begin
        case( r_site1[i] )
          2'd0 : begin
            s_rgb[i][0] = r_c1[i];
            s_rgb[i][1] = r_g4[i];
            s_rgb[i][2] = r_d4[i];
            s_edg[i]    = r_erb[i];
          end
          2'd1 : begin
            s_rgb[i][0] = r_h2[i];
            s_rgb[i][1] = r_c1[i];
            s_rgb[i][2] = r_v2[i];
            s_edg[i]    = r_eg[i];
          end
          2'd2 : begin
            s_rgb[i][0] = r_v2[i];
            s_rgb[i][1] = r_c1[i];
            s_rgb[i][2] = r_h2[i];
            s_edg[i]    = r_eg[i];
          end
          default : begin
            s_rgb[i][0] = r_d4[i];
            s_rgb[i][1] = r_g4[i];
            s_rgb[i][2] = r_c1[i];
            s_edg[i]    = r_erb[i];
          end
        endcase
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
    end else begin
      r_vld1 <= i_win.vld&&!i_clr;
      r_vld2 <= r_vld1&&!i_clr;
    end
  end

  // --------------------------------------------------------------------------
  // データ(リセットなし)
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if( i_win.vld ) begin
      r_sof1  <= i_win.sof;
      r_eol1  <= i_win.eol;
      r_eof1  <= i_win.eof;
      r_y1    <= i_win.y;
      r_oc1   <= i_win.oc;
      r_site1 <= s_site;
      for( int i=0; i<PPC; i++ ) begin
        r_c1[i]  <= s_c[i];
        r_g4[i]  <= f_avg4(s_n[i], s_s[i], s_w[i], s_e[i]);
        r_d4[i]  <= f_avg4(s_nw[i], s_ne[i], s_sw[i], s_se[i]);
        r_h2[i]  <= f_avg2(s_w[i], s_e[i]);
        r_v2[i]  <= f_avg2(s_n[i], s_s[i]);
        r_erb[i] <= f_max(f_absdiff(s_n[i], s_s[i]), f_absdiff(s_w[i], s_e[i]));
        r_eg[i]  <= f_max(f_absdiff(s_nw[i], s_se[i]), f_absdiff(s_ne[i], s_sw[i]));
      end
    end
    if( r_vld1 ) begin
      r_dm.vld <= 1'b0;   // vld は r_vld2 を使う
      r_dm.sof <= r_sof1;
      r_dm.eol <= r_eol1;
      r_dm.eof <= r_eof1;
      r_dm.y   <= r_y1;
      r_dm.oc  <= r_oc1;
      r_dm.rgb <= s_rgb;
      r_dm.edg <= s_edg;
    end
  end

  always_comb begin
    o_dm     = r_dm;
    o_dm.vld = r_vld2;
  end

endmodule
