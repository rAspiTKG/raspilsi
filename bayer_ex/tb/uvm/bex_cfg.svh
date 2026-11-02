// ============================================================================
// bex_cfg : DUT の設定(i_cfg)
//   乱数化は手続きで行う(rand_* 関数)。シードで再現できる。
// ============================================================================
class bex_cfg extends uvm_object;
  `uvm_object_utils(bex_cfg)

  bit        bypass;
  bit [1:0]  phase;     // 0:RGGB 1:GRBG 2:GBRG 3:BGGR
  bit [13:0] blc[4];    // [0]R [1]Gr [2]Gb [3]B
  bit [15:0] gain[4];   // U4.12

  function new( string name="bex_cfg" );
    super.new(name);
    set_default();
  endfunction

  // 補正しても値が変わらない設定(黒レベル 0、ゲイン 1.0倍)
  function void set_default();
    bypass = 1'b0;
    phase  = 2'd0;
    for( int i=0; i<4; i++ ) begin
      blc[i]  = 14'd0;
      gain[i] = 16'h1000;
    end
  endfunction

  // --------------------------------------------------------------------------
  // 乱数の設定。端の値(0、最大値、1.0倍)も一定の割合で選ぶ
  //   bypass_pct: bypass=1 にする割合 [%]
  // --------------------------------------------------------------------------
  function void rand_cfg( int bypass_pct=10 );
    bypass = ($urandom_range(99, 0)<bypass_pct);
    phase  = 2'($urandom_range(3, 0));
    for( int i=0; i<4; i++ ) begin
      blc[i]  = rand_blc();
      gain[i] = rand_gain();
    end
  endfunction

  function bit [13:0] rand_blc();
    case( $urandom_range(9, 0) )
      0 : begin
        return 14'd0;
      end
      1 : begin
        return 14'h3FFF;
      end
      2, 3 : begin
        return 14'($urandom_range(16383, 0));
      end
      default : begin
        return 14'($urandom_range(1023, 0));
      end
    endcase
  endfunction

  function bit [15:0] rand_gain();
    case( $urandom_range(9, 0) )
      0 : begin
        return 16'h0000;
      end
      1 : begin
        return 16'hFFFF;
      end
      2 : begin
        return 16'h1000;
      end
      3, 4 : begin
        return 16'($urandom_range(16'h0FFF, 16'h0001));
      end
      default : begin
        return 16'($urandom_range(16'h3FFF, 16'h1001));
      end
    endcase
  endfunction

  // --------------------------------------------------------------------------
  // 変換・複製
  // --------------------------------------------------------------------------
  function cfg_t to_cfg_t();
    cfg_t c;
    c.bypass = bypass;
    c.phase  = phase;
    for( int i=0; i<4; i++ ) begin
      c.blc[i]  = blc[i];
      c.gain[i] = gain[i];
    end
    return c;
  endfunction

  function void from_cfg_t( cfg_t c );
    bypass = c.bypass;
    phase  = c.phase;
    for( int i=0; i<4; i++ ) begin
      blc[i]  = c.blc[i];
      gain[i] = c.gain[i];
    end
  endfunction

  function void copy_from( bex_cfg o );
    from_cfg_t(o.to_cfg_t());
  endfunction

  function string convert2string();
    return $sformatf("bypass=%0d phase=%0d blc=%0d/%0d/%0d/%0d gain=%04h/%04h/%04h/%04h", bypass, phase,
                      blc[0], blc[1], blc[2], blc[3], gain[0], gain[1], gain[2], gain[3]);
  endfunction
endclass
