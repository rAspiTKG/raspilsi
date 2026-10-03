//=============================================================================
// axi_mem.svh
//-----------------------------------------------------------------------------
//  axi_mem     : スレーブ応答 agent / scoreboard / 仮想シーケンスで共有する
//                バイト単位のメモリモデル (入力側と出力側で 1 個ずつ持つ)
//  axi_slv_cfg : スレーブ応答の振る舞い (ストール / READY の出し方 / エラー注入)
//                仮想シーケンスから実行中に書き換える
//=============================================================================

class axi_mem extends uvm_object;

  `uvm_object_utils(axi_mem)

  protected bit [7:0] m_mem[bit [63:0]];

  function new(string name = "axi_mem");
    super.new(name);
  endfunction

  // 1 バイト読み出し (未書き込みは 0)
  function bit [7:0] read_byte(bit [63:0] a);
    if( m_mem.exists(a) ) begin
      return m_mem[a];
    end
    return 8'h00;
  endfunction

  function void write_byte(bit [63:0] a, bit [7:0] d);
    m_mem[a] = d;
  endfunction

  // バス幅 1 ワード読み出し (a を nbytes 境界に切り下げる)
  function bit [MAX_DATA_W-1:0] read_word(bit [63:0] a, int unsigned nbytes);
    bit [63:0]           base;
    bit [MAX_DATA_W-1:0] d;
    base = a & ~(64'(nbytes) - 64'd1);
    d    = '0;
    for( int unsigned b=0; b<nbytes; b++ ) begin
      d[8*b+:8] = read_byte(base + 64'(b));
    end
    return d;
  endfunction

  // バス幅 1 ワード書き込み (strb が立ったバイトのみ)
  function void write_word(bit [63:0] a, bit [MAX_DATA_W-1:0] d, bit [MAX_STRB_W-1:0] strb, int unsigned nbytes);
    bit [63:0] base;
    base = a & ~(64'(nbytes) - 64'd1);
    for( int unsigned b=0; b<nbytes; b++ ) begin
      if( strb[b] ) begin
        m_mem[base + 64'(b)] = d[8*b+:8];
      end
    end
  endfunction

  // [a, a+nbytes) をランダムデータで埋める
  function void fill_random(bit [63:0] a, int unsigned nbytes);
    for( int unsigned i=0; i<nbytes; i++ ) begin
      m_mem[a + 64'(i)] = 8'($urandom());
    end
  endfunction

  // [lo, hi) を lb_pattern() で埋める
  function void fill_pattern(bit [63:0] lo, bit [63:0] hi);
    bit [63:0] a;
    for( a=lo; a<hi; a=a+64'd1 ) begin
      m_mem[a] = lb_pattern(a);
    end
  endfunction

endclass

class axi_slv_cfg extends uvm_object;

  `uvm_object_utils(axi_slv_cfg)

  int unsigned stall_pct        = 0;      // READY を下げる / VALID を遅らせる確率 [%]
  bit          ready_wait_valid = 1'b0;   // READY を VALID を見てから立てる
  bit [63:0]   err_lo           = '1;     // SLVERR を返す範囲 (err_lo > err_hi で無効)
  bit [63:0]   err_hi           = '0;

  function new(string name = "axi_slv_cfg");
    super.new(name);
  endfunction

  function bit stall();
    return ($urandom_range(99,0)<stall_pct);
  endfunction

  // VALID を出すまでの待ちサイクル数
  function int unsigned delay();
    if( stall() ) begin
      return $urandom_range(4,1);
    end
    return 0;
  endfunction

  // 次サイクルの READY
  //   通常            : VALID と無関係にランダム
  //   ready_wait_valid: VALID が立っていて、このサイクルで握手していなければ立てる
  //   (スレーブが VALID を待つのは AXI で許されている。マスタが READY を待って
  //    VALID を出す実装だとこのモードでデッドロックする)
  function bit ready_next(bit valid_now, bit hs_now);
    if( ready_wait_valid ) begin
      return valid_now&&!hs_now&&!stall();
    end
    return !stall();
  endfunction

  // ビートの先頭アドレス a がエラー範囲に入るか
  function bit in_err(bit [63:0] a);
    return (err_lo<=err_hi)&&(a>=err_lo)&&(a<=err_hi);
  endfunction

  function bit err_enabled();
    return (err_lo<=err_hi);
  endfunction

  function void clear_err();
    err_lo = '1;
    err_hi = '0;
  endfunction

  function string convert2string();
    if( err_lo<=err_hi ) begin
      return $sformatf("stall=%0d%% ready_wait_valid=%0d err=[%0h:%0h]", stall_pct, ready_wait_valid, err_lo, err_hi);
    end
    return $sformatf("stall=%0d%% ready_wait_valid=%0d err=off", stall_pct, ready_wait_valid);
  endfunction

endclass
