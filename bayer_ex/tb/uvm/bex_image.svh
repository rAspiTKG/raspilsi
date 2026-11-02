// ============================================================================
// bex_image : 入力の Bayer 画像(幅は4の倍数、高さは2の倍数)と、転送への分け方
//   転送の順: 2ラインずつ、左から右へ4画素ずつ。1転送 = 水平4画素 × 垂直2ライン
//   sof: 最初の転送、eol: 2ラインの最後の転送、eof: 最後の転送
// ============================================================================
class bex_image;
  int w;
  int h;
  int px[];   // px[y*w+x]

  // 画像の種類
  typedef enum int {
    IMG_RANDOM = 0,   // 0〜16383 の乱数
    IMG_RAMP   = 1,   // 位置で増える値
    IMG_LOW    = 2,   // 黒レベルの近く(0〜level+64)
    IMG_HIGH   = 3,   // 最大値の近く
    IMG_EXTREM = 4,   // 0 と 16383 の市松
    IMG_FLAT   = 5    // すべて level
  } kind_e;

  localparam int N_KIND = 6;

  function new( int ww, int hh );
    w  = ww;
    h  = hh;
    px = new[w*h];
  endfunction

  function void generate_img( int kind, int level=0 );
    int v;
    for( int y=0; y<h; y++ ) begin
      for( int x=0; x<w; x++ ) begin
        case( kind )
          IMG_RAMP : begin
            v = ((y*1000)+(x*37)+level)%16384;
          end
          IMG_LOW : begin
            v = $urandom_range(level+64, 0);
          end
          IMG_HIGH : begin
            v = $urandom_range(16383, 12000);
          end
          IMG_EXTREM : begin
            v = (((x+y)%2)==0) ? 0 : 16383;
          end
          IMG_FLAT : begin
            v = level;
          end
          default : begin
            v = $urandom_range(16383, 0);
          end
        endcase
        if( v>16383 ) begin
          v = 16383;
        end
        px[(y*w)+x] = v;
      end
    end
  endfunction

  function int n_xfer();
    return (w/4)*(h/2);
  endfunction

  // k 番目の転送
  function bayer4x2_t xfer( int k );
    bayer4x2_t t;
    int        nx;
    int        bx;
    int        by;
    nx    = w/4;
    bx    = k%nx;
    by    = k/nx;
    t.sof = (k==0);
    t.eol = (bx==(nx-1));
    t.eof = (k==(n_xfer()-1));
    for( int y=0; y<2; y++ ) begin
      for( int x=0; x<4; x++ ) begin
        t.pix[y][x] = 14'(px[((2*by+y)*w)+(4*bx)+x]);
      end
    end
    return t;
  endfunction
endclass
