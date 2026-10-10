//=============================================================================
// axlm_seq_lib.svh
//-----------------------------------------------------------------------------
//  cmd_single_seq  : コマンド 1 本を書き込み / 読み出しの sequencer に流す
//  loc_single_seq  : ローカルポートの操作 1 つを流す
//  axlm_base_vseq  : 仮想シーケンスの共通処理
//                    (内部メモリの書き込み / 読み出し、コマンド、スレーブの設定、
//                     同時に動かすときの内部メモリの使用範囲の管理)
//  axlm_smoke_vseq : 代表パターン (基本 / 同時実行 / 端 / エラー応答 / 遅延と READY /
//                    コマンドの誤り / ローカルポート / 実行中に出したまま待つコマンド)
//  axlm_rand_vseq  : 書き込みコマンド / 読み出しコマンド / ローカルポートを同時に、
//                    スレーブの振る舞いとエラー範囲を変えながらランダムに流す
//
//  スレーブの設定 (cfg) は、全てのコマンドが完了してから変える
//  (scoreboard / coverage は受付時の設定を使う)。
//  同時に動かす書き込みと読み出しは、内部メモリの範囲とスレーブのアドレス (窓) を分ける
//  (重なったときの結果は仕様上決まらない。scoreboard が「テストベンチの誤り」として報告する)。
//=============================================================================

class cmd_single_seq extends uvm_sequence #(cmd_item);

  `uvm_object_utils(cmd_single_seq)

  cmd_item m_item;

  function new(string name = "cmd_single_seq");
    super.new(name);
  endfunction

  task body();
    start_item(m_item);
    finish_item(m_item);
  endtask

endclass

class loc_single_seq extends uvm_sequence #(loc_item);

  `uvm_object_utils(loc_single_seq)

  loc_item m_item;

  function new(string name = "loc_single_seq");
    super.new(name);
  endfunction

  task body();
    start_item(m_item);
    finish_item(m_item);
  endtask

endclass

//=============================================================================
// 共通処理
//=============================================================================
class axlm_base_vseq extends uvm_sequence;

  `uvm_object_utils(axlm_base_vseq)
  `uvm_declare_p_sequencer(axlm_vsequencer)

  // 内部メモリの使用中の範囲 (0 = 書き込みコマンド / 1 = 読み出しコマンド / 2 = ローカルポート)
  protected int unsigned m_lk_lo[3];
  protected int unsigned m_lk_n[3];

  function new(string name = "axlm_base_vseq");
    super.new(name);
  endfunction

  //---------------------------------------------------------------------------
  // sequencer へ流す
  //---------------------------------------------------------------------------
  protected task send_cmd(cmd_item c);
    cmd_single_seq s;
    s        = cmd_single_seq::type_id::create("s");
    s.m_item = c;
    if( c.wr ) begin
      s.start(p_sequencer.wsqr, this);
    end else begin
      s.start(p_sequencer.rsqr, this);
    end
    `uvm_info("VSEQ", $sformatf("%s -> err_flags=%b err_index=%0d done_count=%0d", c.convert2string(), c.err_flags, c.err_index, c.done_count), UVM_HIGH)
  endtask

  protected task send_loc(loc_item it);
    loc_single_seq s;
    s        = loc_single_seq::type_id::create("s");
    s.m_item = it;
    s.start(p_sequencer.lsqr, this);
  endtask

  //---------------------------------------------------------------------------
  // スレーブ
  //---------------------------------------------------------------------------
  // スレーブのメモリに初期値を入れる (最初のコマンドより前に呼ぶ)
  protected function void init_slave();
    p_sequencer.smem.fill_random(WB, LWIN);
    p_sequencer.smem.fill_random(RB, LWIN);
    p_sequencer.smem.fill_random(64'd0, 4);
    if( SPACE_WORDS>=64'(MEM_DEPTH) ) begin
      p_sequencer.smem.fill_random(SPACE_WORDS - 64'(MEM_DEPTH), MEM_DEPTH);
    end else begin
      p_sequencer.smem.fill_random(64'd0, int'(SPACE_WORDS));
    end
  endfunction

  protected function void set_ideal();
    p_sequencer.cfg.set_ideal();
  endfunction

  // READY の確率と遅延を乱数で決める。sel で AWREADY / WREADY の待ち合わせも入れる
  protected function void set_rand_slave(int unsigned sel);
    p_sequencer.cfg.set_ready($urandom_range(100,20), $urandom_range(100,20), $urandom_range(100,20));
    p_sequencer.cfg.set_lat(0, $urandom_range(8,0), 0, $urandom_range(8,0));
    p_sequencer.cfg.aw_wait_w = ((sel%4)==1)||((sel%4)==3);
    p_sequencer.cfg.w_wait_aw = ((sel%4)==2)||((sel%4)==3);
  endfunction

  // 窓の中に、エラー応答の範囲 (1〜3 ワード) を i 番目として置く。応答の種類は resp (0 なら乱数)
  protected function void rand_err(bit wr, int unsigned i, longint unsigned w0, bit [1:0] resp = 2'b00);
    bit [63:0] a;
    bit [63:0] b;
    bit [1:0]  r;
    a = axlm_waddr(w0 + 64'($urandom_range(LWIN-1,0)));
    b = a + (64'(STRB_W) * 64'($urandom_range(2,0))) + 64'(STRB_W-1);
    r = (resp!=2'b00) ? resp : 2'($urandom_range(3,1));
    if( wr ) begin
      p_sequencer.cfg.set_werr(i, r, a, b);
    end else begin
      p_sequencer.cfg.set_rerr(i, r, a, b);
    end
  endfunction

  //---------------------------------------------------------------------------
  // 内部メモリのローカルポート
  //---------------------------------------------------------------------------
  protected function loc_item new_loc_wr(int unsigned maddr, int unsigned n, int unsigned gap_pct = 0, int unsigned idle = 0);
    loc_item         it;
    bit [DATA_W-1:0] d;
    it          = loc_item::type_id::create("lw");
    it.wr_maddr = maddr;
    it.gap_pct  = gap_pct;
    it.idle     = idle;
    for( int unsigned i=0; i<n; i++ ) begin
      for( int unsigned b=0; b<DATA_W; b++ ) begin
        d[b] = 1'($urandom());
      end
      it.wr_data.push_back(d);
    end
    return it;
  endfunction

  protected function loc_item new_loc_rd(int unsigned maddr, int unsigned n, int unsigned gap_pct = 0, int unsigned idle = 0);
    loc_item it;
    it          = loc_item::type_id::create("lr");
    it.rd_maddr = maddr;
    it.rd_n     = n;
    it.gap_pct  = gap_pct;
    it.idle     = idle;
    return it;
  endfunction

  protected task mem_write(int unsigned maddr, int unsigned n, int unsigned gap_pct = 0);
    send_loc(new_loc_wr(maddr, n, gap_pct));
  endtask

  // 読めたデータは scoreboard が照合する
  protected task mem_read(int unsigned maddr, int unsigned n, int unsigned gap_pct = 0);
    send_loc(new_loc_rd(maddr, n, gap_pct));
  endtask

  protected task mem_fill();
    mem_write(0, MEM_DEPTH);
  endtask

  protected task mem_dump();
    mem_read(0, MEM_DEPTH);
  endtask

  //---------------------------------------------------------------------------
  // コマンド
  //---------------------------------------------------------------------------
  protected function cmd_item new_cmd
  (
    bit              wr
   ,bit [63:0]       addr
   ,bit              incr
   ,int unsigned     maddr
   ,int unsigned     len
   ,bit [STRB_W-1:0] strb = {STRB_W{1'b1}}
   ,bit [2:0]        prot = 3'b000
  );
    cmd_item c;
    c = cmd_item::type_id::create("c");
    c.set_cmd(wr, addr, incr, maddr, len, strb, prot);
    return c;
  endfunction

  protected task wcmd(bit [63:0] addr, bit incr, int unsigned maddr, int unsigned len, bit [STRB_W-1:0] strb = {STRB_W{1'b1}}, bit [2:0] prot = 3'b000);
    send_cmd(new_cmd(1'b1, addr, incr, maddr, len, strb, prot));
  endtask

  protected task rcmd(bit [63:0] addr, bit incr, int unsigned maddr, int unsigned len, bit [2:0] prot = 3'b000);
    send_cmd(new_cmd(1'b0, addr, incr, maddr, len, {STRB_W{1'b0}}, prot));
  endtask

  // 書き込みと読み出しを同時に出す (同じサイクルに受け付けられる)
  protected task pair(cmd_item w, cmd_item r);
    fork
      begin
        send_cmd(w);
      end
      begin
        send_cmd(r);
      end
    join
  endtask

  // 内部メモリ [m_lo, m_lo+m_n) と窓 [w_lo, w_lo+w_n) に収まる、制約付きランダムなコマンド
  protected function cmd_item new_rand_cmd(bit wr, int unsigned m_lo, int unsigned m_n, longint unsigned w_lo, int unsigned w_n);
    cmd_item c;
    c = cmd_item::type_id::create(wr ? "rw" : "rr");
    c.set_region(wr, m_lo, m_n, w_lo, w_n);
    if( !c.randomize() ) begin
      `uvm_error("RAND", "cmd_item randomize failed")
    end
    return c;
  endfunction

  // 書き込み (窓 WB、内部メモリ [0, MH)) と読み出し (窓 RB、内部メモリ [MH, MEM_DEPTH)) を
  // ランダムな形で同時に出す (内部メモリが 1 ワードなら順に)
  protected task rand_pair();
    int unsigned mh;
    mh = MEM_DEPTH / 2;
    if( mh==0 ) begin
      send_cmd(new_rand_cmd(1'b1, 0, MEM_DEPTH, WB, LWIN));
      send_cmd(new_rand_cmd(1'b0, 0, MEM_DEPTH, RB, LWIN));
    end else begin
      pair(new_rand_cmd(1'b1, 0, mh, WB, LWIN), new_rand_cmd(1'b0, mh, MEM_DEPTH - mh, RB, LWIN));
    end
  endtask

  // DUT が断るべきコマンド / 何もしないコマンド (内部メモリにもバスにも触らない)
  //   kind 0: 0 ワード / 1: 0 ワード (他の項目も誤り) / 2: メモリ範囲超え / 3: 非アライン /
  //        4: アドレス範囲超え (内部メモリが 1 ワードの構成では非アライン)
  protected function cmd_item new_bad_cmd(bit wr, int unsigned kind);
    cmd_item c;
    c = new_rand_cmd(wr, 0, MEM_DEPTH, wr ? WB : RB, LWIN);
    case( kind )
      0 : begin
        c.len = 0;
      end
      1 : begin
        c.len   = 0;
        c.maddr = (1<<MEM_AW) - 1;
        c.addr  = axlm_waddr(SPACE_WORDS - 64'd1) + 64'(STRB_W-1);
        c.incr  = 1'b1;
      end
      2 : begin
        if( MEM_DEPTH>=2 ) begin
          c.len   = (c.len<2) ? 2 : c.len;
          c.maddr = MEM_DEPTH - c.len + 1;
        end else begin
          c.len   = 1;
          c.maddr = 1;
        end
      end
      3 : begin
        c.addr = c.addr + 64'($urandom_range(STRB_W-1,1));
      end
      default : begin
        if( MEM_DEPTH>=2 ) begin
          c.incr  = 1'b1;
          c.len   = (c.len<2) ? 2 : c.len;
          c.maddr = MEM_DEPTH - c.len;
          c.addr  = axlm_waddr(SPACE_WORDS - 64'(c.len) + 64'd1);
        end else begin
          c.addr = c.addr + 64'($urandom_range(STRB_W-1,1));
        end
      end
    endcase
    return c;
  endfunction

  //---------------------------------------------------------------------------
  // 内部メモリの使用範囲 (ランダムに同時実行するとき)
  //---------------------------------------------------------------------------
  protected function bit lk_free(int unsigned self, int unsigned lo, int unsigned n);
    for( int unsigned p=0; p<3; p++ ) begin
      if( (p!=self)&&(m_lk_n[p]!=0)&&(lo<(m_lk_lo[p]+m_lk_n[p]))&&(m_lk_lo[p]<(lo+n)) ) begin
        return 1'b0;
      end
    end
    return 1'b1;
  endfunction

  // 内部メモリ [base, base+span) の中で、空いている範囲 (nmax ワードまで) を探して確保する (見つからなければ 0)。
  // prefer_long=1 なら半分の確率で nmax/2 ワード以上にする
  protected function bit lk_take
  (
    input  int unsigned self
   ,input  int unsigned base
   ,input  int unsigned span
   ,input  int unsigned nmax
   ,output int unsigned lo
   ,output int unsigned n
   ,input  bit          prefer_long = 1'b0
  );
    int unsigned sel;
    if( nmax>span ) begin
      nmax = span;
    end
    for( int unsigned t=0; t<8; t++ ) begin
      sel = $urandom_range(3,0);
      if( prefer_long&&(sel>=2) ) begin
        n = $urandom_range(nmax, (nmax+1)/2);
      end else if( sel[0] ) begin
        n = $urandom_range(nmax, 1);
      end else begin
        n = $urandom_range((nmax<4) ? nmax : 4, 1);
      end
      lo = base + $urandom_range(span-n, 0);
      if( lk_free(self,lo,n) ) begin
        m_lk_lo[self] = lo;
        m_lk_n[self]  = n;
        return 1'b1;
      end
    end
    return 1'b0;
  endfunction

  protected function void lk_release(int unsigned self);
    m_lk_n[self] = 0;
  endfunction

endclass

//=============================================================================
// smoke
//=============================================================================
class axlm_smoke_vseq extends axlm_base_vseq;

  `uvm_object_utils(axlm_smoke_vseq)

  function new(string name = "axlm_smoke_vseq");
    super.new(name);
  endfunction

  task body();
    bit [63:0]   wbase;
    bit [63:0]   rbase;
    int unsigned mh;
    int unsigned l3;
    int unsigned k;
    int unsigned lt;
    bit [1:0]    rsps[3];
    cmd_item     ca;
    cmd_item     cb;
    cmd_item     cc;
    wbase   = axlm_waddr(WB);
    rbase   = axlm_waddr(RB);
    mh      = MEM_DEPTH / 2;
    l3      = LWIN;
    rsps[0] = 2'b10;
    rsps[1] = 2'b11;
    rsps[2] = 2'b01;
    init_slave();
    set_ideal();

    `uvm_info("VSEQ", "phase1 : write the internal memory out, overwrite it, read it back", UVM_LOW)
    mem_fill();
    wcmd(wbase, 1'b1, 0, LWIN);
    mem_fill();
    rcmd(wbase, 1'b1, 0, LWIN);
    mem_dump();

    `uvm_info("VSEQ", "phase2 : write and read accepted in the same cycle", UVM_LOW)
    if( mh>=1 ) begin
      pair(new_cmd(1'b1, wbase, 1'b1, 0, (mh<LWIN) ? mh : LWIN), new_cmd(1'b0, rbase, 1'b1, mh, ((MEM_DEPTH-mh)<LWIN) ? (MEM_DEPTH-mh) : LWIN));
      for( int unsigned i=0; i<6; i++ ) begin
        rand_pair();
      end
      mem_dump();
    end

    `uvm_info("VSEQ", "phase3 : length / memory position corners, fixed address, WSTRB, PROT, top / bottom of the address space", UVM_LOW)
    wcmd(wbase, 1'b1, 0, 1, {STRB_W{1'b1}}, 3'b001);
    wcmd(axlm_waddr(WB + WIN - 64'd1), 1'b1, MEM_DEPTH-1, 1, {STRB_W{1'b1}}, 3'b010);
    rcmd(wbase, 1'b1, MEM_DEPTH-1, 1, 3'b100);
    if( MEM_DEPTH>=2 ) begin
      wcmd(rbase, 1'b1, MEM_DEPTH-2, 2, {STRB_W{1'b1}}, 3'b111);
      rcmd(rbase, 1'b1, MEM_DEPTH-2, 2, 3'b101);
    end
    mem_fill();
    wcmd(axlm_waddr(WB + WIN - 64'd1), 1'b0, 0, MEM_DEPTH);
    rcmd(axlm_waddr(RB + WIN - 64'd1), 1'b0, 0, MEM_DEPTH);
    for( int unsigned b=0; b<STRB_W; b++ ) begin
      mem_fill();
      wcmd(wbase, 1'b1, 0, LWIN, STRB_W'(1) << b);
    end
    wcmd(wbase, 1'b1, 0, LWIN, STRB_W'(8'b10100101));
    wcmd(wbase, 1'b1, 0, LWIN, {STRB_W{1'b0}});
    rcmd(wbase, 1'b1, 0, LWIN);
    for( int unsigned p=0; p<8; p++ ) begin
      if( mh>=1 ) begin
        pair(new_cmd(1'b1, wbase, 1'b1, 0, 1, {STRB_W{1'b1}}, 3'(p)), new_cmd(1'b0, rbase, 1'b1, mh, 1, {STRB_W{1'b0}}, 3'(7-p)));
      end else begin
        wcmd(wbase, 1'b1, 0, 1, {STRB_W{1'b1}}, 3'(p));
        rcmd(rbase, 1'b1, 0, 1, 3'(7-p));
      end
    end
    lt = (SPACE_WORDS<64'(MEM_DEPTH)) ? int'(SPACE_WORDS) : MEM_DEPTH;
    mem_fill();
    wcmd(axlm_waddr(SPACE_WORDS - 64'(lt)), 1'b1, 0, lt);
    mem_fill();
    rcmd(axlm_waddr(SPACE_WORDS - 64'(lt)), 1'b1, 0, lt);
    wcmd(axlm_waddr(SPACE_WORDS - 64'd1), 1'b0, 0, MEM_DEPTH);
    rcmd(axlm_waddr(SPACE_WORDS - 64'd1), 1'b0, 0, MEM_DEPTH);
    wcmd(axlm_waddr(64'd0), 1'b1, 0, (MEM_DEPTH>=2) ? 2 : 1);
    rcmd(axlm_waddr(64'd0), 1'b1, 0, (MEM_DEPTH>=2) ? 2 : 1);
    mem_dump();

    `uvm_info("VSEQ", "phase4 : error responses (SLVERR / DECERR / EXOKAY at the first / middle / last transaction, all, two kinds)", UVM_LOW)
    for( int unsigned e=0; e<3; e++ ) begin
      for( int unsigned q=0; q<3; q++ ) begin
        k = (q==0) ? 0 : ((q==1) ? (l3/2) : (l3-1));
        p_sequencer.cfg.clear_err();
        p_sequencer.cfg.set_werr_word(0, rsps[e], axlm_waddr(WB + 64'(k)));
        p_sequencer.cfg.set_rerr_word(0, rsps[e], axlm_waddr(RB + 64'(k)));
        mem_fill();
        wcmd(wbase, 1'b1, 0, l3);
        rcmd(rbase, 1'b1, 0, l3);
        p_sequencer.cfg.clear_err();
        wcmd(wbase, 1'b1, 0, l3);
        rcmd(rbase, 1'b1, 0, l3);
      end
    end
    p_sequencer.cfg.set_werr_word(0, 2'b10, wbase);
    p_sequencer.cfg.set_rerr_word(0, 2'b11, rbase);
    wcmd(wbase, 1'b0, 0, MEM_DEPTH);
    rcmd(rbase, 1'b0, 0, MEM_DEPTH);
    p_sequencer.cfg.clear_err();
    if( l3>=3 ) begin
      // 隣り合う 2 つのトランザクションを別の種類のエラーにする (止める構成でも、次はもう出ている)
      p_sequencer.cfg.set_werr_word(0, 2'b10, axlm_waddr(WB + 64'd1));
      p_sequencer.cfg.set_werr_word(1, 2'b11, axlm_waddr(WB + 64'd2));
      p_sequencer.cfg.set_rerr_word(0, 2'b01, axlm_waddr(RB + 64'd1));
      p_sequencer.cfg.set_rerr_word(1, 2'b10, axlm_waddr(RB + 64'd2));
      wcmd(wbase, 1'b1, 0, l3);
      rcmd(rbase, 1'b1, 0, l3);
      p_sequencer.cfg.clear_err();
    end
    mem_dump();

    `uvm_info("VSEQ", "phase5 : long latency (outstanding up to the limit), random READY / latency with the AW / W wait rules", UVM_LOW)
    p_sequencer.cfg.set_lat(MAX_WR+2, MAX_WR+6, MAX_RD+2, MAX_RD+6);
    wcmd(wbase, 1'b0, 0, MEM_DEPTH);
    rcmd(rbase, 1'b0, 0, MEM_DEPTH);
    for( int unsigned p=0; p<16; p++ ) begin
      set_rand_slave(p);
      if( (p%2)==1 ) begin
        rand_err(1'b1, 0, WB);
        rand_err(1'b0, 0, RB);
      end
      rand_pair();
      p_sequencer.cfg.clear_err();
    end
    set_ideal();
    mem_dump();

    `uvm_info("VSEQ", "phase6 : rejected / empty commands (also while the other direction is running)", UVM_LOW)
    for( int unsigned kind=0; kind<5; kind++ ) begin
      send_cmd(new_bad_cmd(1'b1, kind));
      send_cmd(new_bad_cmd(1'b0, kind));
    end
    if( mh>=1 ) begin
      ca      = new_cmd(1'b0, rbase, 1'b1, mh, ((MEM_DEPTH-mh)<LWIN) ? (MEM_DEPTH-mh) : LWIN);
      cb      = new_bad_cmd(1'b1, 3);
      cb.idle = 1;
      pair(cb, ca);
      ca      = new_cmd(1'b1, wbase, 1'b1, 0, (mh<LWIN) ? mh : LWIN);
      cb      = new_bad_cmd(1'b0, 2);
      cb.idle = 1;
      pair(ca, cb);
    end

    `uvm_info("VSEQ", "phase7 : local port (gaps, continuous, out of range, same cycle as a command, during a command, blocked)", UVM_LOW)
    mem_write(0, MEM_DEPTH, 50);
    mem_read(0, MEM_DEPTH, 50);
    mem_read(0, MEM_DEPTH, 0);
    send_loc(new_loc_wr(0, MEM_DEPTH));
    if( HAS_BAD_MEM ) begin
      mem_write(MEM_DEPTH, 1);
      mem_read(MEM_DEPTH, 1);
      mem_write((1<<MEM_AW)-1, 1);
      mem_read((1<<MEM_AW)-1, 1);
      mem_dump();
    end
    // ローカルの書き込みと読み出しを同じサイクルに
    if( mh>=1 ) begin
      begin
        loc_item it;
        it          = new_loc_wr(0, mh);
        it.rd_maddr = mh;
        it.rd_n     = MEM_DEPTH - mh;
        send_loc(it);
      end
    end
    // コマンドの受付と同じサイクル
    //   書き込みコマンド + ローカル書き込み (コマンドの先頭ワード) : 書いた後の値が送られる
    //   書き込みコマンド + ローカル読み出し / 読み出しコマンド + ローカル書き込み / 読み出しコマンド + ローカル読み出し
    fork
      begin
        wcmd(wbase, 1'b1, 0, 1);
      end
      begin
        send_loc(new_loc_wr(0, 1));
      end
    join
    fork
      begin
        wcmd(wbase, 1'b1, 0, LWIN);
      end
      begin
        send_loc(new_loc_rd(MEM_DEPTH-1, 1));
      end
    join
    if( MEM_DEPTH>=2 ) begin
      fork
        begin
          rcmd(rbase, 1'b0, 0, MEM_DEPTH-1);
        end
        begin
          send_loc(new_loc_wr(MEM_DEPTH-1, 1));
        end
      join
      fork
        begin
          rcmd(rbase, 1'b0, 0, MEM_DEPTH-1);
        end
        begin
          send_loc(new_loc_rd(MEM_DEPTH-1, 1));
        end
      join
      // コマンドの実行中 : 書き込みコマンド中のローカル書き込み / 読み出しコマンド中のローカル読み出しは受け付けられる。
      //                   書き込みコマンド中のローカル読み出し / 読み出しコマンド中のローカル書き込みは待たされる
      p_sequencer.cfg.set_lat(3, 3, 3, 3);
      fork
        begin
          wcmd(wbase, 1'b0, 0, MEM_DEPTH-1);
        end
        begin
          send_loc(new_loc_wr(MEM_DEPTH-1, 1, 0, 2));
          send_loc(new_loc_rd(MEM_DEPTH-1, 1));
        end
      join
      fork
        begin
          rcmd(rbase, 1'b0, 0, MEM_DEPTH-1);
        end
        begin
          send_loc(new_loc_rd(MEM_DEPTH-1, 1, 0, 2));
          send_loc(new_loc_wr(MEM_DEPTH-1, 1));
        end
      join
      set_ideal();
    end
    mem_dump();

    `uvm_info("VSEQ", "phase8 : next command held while busy, the other direction accepted at once", UVM_LOW)
    p_sequencer.cfg.set_lat(2, 2, 2, 2);
    mem_fill();
    ca           = new_cmd(1'b1, wbase, 1'b1, 0, (mh>=1) ? ((mh<LWIN) ? mh : LWIN) : 1);
    ca.wait_done = 1'b0;
    cb           = new_cmd(1'b1, axlm_waddr(WB + WIN - 64'd1), 1'b0, 0, 1, {STRB_W{1'b1}}, 3'b110);
    fork
      begin
        send_cmd(ca);
        send_cmd(cb);
      end
      begin
        if( mh>=1 ) begin
          cc      = new_cmd(1'b0, rbase, 1'b1, mh, 1);
          cc.idle = 3;
          send_cmd(cc);
        end
      end
    join
    ca           = new_cmd(1'b0, rbase, 1'b1, mh, (MEM_DEPTH-mh<LWIN) ? (MEM_DEPTH-mh) : LWIN);
    ca.wait_done = 1'b0;
    cb           = new_cmd(1'b0, axlm_waddr(RB + WIN - 64'd1), 1'b0, MEM_DEPTH-1, 1);
    fork
      begin
        send_cmd(ca);
        send_cmd(cb);
      end
      begin
        if( mh>=1 ) begin
          cc      = new_cmd(1'b1, wbase, 1'b1, 0, 1);
          cc.idle = 3;
          send_cmd(cc);
        end
      end
    join
    set_ideal();
    mem_dump();
  endtask

endclass

//=============================================================================
// rand
//=============================================================================
class axlm_rand_vseq extends axlm_base_vseq;

  `uvm_object_utils(axlm_rand_vseq)

  int unsigned m_num = 8;          // 1 ラウンドあたりの書き込み / 読み出しコマンドの数
  bit          m_long;             // エラー応答を置くラウンド : 長いコマンドを多めにし、内部メモリを読み書きで半分ずつ使う

  function new(string name = "axlm_rand_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned lt;
    init_slave();
    mem_fill();
    for( int unsigned rnd=0; rnd<8; rnd++ ) begin
      // ラウンド 0 / 3 / 4 / 7 はスレーブが理想的 (3 / 7 はエラー応答もあり、止めるまでに出す数を正確に照合する)
      if( ((rnd%4)==0)||((rnd%4)==3) ) begin
        set_ideal();
      end else begin
        set_rand_slave(rnd);
      end
      p_sequencer.cfg.clear_err();
      // 奇数ラウンドはエラー応答を置く。範囲 0 の応答の種類はラウンドごとに回し
      // (SLVERR / DECERR / EXOKAY)、範囲 1 は乱数。コマンドの途中でエラーになるよう、長いコマンドを多めにする
      m_long = ((rnd%2)==1);
      if( m_long ) begin
        rand_err(1'b1, 0, WB, f_resp(rnd/2));
        rand_err(1'b1, 1, WB);
        rand_err(1'b0, 0, RB, f_resp((rnd/2)+1));
        rand_err(1'b0, 1, RB);
      end
      `uvm_info("VSEQ", $sformatf("round %0d : %0d write / %0d read commands and local accesses at the same time, slave : %s", rnd, m_num, m_num, p_sequencer.cfg.convert2string()), UVM_LOW)
      fork
        begin
          cmd_thread(1'b1);
        end
        begin
          cmd_thread(1'b0);
        end
        begin
          loc_thread();
        end
      join
      p_sequencer.cfg.clear_err();
      mem_dump();
    end
    set_ideal();
    `uvm_info("VSEQ", "final : rejected / empty commands, commands that end exactly at the top of the address space", UVM_LOW)
    for( int unsigned kind=0; kind<5; kind++ ) begin
      send_cmd(new_bad_cmd(1'b1, kind));
      send_cmd(new_bad_cmd(1'b0, kind));
    end
    for( int unsigned i=0; i<4; i++ ) begin
      lt = $urandom_range((SPACE_WORDS<64'(MEM_DEPTH)) ? int'(SPACE_WORDS) : MEM_DEPTH, 1);
      wcmd(axlm_waddr(SPACE_WORDS - 64'(lt)), 1'b1, 0, lt, {STRB_W{1'b1}}, 3'($urandom()));
      rcmd(axlm_waddr(SPACE_WORDS - 64'(lt)), 1'b1, 0, lt, 3'($urandom()));
    end
    mem_dump();
  endtask

  // SLVERR / DECERR / EXOKAY を順に
  protected function bit [1:0] f_resp(int unsigned i);
    case( i%3 )
      0 : begin
        return 2'b10;
      end
      1 : begin
        return 2'b11;
      end
      default : begin
        return 2'b01;
      end
    endcase
  endfunction

  // 内部メモリの空いている範囲で、ランダムなコマンドを m_num 本 (1 割は誤り / 0 ワード)
  protected task cmd_thread(bit wr);
    cmd_item     c;
    int unsigned self;
    int unsigned base;
    int unsigned span;
    int unsigned lo;
    int unsigned n;
    self = wr ? 0 : 1;
    // エラー応答を置くラウンドでは、書き込みは内部メモリの前半、読み出しは後半を使う (どちらも長いコマンドを出せるように)
    base = 0;
    span = MEM_DEPTH;
    if( m_long&&(MEM_DEPTH>=2) ) begin
      base = wr ? 0 : (MEM_DEPTH/2);
      span = wr ? (MEM_DEPTH/2) : (MEM_DEPTH-(MEM_DEPTH/2));
    end
    for( int unsigned i=0; i<m_num; i++ ) begin
      if( ($urandom_range(9,0)!=0)&&lk_take(self,base,span,span,lo,n,m_long) ) begin
        c = new_rand_cmd(wr, lo, n, wr ? WB : RB, LWIN);
      end else begin
        c = new_bad_cmd(wr, $urandom_range(4,0));
      end
      c.idle = ($urandom_range(1,0)==0) ? 0 : $urandom_range(3,1);
      send_cmd(c);
      lk_release(self);
    end
  endtask

  // ローカルポートの書き込み / 読み出し (1〜4 ワード、範囲外も混ぜる)
  protected task loc_thread();
    loc_item     it;
    int unsigned lo;
    int unsigned n;
    int unsigned nmax;
    nmax = (MEM_DEPTH<4) ? MEM_DEPTH : 4;
    for( int unsigned i=0; i<m_num; i++ ) begin
      if( HAS_BAD_MEM&&($urandom_range(9,0)==0) ) begin
        lo = $urandom_range((1<<MEM_AW)-1, MEM_DEPTH);
        if( $urandom_range(1,0)==0 ) begin
          it = new_loc_wr(lo, 1, 0, $urandom_range(3,0));
        end else begin
          it = new_loc_rd(lo, 1, 0, $urandom_range(3,0));
        end
        send_loc(it);
      end else if( lk_take(2,0,MEM_DEPTH,nmax,lo,n) ) begin
        if( $urandom_range(1,0)==0 ) begin
          it = new_loc_wr(lo, n, $urandom_range(1,0)*30, $urandom_range(3,0));
        end else begin
          it = new_loc_rd(lo, n, $urandom_range(1,0)*30, $urandom_range(3,0));
        end
        send_loc(it);
        lk_release(2);
      end else begin
        it = new_loc_rd(0, 0, 0, 1);
        send_loc(it);
      end
    end
  endtask

endclass
