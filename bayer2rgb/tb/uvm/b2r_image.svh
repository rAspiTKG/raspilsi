// ============================================================================
// b2r_image : 合成したBayer画像(メモリに置く16bit値。下位14bitが画素)
//   上位2bitには乱数を入れ、DUTが下位14bitだけを使うことを確かめる
//   kind 0: 一様乱数            1: なめらかなグラデーション
//        2: 色付きの矩形(エッジで偽色が出る)  3: 細かい縞・市松(高周波)
//        4: 0 / 16383 / 乱数 の混在(クリップ)  5: 暗部(黒レベル付近)
//        6: 明部(WBでクリップ)
// ============================================================================
class b2r_image;
  int        w;
  int        h;
  bit [15:0] px[];

  function new( int w, int h );
    this.w = w;
    this.h = h;
    px     = new[w*h];
  endfunction

  function bit [13:0] get( int x, int y );
    return px[(y*w)+x][13:0];
  endfunction

  // 画像を作る(phase は色付き矩形を正しい色位置に置くために使う)
  function void generate_img( int kind, bit [1:0] phase );
    int bs;
    int bx;
    int by;
    int ncol;
    int site;
    bit [13:0] v;
    bit [13:0] col[64][3];
    bs   = 8*$urandom_range(4, 1);
    ncol = 64;
    for( int i=0; i<ncol; i++ ) begin
      for( int c=0; c<3; c++ ) begin
        col[i][c] = 14'($urandom_range(16383, 0));
      end
    end
    for( int y=0; y<h; y++ ) begin
      for( int x=0; x<w; x++ ) begin
        case( kind )
          1 : begin
            v = 14'(((x*12000)/w)+((y*4000)/h));
          end
          2 : begin
            bx   = x/bs;
            by   = y/bs;
            site = (((y&1)^phase[1])*2)+((x&1)^phase[0]);
            case( site )
              0 : begin
                v = col[((by*7)+(bx*3))%ncol][0];
              end
              3 : begin
                v = col[((by*7)+(bx*3))%ncol][2];
              end
              default : begin
                v = col[((by*7)+(bx*3))%ncol][1];
              end
            endcase
          end
          3 : begin
            case( (x/64)%3 )
              0 : begin
                v = ((x&1)!=0) ? 14'd15000 : 14'd1000;
              end
              1 : begin
                v = (((x^y)&1)!=0) ? 14'd14000 : 14'd500;
              end
              default : begin
                v = ((((x>>1)^(y>>1))&1)!=0) ? 14'd16000 : 14'd2000;
              end
            endcase
          end
          4 : begin
            case( $urandom_range(2, 0) )
              0 : begin
                v = 14'd0;
              end
              1 : begin
                v = 14'd16383;
              end
              default : begin
                v = 14'($urandom_range(16383, 0));
              end
            endcase
          end
          5 : begin
            v = 14'($urandom_range(600, 0));
          end
          6 : begin
            v = 14'($urandom_range(16383, 12000));
          end
          default : begin
            v = 14'($urandom_range(16383, 0));
          end
        endcase
        px[(y*w)+x] = {2'($urandom_range(3, 0)), v};
      end
    end
  endfunction

endclass
