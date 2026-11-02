// ============================================================================
// b2r_ref_model : BAYER2RGB のリファレンスモデル(ビット一致)
//   RTLと同じ整数演算で、入力画像と設定から出力のRGB888(R,G,B順)を作る。
//   アルゴリズムは仕様書と tools/b2r_model.py(Python版)と同じ。
// ============================================================================
class b2r_ref_model;
  b2r_frame_cfg cfg;
  int           w;
  int           h;
  int           q[];        // BLC・WBの後の値(w*h)
  byte unsigned out[];      // 出力(w*h*3)

  function new( b2r_frame_cfg cfg );
    this.cfg = cfg;
    w        = cfg.eff_w();
    h        = cfg.eff_h();
  endfunction

  // 色位置 0:R 1:Gr 2:Gb 3:B
  function int site( int x, int y );
    return (((y&1)^cfg.phase[1])*2)+((x&1)^cfg.phase[0]);
  endfunction

  // ミラー(reflect-101)
  function int mir( int v, int n );
    if( v<0 ) begin
      return -v;
    end else if( v>=n ) begin
      return (2*n)-2-v;
    end
    return v;
  endfunction

  function int qv( int x, int y );
    return q[(mir(y, h)*w)+mir(x, w)];
  endfunction

  function int imax( int a, int b );
    return (a>b) ? a : b;
  endfunction

  function int iabs( int a );
    return (a<0) ? -a : a;
  endfunction

  function int clip14( int a );
    if( a<0 ) begin
      return 0;
    end else if( a>16383 ) begin
      return 16383;
    end
    return a;
  endfunction

  // 14bit → 8bit(ガンマまたは線形)
  function int gamma( int x );
    int seg;
    int frac;
    int p;
    int k0;
    int k1;
    int y;
    int r;
    if( !cfg.gamma_en ) begin
      r = (x+32)>>6;
      return (r>255) ? 255 : r;
    end
    if( x<64 ) begin
      seg  = x>>4;
      frac = (x&15)<<7;
    end else begin
      p = 6;
      for( int b=6; b<14; b++ ) begin
        if( ((x>>b)&1)!=0 ) begin
          p = b;
        end
      end
      seg  = 4+(4*(p-6))+((x>>(p-2))&3);
      frac = (x&((1<<(p-2))-1))<<(13-p);
    end
    k0 = cfg.gm_knot[seg];
    k1 = cfg.gm_knot[seg+1];
    y  = k0+((((k1-k0)*frac)+1024)>>>11);
    if( y<0 ) begin
      y = 0;
    end
    r = (y+8)>>4;
    return (r>255) ? 255 : r;
  endfunction

  // 出力画像を計算する
  function void compute( b2r_image img );
    int p;
    int s;
    int g;
    longint t;
    int c;
    int n;
    int ss;
    int ww;
    int e;
    int nw;
    int ne;
    int sw;
    int se;
    int g4;
    int d4;
    int h2;
    int v2;
    int erb;
    int eg;
    int rgb[3];
    int edg;
    int yl;
    int ex;
    int k;
    int bw;
    int bar;
    out = new[w*h*3];
    // ---- テストパターン(入力は使わない)
    if( cfg.tpg_en ) begin
      bw = w>>3;
      for( int y=0; y<h; y++ ) begin
        for( int x=0; x<w; x++ ) begin
          case( cfg.tpg_sel )
            2'd0 : begin
              bar = 0;
              for( int j=1; j<8; j++ ) begin
                if( x>=(j*bw) ) begin
                  bar = j;
                end
              end
              rgb[0] = ((bar&2)!=0) ? 0 : 255;
              rgb[1] = ((bar&4)!=0) ? 0 : 255;
              rgb[2] = ((bar&1)!=0) ? 0 : 255;
            end
            2'd1 : begin
              rgb[0] = (x>>4)&255;
              rgb[1] = rgb[0];
              rgb[2] = rgb[0];
            end
            2'd2 : begin
              rgb[0] = ((((x>>6)^(y>>6))&1)!=0) ? 255 : 0;
              rgb[1] = rgb[0];
              rgb[2] = rgb[0];
            end
            default : begin
              rgb[0] = cfg.tpg_color[23:16];
              rgb[1] = cfg.tpg_color[15:8];
              rgb[2] = cfg.tpg_color[7:0];
            end
          endcase
          for( int ch=0; ch<3; ch++ ) begin
            out[(((y*w)+x)*3)+ch] = 8'(rgb[ch]);
          end
        end
      end
      return;
    end
    // ---- BLC と WB
    q = new[w*h];
    for( int y=0; y<h; y++ ) begin
      for( int x=0; x<w; x++ ) begin
        p = img.get(x, y);
        s = site(x, y);
        if( cfg.blc_en ) begin
          p = (p>cfg.blc[s]) ? (p-cfg.blc[s]) : 0;
        end
        g = cfg.wb_en ? cfg.wbg[s] : 4096;
        t = ((longint'(p)*g)+2048)>>12;
        q[(y*w)+x] = (t>16383) ? 16383 : int'(t);
      end
    end
    // ---- デモザイク・偽色抑制・ガンマ
    for( int y=0; y<h; y++ ) begin
      for( int x=0; x<w; x++ ) begin
        c   = qv(x, y);
        n   = qv(x, y-1);
        ss  = qv(x, y+1);
        ww  = qv(x-1, y);
        e   = qv(x+1, y);
        nw  = qv(x-1, y-1);
        ne  = qv(x+1, y-1);
        sw  = qv(x-1, y+1);
        se  = qv(x+1, y+1);
        g4  = (n+ss+ww+e+2)>>2;
        d4  = (nw+ne+sw+se+2)>>2;
        h2  = (ww+e+1)>>1;
        v2  = (n+ss+1)>>1;
        erb = imax(iabs(n-ss), iabs(ww-e));
        eg  = imax(iabs(nw-se), iabs(ne-sw));
        if( cfg.bypass ) begin
          rgb[0] = c;
          rgb[1] = c;
          rgb[2] = c;
          edg    = 0;
        end else begin
          case( site(x, y) )
            0 : begin
              rgb[0] = c;
              rgb[1] = g4;
              rgb[2] = d4;
              edg    = erb;
            end
            1 : begin
              rgb[0] = h2;
              rgb[1] = c;
              rgb[2] = v2;
              edg    = eg;
            end
            2 : begin
              rgb[0] = v2;
              rgb[1] = c;
              rgb[2] = h2;
              edg    = eg;
            end
            default : begin
              rgb[0] = d4;
              rgb[1] = g4;
              rgb[2] = c;
              edg    = erb;
            end
          endcase
        end
        // 偽色抑制
        yl = (rgb[0]+(2*rgb[1])+rgb[2]+2)>>2;
        ex = (edg>cfg.fcs_th) ? (edg-cfg.fcs_th) : 0;
        t  = (longint'(ex)*cfg.fcs_gain)>>6;
        if( !cfg.fcs_en||cfg.bypass ) begin
          k = 256;
        end else if( t>=256 ) begin
          k = 0;
        end else begin
          k = 256-int'(t);
        end
        for( int ch=0; ch<3; ch++ ) begin
          rgb[ch] = clip14(yl+((((rgb[ch]-yl)*k)+128)>>>8));
          out[(((y*w)+x)*3)+ch] = 8'(gamma(rgb[ch]));
        end
      end
    end
  endfunction

endclass
