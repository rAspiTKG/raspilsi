//=============================================================================
// axi_slv_mem.svh
//-----------------------------------------------------------------------------
//  axi_slv_mem : スレーブのワード単位メモリ。responder / scoreboard / 仮想シーケンスで共有する
//                (キーはワード先頭のアドレス)
//  axi_slv_cfg : スレーブの振る舞い (READY の確率、AWREADY / WREADY の待ち合わせ、
//                応答の遅延、エラー応答の範囲)。仮想シーケンスがコマンドの合間に書き換える
//=============================================================================

class axi_slv_mem extends uvm_object;

  `uvm_object_utils(axi_slv_mem)

  typedef bit [63:0] key_q_t[$];

  protected bit [DATA_W-1:0] m_mem[bit [63:0]];

  function new(string name = "axi_slv_mem");
    super.new(name);
  endfunction

  static function bit [63:0] key(bit [63:0] a);
    return (a / 64'(STRB_W)) * 64'(STRB_W);
  endfunction

  // 1 ワード読み出し (未書き込みは 0)
  function bit [DATA_W-1:0] read_word(bit [63:0] a);
    if( m_mem.exists(key(a)) ) begin
      return m_mem[key(a)];
    end
    return {DATA_W{1'b0}};
  endfunction

  // 1 ワード書き込み (strb が立ったバイトのみ)
  function void write_word(bit [63:0] a, bit [DATA_W-1:0] d, bit [STRB_W-1:0] strb);
    bit [DATA_W-1:0] w;
    w = read_word(a);
    for( int unsigned b=0; b<STRB_W; b++ ) begin
      if( strb[b] ) begin
        w[8*b +: 8] = d[8*b +: 8];
      end
    end
    m_mem[key(a)] = w;
  endfunction

  // [ワード位置 w0 から n ワード] を乱数で埋める
  function void fill_random(longint unsigned w0, int unsigned n);
    bit [DATA_W-1:0] d;
    for( int unsigned i=0; i<n; i++ ) begin
      if( (w0+64'(i))<SPACE_WORDS ) begin
        for( int unsigned b=0; b<DATA_W; b++ ) begin
          d[b] = 1'($urandom());
        end
        m_mem[axlm_waddr(w0+64'(i))] = d;
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

class axi_slv_cfg extends uvm_object;

  `uvm_object_utils(axi_slv_cfg)

  // READY を 1 にする確率 [%]
  int unsigned aw_ready_pct = 100;
  int unsigned w_ready_pct  = 100;
  int unsigned ar_ready_pct = 100;
  // 1 : W のデータが来ているまで AWREADY を出さない / AW のアドレスが来ているまで WREADY を出さない
  bit          aw_wait_w    = 1'b0;
  bit          w_wait_aw    = 1'b0;
  // 応答の遅延 [cycle] (アドレスとデータが揃った次のサイクルから数える)
  int unsigned b_lat_min    = 0;
  int unsigned b_lat_max    = 0;
  int unsigned r_lat_min    = 0;
  int unsigned r_lat_max    = 0;
  // エラー応答 (アドレス範囲 [lo, hi] を 2 つまで。resp が 2'b00 なら無効。両方に入るときは [0] が優先)
  bit [1:0]    werr_resp[2];
  bit [63:0]   werr_lo[2];
  bit [63:0]   werr_hi[2];
  bit [1:0]    rerr_resp[2];
  bit [63:0]   rerr_lo[2];
  bit [63:0]   rerr_hi[2];
  // 仕様上「見てはいけない」値 (VALID=0 のときの BRESP / RDATA / RRESP、BID / RID / RLAST) を乱数にする
  bit          noise        = 1'b1;

  function new(string name = "axi_slv_cfg");
    super.new(name);
    clear_err();
  endfunction

  // READY が常に 1、遅延 0 (DUT のサイクル数を正確に照合できる)
  function bit is_ideal();
    return (aw_ready_pct>=100)&&(w_ready_pct>=100)&&(ar_ready_pct>=100)&&!aw_wait_w&&!w_wait_aw&&(b_lat_max==0)&&(r_lat_max==0);
  endfunction

  function void set_ideal();
    set_ready(100, 100, 100);
    set_lat(0, 0, 0, 0);
    aw_wait_w = 1'b0;
    w_wait_aw = 1'b0;
  endfunction

  function void set_ready(int unsigned aw, int unsigned w, int unsigned ar);
    aw_ready_pct = aw;
    w_ready_pct  = w;
    ar_ready_pct = ar;
  endfunction

  function void set_lat(int unsigned bmin, int unsigned bmax, int unsigned rmin, int unsigned rmax);
    b_lat_min = bmin;
    b_lat_max = bmax;
    r_lat_min = rmin;
    r_lat_max = rmax;
  endfunction

  function void set_werr(int unsigned i, bit [1:0] resp, bit [63:0] lo, bit [63:0] hi);
    werr_resp[i] = resp;
    werr_lo[i]   = lo;
    werr_hi[i]   = hi;
  endfunction

  function void set_rerr(int unsigned i, bit [1:0] resp, bit [63:0] lo, bit [63:0] hi);
    rerr_resp[i] = resp;
    rerr_lo[i]   = lo;
    rerr_hi[i]   = hi;
  endfunction

  // 1 ワードぶんの範囲
  function void set_werr_word(int unsigned i, bit [1:0] resp, bit [63:0] a);
    set_werr(i, resp, a, a + 64'(STRB_W) - 64'd1);
  endfunction

  function void set_rerr_word(int unsigned i, bit [1:0] resp, bit [63:0] a);
    set_rerr(i, resp, a, a + 64'(STRB_W) - 64'd1);
  endfunction

  function void clear_err();
    for( int unsigned i=0; i<2; i++ ) begin
      werr_resp[i] = 2'b00;
      werr_lo[i]   = '0;
      werr_hi[i]   = '0;
      rerr_resp[i] = 2'b00;
      rerr_lo[i]   = '0;
      rerr_hi[i]   = '0;
    end
  endfunction

  function bit [1:0] wresp(bit [63:0] a);
    for( int unsigned i=0; i<2; i++ ) begin
      if( (werr_resp[i]!=2'b00)&&(a>=werr_lo[i])&&(a<=werr_hi[i]) ) begin
        return werr_resp[i];
      end
    end
    return 2'b00;
  endfunction

  function bit [1:0] rresp(bit [63:0] a);
    for( int unsigned i=0; i<2; i++ ) begin
      if( (rerr_resp[i]!=2'b00)&&(a>=rerr_lo[i])&&(a<=rerr_hi[i]) ) begin
        return rerr_resp[i];
      end
    end
    return 2'b00;
  endfunction

  function string convert2string();
    string s;
    s = $sformatf("READY %0d/%0d/%0d%% B lat %0d..%0d R lat %0d..%0d", aw_ready_pct, w_ready_pct, ar_ready_pct, b_lat_min, b_lat_max, r_lat_min, r_lat_max);
    if( aw_wait_w ) begin
      s = {s, " AWREADY-waits-W"};
    end
    if( w_wait_aw ) begin
      s = {s, " WREADY-waits-AW"};
    end
    for( int unsigned i=0; i<2; i++ ) begin
      if( werr_resp[i]!=2'b00 ) begin
        s = {s, $sformatf(" werr%0d=%b@%0h..%0h", i, werr_resp[i], werr_lo[i], werr_hi[i])};
      end
      if( rerr_resp[i]!=2'b00 ) begin
        s = {s, $sformatf(" rerr%0d=%b@%0h..%0h", i, rerr_resp[i], rerr_lo[i], rerr_hi[i])};
      end
    end
    return s;
  endfunction

endclass
