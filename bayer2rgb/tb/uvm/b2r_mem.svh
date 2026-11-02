// ============================================================================
// b2r_mem : AXIスレーブが使う疎なメモリ(4KBページ単位)
//   書いていないバイトはアドレスから決まる値を返す(読み出しの再現性のため)
// ============================================================================
class b2r_mem_page;
  bit [7:0] b[4096];
endclass

class b2r_mem;
  b2r_mem_page pages[bit [27:0]];

  function bit [7:0] fill_byte( bit [39:0] a );
    bit [31:0] v;
    v = a[31:0]*32'h9E37_79B1;
    return v[31:24]^v[7:0]^8'(a[39:32]);
  endfunction

  function b2r_mem_page get_page( bit [39:0] a, bit create );
    bit [27:0] pn;
    b2r_mem_page pg;
    pn = a[39:12];
    if( pages.exists(pn) ) begin
      return pages[pn];
    end
    if( !create ) begin
      return null;
    end
    pg = new();
    for( int i=0; i<4096; i++ ) begin
      pg.b[i] = fill_byte({pn, 12'(i)});
    end
    pages[pn] = pg;
    return pg;
  endfunction

  function void write_byte( bit [39:0] a, bit [7:0] d );
    b2r_mem_page pg;
    pg = get_page(a, 1'b1);
    pg.b[a[11:0]] = d;
  endfunction

  function bit [7:0] read_byte( bit [39:0] a );
    b2r_mem_page pg;
    pg = get_page(a, 1'b0);
    if( pg==null ) begin
      return fill_byte(a);
    end
    return pg.b[a[11:0]];
  endfunction

  // 16バイトのビート(a は16バイト境界)
  function void write_beat( bit [39:0] a, bit [127:0] d, bit [15:0] strb );
    for( int i=0; i<16; i++ ) begin
      if( strb[i] ) begin
        write_byte(a+40'(i), d[(8*i)+:8]);
      end
    end
  endfunction

  function bit [127:0] read_beat( bit [39:0] a );
    bit [127:0] d;
    for( int i=0; i<16; i++ ) begin
      d[(8*i)+:8] = read_byte(a+40'(i));
    end
    return d;
  endfunction

  // Bayer画像を置く(1画素 = 16bitリトルエンディアン)
  function void load_image( bit [39:0] base, int stride, b2r_image img );
    bit [39:0] a;
    for( int y=0; y<img.h; y++ ) begin
      a = base+(40'(stride)*40'(y));
      for( int x=0; x<img.w; x++ ) begin
        write_byte(a+40'(2*x), img.px[(y*img.w)+x][7:0]);
        write_byte(a+40'((2*x)+1), img.px[(y*img.w)+x][15:8]);
      end
    end
  endfunction

endclass
