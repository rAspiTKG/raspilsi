//=============================================================================
// apb_slv_mem.svh
//-----------------------------------------------------------------------------
//  apb_slv_mem : 全スレーブぶんのワード単位メモリ。responder / scoreboard /
//                仮想シーケンスで共有する (キーは {スレーブ番号, ワード先頭アドレス})
//  apb_slv_cfg : スレーブ 1 個の振る舞い (ウェイト / PSLVERR / ハング)。
//                仮想シーケンスがコマンドの合間に書き換える
//=============================================================================

class apb_slv_mem extends uvm_object;

  `uvm_object_utils(apb_slv_mem)

  typedef bit [63:0] key_q_t[$];

  protected bit [DATA_W-1:0] m_mem[bit [63:0]];

  function new(string name = "apb_slv_mem");
    super.new(name);
  endfunction

  static function bit [63:0] key(int unsigned s, bit [63:0] a);
    bit [63:0] base;
    base = (a / 64'(STRB_W)) * 64'(STRB_W);
    return {32'(s), base[31:0]};
  endfunction

  // 1 ワード読み出し (未書き込みは 0)
  function bit [DATA_W-1:0] read_word(int unsigned s, bit [63:0] a);
    if( m_mem.exists(key(s,a)) ) begin
      return m_mem[key(s,a)];
    end
    return {DATA_W{1'b0}};
  endfunction

  // 1 ワード書き込み (strb が立ったバイトのみ)
  function void write_word(int unsigned s, bit [63:0] a, bit [DATA_W-1:0] d, bit [STRB_W-1:0] strb);
    bit [DATA_W-1:0] w;
    w = read_word(s, a);
    for( int unsigned b=0; b<STRB_W; b++ ) begin
      if( strb[b] ) begin
        w[8*b +: 8] = d[8*b +: 8];
      end
    end
    m_mem[key(s,a)] = w;
  endfunction

  // スレーブ s の [ワード位置 w0 から n ワード] を乱数で埋める
  function void fill_random(int unsigned s, longint unsigned w0, int unsigned n);
    bit [DATA_W-1:0] d;
    for( int unsigned i=0; i<n; i++ ) begin
      if( (w0+64'(i))<SPACE_WORDS ) begin
        for( int unsigned b=0; b<DATA_W; b++ ) begin
          d[b] = 1'($urandom());
        end
        m_mem[key(s, apbm_waddr(w0+64'(i)))] = d;
      end
    end
  endfunction

  function int unsigned num();
    return m_mem.num();
  endfunction

  function bit exists(bit [63:0] k);
    return m_mem.exists(k);
  endfunction

  function bit [DATA_W-1:0] get(bit [63:0] k);
    return m_mem[k];
  endfunction

  // 全てのキーを取り出す
  function key_q_t get_keys();
    key_q_t    keys;
    bit [63:0] k;
    if( m_mem.first(k)!=0 ) begin
      do begin
        keys.push_back(k);
      end while( m_mem.next(k)!=0 );
    end
    return keys;
  endfunction

endclass

class apb_slv_cfg extends uvm_object;

  `uvm_object_utils(apb_slv_cfg)

  int unsigned wait_min = 0;        // 転送ごとのウェイト数の範囲
  int unsigned wait_max = 0;
  bit [63:0]   err_lo   = '1;       // PSLVERR を返す範囲 (err_lo > err_hi で無効)
  bit [63:0]   err_hi   = '0;
  bit [63:0]   hang_lo  = '1;       // PREADY を返さない範囲 (hang_lo > hang_hi で無効)
  bit [63:0]   hang_hi  = '0;
  // 仕様上「見てはいけない」タイミングの PREADY / PSLVERR / PRDATA を乱数にする
  bit          noise    = 1'b1;

  function new(string name = "apb_slv_cfg");
    super.new(name);
  endfunction

  function int unsigned pick_wait();
    return $urandom_range(wait_max, wait_min);
  endfunction

  function bit in_err(bit [63:0] a);
    return (err_lo<=err_hi)&&(a>=err_lo)&&(a<=err_hi);
  endfunction

  function bit in_hang(bit [63:0] a);
    return (hang_lo<=hang_hi)&&(a>=hang_lo)&&(a<=hang_hi);
  endfunction

  // この設定では、ウェイトだけで必ずタイムアウトするか
  function bit wait_times_out();
    return (TIMEOUT_CYCLES>0)&&(wait_min>=TIMEOUT_CYCLES);
  endfunction

  function void set_wait(int unsigned lo, int unsigned hi);
    wait_min = lo;
    wait_max = hi;
  endfunction

  // 1 ワードぶんの範囲を設定する
  function void set_err_word(bit [63:0] a);
    err_lo = a;
    err_hi = a + 64'(STRB_W) - 64'd1;
  endfunction

  function void set_hang_word(bit [63:0] a);
    hang_lo = a;
    hang_hi = a + 64'(STRB_W) - 64'd1;
  endfunction

  function void clear_err();
    err_lo  = '1;
    err_hi  = '0;
    hang_lo = '1;
    hang_hi = '0;
  endfunction

  function string convert2string();
    string s;
    s = $sformatf("wait=%0d..%0d", wait_min, wait_max);
    if( err_lo<=err_hi ) begin
      s = {s, $sformatf(" err=%0h", err_lo)};
    end
    if( hang_lo<=hang_hi ) begin
      s = {s, $sformatf(" hang=%0h", hang_lo)};
    end
    return s;
  endfunction

endclass
