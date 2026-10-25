// ============================================================================
// b2r_frame_cfg : 1フレーム分の設定(レジスタに書く値そのもの)
//   乱数化は手続きで行う(rand_* 関数)。シードで再現できる。
// ============================================================================
class b2r_frame_cfg extends uvm_object;
  `uvm_object_utils(b2r_frame_cfg)

  // レジスタに書く値(範囲外の値もそのまま書く。実効値は eff_w / eff_h)
  bit [11:0] width;
  bit [11:0] height;
  bit [1:0]  phase;
  bit        blc_en;
  bit        wb_en;
  bit        fcs_en;
  bit        gamma_en;
  bit        bypass;
  bit        tpg_en;
  bit [1:0]  tpg_sel;
  bit [23:0] tpg_color;
  bit [13:0] blc[4];        // [0]R [1]Gr [2]Gb [3]B
  bit [15:0] wbg[4];        // U4.12
  bit [13:0] fcs_th;
  bit [7:0]  fcs_gain;
  bit [11:0] gm_knot[37];
  bit [39:0] src_addr;
  bit [23:0] src_stride;
  bit [39:0] dst_addr;
  bit [23:0] dst_stride;
  bit [3:0]  arcache;
  bit [3:0]  awcache;
  bit [2:0]  arprot;
  bit [2:0]  awprot;
  bit [3:0]  arqos;
  bit [3:0]  awqos;
  // 入力画像の種類(b2r_image の kind)
  int        img_kind;

  function new( string name="b2r_frame_cfg" );
    super.new(name);
    set_default();
  endfunction

  // --------------------------------------------------------------------------
  // リセット値と同じ設定
  // --------------------------------------------------------------------------
  function void set_default();
    width      = 12'd3840;
    height     = 12'd2160;
    phase      = 2'd0;
    blc_en     = 1'b1;
    wb_en      = 1'b1;
    fcs_en     = 1'b1;
    gamma_en   = 1'b1;
    bypass     = 1'b0;
    tpg_en     = 1'b0;
    tpg_sel    = 2'd0;
    tpg_color  = 24'h000000;
    for( int i=0; i<4; i++ ) begin
      blc[i] = 14'd0;
      wbg[i] = 16'h1000;
    end
    fcs_th     = 14'd256;
    fcs_gain   = 8'd16;
    for( int i=0; i<37; i++ ) begin
      gm_knot[i] = BAYER2RGB_PKG::GM_SRGB[i];
    end
    src_addr   = 40'h0;
    src_stride = 24'h0;
    dst_addr   = 40'h0;
    dst_stride = 24'h0;
    arcache    = 4'b0011;
    awcache    = 4'b0011;
    arprot     = 3'd0;
    awprot     = 3'd0;
    arqos      = 4'd0;
    awqos      = 4'd0;
    img_kind   = 0;
  endfunction

  // --------------------------------------------------------------------------
  // 実効サイズ(RTLの f_width / f_height と同じ)
  // --------------------------------------------------------------------------
  function int eff_w();
    int t;
    t = width;
    if( t<16 ) begin
      t = 16;
    end else if( t>3840 ) begin
      t = 3840;
    end
    return t&~7;
  endfunction

  function int eff_h();
    int t;
    t = height;
    if( t<16 ) begin
      t = 16;
    end else if( t>2160 ) begin
      t = 2160;
    end
    return t&~1;
  endfunction

  function int src_line_bytes();
    return eff_w()*2;
  endfunction

  function int dst_line_bytes();
    return eff_w()*3;
  endfunction

  // --------------------------------------------------------------------------
  // 乱数化
  // --------------------------------------------------------------------------
  // 画像処理の設定(サイズとアドレス以外)
  function void rand_func();
    phase    = 2'($urandom_range(3, 0));
    blc_en   = 1'($urandom_range(1, 0));
    wb_en    = 1'($urandom_range(1, 0));
    fcs_en   = 1'($urandom_range(1, 0));
    gamma_en = 1'($urandom_range(1, 0));
    bypass   = ($urandom_range(9, 0)==0);
    tpg_en   = 1'b0;
    for( int i=0; i<4; i++ ) begin
      case( $urandom_range(3, 0) )
        0 : begin
          blc[i] = 14'd0;
        end
        1 : begin
          blc[i] = 14'($urandom_range(1023, 0));
        end
        2 : begin
          blc[i] = 14'($urandom_range(16383, 0));
        end
        default : begin
          blc[i] = 14'($urandom_range(300, 200));
        end
      endcase
      case( $urandom_range(3, 0) )
        0 : begin
          wbg[i] = 16'h1000;
        end
        1 : begin
          wbg[i] = 16'($urandom_range(16'h3000, 16'h0800));
        end
        2 : begin
          wbg[i] = 16'($urandom_range(16'hFFFF, 0));
        end
        default : begin
          wbg[i] = 16'($urandom_range(16'h2000, 16'h1000));
        end
      endcase
    end
    case( $urandom_range(3, 0) )
      0 : begin
        fcs_th = 14'd0;
      end
      1 : begin
        fcs_th = 14'($urandom_range(16383, 0));
      end
      default : begin
        fcs_th = 14'($urandom_range(2000, 0));
      end
    endcase
    case( $urandom_range(3, 0) )
      0 : begin
        fcs_gain = 8'd0;
      end
      1 : begin
        fcs_gain = 8'd255;
      end
      default : begin
        fcs_gain = 8'($urandom_range(64, 1));
      end
    endcase
    rand_gamma($urandom_range(3, 0));
    img_kind = $urandom_range(6, 0);
  endfunction

  // ガンマの折れ点: 0=sRGB 1=単調増加の乱数 2=任意の乱数 3=直線
  function void rand_gamma( int mode );
    int v;
    case( mode )
      0 : begin
        for( int i=0; i<37; i++ ) begin
          gm_knot[i] = BAYER2RGB_PKG::GM_SRGB[i];
        end
      end
      1 : begin
        v = 0;
        for( int i=0; i<37; i++ ) begin
          v = v+$urandom_range(200, 0);
          if( v>4095 ) begin
            v = 4095;
          end
          gm_knot[i] = 12'(v);
        end
      end
      2 : begin
        for( int i=0; i<37; i++ ) begin
          gm_knot[i] = 12'($urandom_range(4095, 0));
        end
      end
      default : begin
        for( int i=0; i<37; i++ ) begin
          gm_knot[i] = 12'((i*4095)/36);
        end
      end
    endcase
  endfunction

  // テストパターン
  function void rand_tpg();
    tpg_en    = 1'b1;
    tpg_sel   = 2'($urandom_range(3, 0));
    tpg_color = 24'($urandom());
  endfunction

  // AXIの属性
  function void rand_attr();
    arcache = 4'($urandom_range(15, 0));
    awcache = 4'($urandom_range(15, 0));
    arprot  = 3'($urandom_range(7, 0));
    awprot  = 3'($urandom_range(7, 0));
    arqos   = 4'($urandom_range(15, 0));
    awqos   = 4'($urandom_range(15, 0));
  endfunction

  // アドレスとライン間隔を決める(入力と出力の領域は重ならない)
  //   base: 入力領域の先頭(16バイト境界)、pad_max: ライン間隔の余り(16バイト単位)
  function void place( bit [39:0] base, int pad_max );
    longint unsigned src_size;
    src_stride = 24'(src_line_bytes()+(16*$urandom_range(pad_max, 0)));
    dst_stride = 24'(((dst_line_bytes()+15)&~15)+(16*$urandom_range(pad_max, 0)));
    src_addr   = base+40'(16*$urandom_range(255, 0));
    src_size   = longint'(src_stride)*eff_h();
    dst_addr   = (src_addr+40'(src_size)+40'h1000)&~40'hF;
    dst_addr   = dst_addr+40'(16*$urandom_range(255, 0));
  endfunction

  function string convert2string();
    return $sformatf("W=%0d(%0d) H=%0d(%0d) phase=%0d blc_en=%0d wb_en=%0d fcs_en=%0d gamma_en=%0d bypass=%0d tpg=%0d/%0d src=%0h/%0d dst=%0h/%0d img=%0d",
                    width, eff_w(), height, eff_h(), phase, blc_en, wb_en, fcs_en, gamma_en, bypass,
                    tpg_en, tpg_sel, src_addr, src_stride, dst_addr, dst_stride, img_kind);
  endfunction

  // 値のコピー
  function void copy_from( b2r_frame_cfg c );
    width      = c.width;
    height     = c.height;
    phase      = c.phase;
    blc_en     = c.blc_en;
    wb_en      = c.wb_en;
    fcs_en     = c.fcs_en;
    gamma_en   = c.gamma_en;
    bypass     = c.bypass;
    tpg_en     = c.tpg_en;
    tpg_sel    = c.tpg_sel;
    tpg_color  = c.tpg_color;
    blc        = c.blc;
    wbg        = c.wbg;
    fcs_th     = c.fcs_th;
    fcs_gain   = c.fcs_gain;
    gm_knot    = c.gm_knot;
    src_addr   = c.src_addr;
    src_stride = c.src_stride;
    dst_addr   = c.dst_addr;
    dst_stride = c.dst_stride;
    arcache    = c.arcache;
    awcache    = c.awcache;
    arprot     = c.arprot;
    awprot     = c.awprot;
    arqos      = c.arqos;
    awqos      = c.awqos;
    img_kind   = c.img_kind;
  endfunction

endclass
