//=============================================================================
// apbm_seq_lib.svh
//-----------------------------------------------------------------------------
//  usr_single_seq  : 操作 1 つをユーザ側 sequencer に流す
//  apbm_base_vseq  : 仮想シーケンスの共通処理
//                    (内部メモリの書き込み / 読み出し、コマンド、スレーブ設定の切り替え)
//  apbm_smoke_vseq : 代表パターン (基本 / 端 / 各スレーブ / ウェイト / PSLVERR /
//                    タイムアウト / コマンド誤り / ローカルポート / アドレス空間の末尾)
//  apbm_rand_vseq  : ランダムなコマンドを、スレーブの振る舞いを変えながら流す。
//                    続けて PSLVERR / タイムアウトの注入、断るコマンド
//
//  スレーブの設定 (cfg[]) は、コマンドが完了してから変える
//  (scoreboard / coverage は受付時の設定を使う)。
//=============================================================================

class usr_single_seq extends uvm_sequence #(usr_item);

  `uvm_object_utils(usr_single_seq)

  usr_item m_item;

  function new(string name = "usr_single_seq");
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
class apbm_base_vseq extends uvm_sequence;

  `uvm_object_utils(apbm_base_vseq)
  `uvm_declare_p_sequencer(apbm_vsequencer)

  // 指定テストで使う先頭ワード位置 (アドレス空間に余裕があれば 0 以外にする)
  localparam int unsigned BASE_W = (SPACE_WORDS>=(64'(LMAX)+64'd8)) ? 4 : 0;

  function new(string name = "apbm_base_vseq");
    super.new(name);
  endfunction

  protected task send(usr_item it);
    usr_single_seq s;
    s        = usr_single_seq::type_id::create("s");
    s.m_item = it;
    s.start(p_sequencer.usr_sqr, this);
  endtask

  //---------------------------------------------------------------------------
  // スレーブ
  //---------------------------------------------------------------------------
  // スレーブのメモリに初期値を入れる (最初のコマンドより前に呼ぶ)
  protected function void init_slaves();
    for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
      p_sequencer.smem.fill_random(s, 64'd0, 64);
      if( SPACE_WORDS>=(64'(MEM_DEPTH)+64'd68) ) begin
        p_sequencer.smem.fill_random(s, SPACE_WORDS - 64'(MEM_DEPTH) - 64'd4, MEM_DEPTH + 4);
      end
    end
  endfunction

  protected function void set_wait(int unsigned lo, int unsigned hi);
    for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
      p_sequencer.cfg[s].set_wait(lo, hi);
    end
  endfunction

  protected function void clear_err();
    for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
      p_sequencer.cfg[s].clear_err();
    end
  endfunction

  //---------------------------------------------------------------------------
  // 内部メモリのローカルポート
  //---------------------------------------------------------------------------
  // maddr から n ワードに乱数を書く
  protected task mem_write(int unsigned maddr, int unsigned n, int unsigned gap_pct = 0);
    usr_item         it;
    bit [DATA_W-1:0] d;
    it         = usr_item::type_id::create("mw");
    it.op      = OP_MEM_WR;
    it.maddr   = maddr;
    it.gap_pct = gap_pct;
    for( int unsigned i=0; i<n; i++ ) begin
      for( int unsigned b=0; b<DATA_W; b++ ) begin
        d[b] = 1'($urandom());
      end
      it.data.push_back(d);
    end
    send(it);
  endtask

  // maddr から n ワード読む (読めたデータは scoreboard が照合する)
  protected task mem_read(int unsigned maddr, int unsigned n, int unsigned gap_pct = 0);
    usr_item it;
    it         = usr_item::type_id::create("mr");
    it.op      = OP_MEM_RD;
    it.maddr   = maddr;
    it.n       = n;
    it.gap_pct = gap_pct;
    send(it);
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
  // コマンドを流し、完了後に内部メモリを全ワード読む
  protected task run_cmd(usr_item c, bit dump = 1'b1);
    send(c);
    `uvm_info("VSEQ", $sformatf("%s [slave %0d: %s] -> err_flags=%b err_index=%0d done_count=%0d", c.convert2string(), c.sel, (c.sel<NUM_SLAVES) ? p_sequencer.cfg[c.sel].convert2string() : "-", c.err_flags, c.err_index, c.done_count), UVM_MEDIUM)
    if( dump ) begin
      mem_dump();
    end
  endtask

  // 指定したコマンド
  protected task cmd_fixed
  (
    bit              wr
   ,int unsigned     sel
   ,bit [63:0]       addr
   ,bit              incr
   ,int unsigned     maddr
   ,int unsigned     len
   ,bit [STRB_W-1:0] strb = {STRB_W{1'b1}}
   ,bit [2:0]        prot = 3'b000
   ,bit              dump = 1'b1
  );
    usr_item c;
    c = usr_item::type_id::create("c");
    c.set_cmd(wr, sel, addr, incr, maddr, len, strb, prot);
    run_cmd(c, dump);
  endtask

  // 指定したコマンド (インクリメント、全バイト) と同じサイクルに、ローカルポートで 1 ワード書く / 読む
  protected task cmd_with_mem
  (
    bit          wr
   ,int unsigned sel
   ,bit [63:0]   addr
   ,int unsigned maddr
   ,int unsigned len
   ,bit          mem_wr
   ,int unsigned mem_addr
  );
    usr_item c;
    c = usr_item::type_id::create("cm");
    c.set_cmd(wr, sel, addr, 1'b1, maddr, len, {STRB_W{1'b1}}, 3'b000);
    c.with_mem      = 1'b1;
    c.with_mem_wr   = mem_wr;
    c.with_mem_addr = mem_addr;
    for( int unsigned b=0; b<DATA_W; b++ ) begin
      c.with_mem_data[b] = 1'($urandom());
    end
    run_cmd(c);
  endtask

  // 制約付きランダムな (有効な) コマンドを 1 本作る
  protected function usr_item new_rand_cmd(string name = "c");
    usr_item c;
    bit      ok;
    c  = usr_item::type_id::create(name);
    ok = c.randomize();
    if( !ok ) begin
      `uvm_error("RAND", "usr_item randomize failed")
    end
    return c;
  endfunction

  // ランダムなコマンドを n 本。8 本に 1 回、内部メモリを書き直す。
  // 4 本に 1 本は、コマンドと同じサイクルにローカルポートも読み書きする
  protected task cmd_rand(int unsigned n);
    usr_item c;
    for( int unsigned i=0; i<n; i++ ) begin
      if( (i%8)==0 ) begin
        mem_fill();
      end
      c = new_rand_cmd($sformatf("c%0d", i));
      if( $urandom_range(3,0)==0 ) begin
        c.with_mem      = 1'b1;
        c.with_mem_wr   = 1'($urandom());
        c.with_mem_addr = $urandom_range(MEM_DEPTH-1, 0);
        for( int unsigned b=0; b<DATA_W; b++ ) begin
          c.with_mem_data[b] = 1'($urandom());
        end
      end
      run_cmd(c);
    end
  endtask

  // ランダムなコマンドの 1 転送をエラーにする
  //   pos  : 0 = 先頭 / 1 = 中間 / 2 = 最後 / 3 = ランダム
  //   hang : 1 = PREADY を返さない (タイムアウト) / 0 = PSLVERR
  protected task cmd_err(int unsigned pos, bit hang);
    usr_item     c;
    int unsigned k;
    bit [63:0]   a;
    c = new_rand_cmd("e");
    // 位置を区別できるよう、できるだけ 3 ワード以上のインクリメントにする
    if( (LMAX>=3)&&((c.len<3)||!c.incr) ) begin
      c.incr  = 1'b1;
      c.len   = $urandom_range(LMAX, 3);
      c.maddr = MEM_DEPTH - c.len;
      c.addr  = apbm_waddr(64'(BASE_W));
    end
    case( pos )
      0 : begin
        k = 0;
      end
      1 : begin
        k = c.len / 2;
      end
      2 : begin
        k = c.len - 1;
      end
      default : begin
        k = $urandom_range(c.len-1, 0);
      end
    endcase
    a = apbm_xaddr(c.addr, c.incr, k);
    if( hang ) begin
      p_sequencer.cfg[c.sel].set_hang_word(a);
    end else begin
      p_sequencer.cfg[c.sel].set_err_word(a);
    end
    run_cmd(c);
    p_sequencer.cfg[c.sel].clear_err();
  endtask

  // ランダムな固定アドレスのコマンドで、そのワードをエラーにする (全ての転送が PSLVERR になる)
  protected task cmd_err_all();
    usr_item c;
    c      = new_rand_cmd("ea");
    c.incr = 1'b0;
    if( (c.len<2)&&(MEM_DEPTH>=2) ) begin
      c.len   = 2;
      c.maddr = 0;
    end
    p_sequencer.cfg[c.sel].set_err_word(c.addr);
    run_cmd(c);
    p_sequencer.cfg[c.sel].clear_err();
  endtask

  // DUT が断るべきコマンド / 何もしないコマンド
  //   kind 0: 0 ワード / 1: 0 ワード (他の項目も誤り) / 2: メモリ範囲超え / 3: アドレス範囲超え /
  //        4: 非アライン (データ幅 8bit の構成ではメモリ範囲超え) /
  //        5: 存在しないスレーブ番号 (表せない構成ではアドレス範囲超え)
  protected task cmd_bad(int unsigned kind);
    usr_item c;
    c = new_rand_cmd("b");
    case( kind )
      0 : begin
        c.len = 0;
      end
      1 : begin
        c.len   = 0;
        c.maddr = MEM_DEPTH - 1;
        c.addr  = apbm_waddr(SPACE_WORDS - 64'd1) + 64'(STRB_W-1);
        c.incr  = 1'b1;
        c.sel   = (1<<SEL_W) - 1;
      end
      2 : begin
        make_mem_bad(c);
      end
      3 : begin
        make_range_bad(c);
      end
      4 : begin
        if( STRB_W>1 ) begin
          c.addr = c.addr + 64'($urandom_range(STRB_W-1, 1));
        end else begin
          make_mem_bad(c);
        end
      end
      default : begin
        if( HAS_BAD_SEL ) begin
          c.sel = $urandom_range((1<<SEL_W)-1, NUM_SLAVES);
        end else begin
          make_range_bad(c);
        end
      end
    endcase
    run_cmd(c);
  endtask

  // メモリ範囲を 1 ワードだけ超えるコマンドにする
  //   (cmd_mem_addr のビット幅に収まるよう、MEM_DEPTH が 2 以上なら 2 ワード以上にする)
  protected function void make_mem_bad(usr_item c);
    if( (c.len<2)&&(MEM_DEPTH>=2) ) begin
      c.len = 2;
    end
    c.maddr = MEM_DEPTH - c.len + 1;
  endfunction

  // アドレス空間の末尾を 1 ワードだけ超えるコマンドにする
  //   (アドレスが ADDR_W ビットに収まるよう、2 ワード以上にする)
  protected function void make_range_bad(usr_item c);
    c.incr = 1'b1;
    if( c.len<2 ) begin
      c.len = 2;
    end
    if( (c.maddr+c.len)>MEM_DEPTH ) begin
      c.maddr = MEM_DEPTH - c.len;
    end
    c.addr = apbm_waddr(SPACE_WORDS - 64'(c.len) + 64'd1);
  endfunction

endclass

//=============================================================================
// smoke
//=============================================================================
class apbm_smoke_vseq extends apbm_base_vseq;

  `uvm_object_utils(apbm_smoke_vseq)

  function new(string name = "apbm_smoke_vseq");
    super.new(name);
  endfunction

  task body();
    bit [63:0]   base;
    int unsigned l3;
    int unsigned k;
    base = apbm_waddr(64'(BASE_W));
    l3   = (LMAX>=3) ? LMAX : 1;
    init_slaves();

    `uvm_info("VSEQ", "phase1 : write the whole internal memory, overwrite it, read it back", UVM_LOW)
    set_wait(0, 0);
    mem_fill();
    cmd_fixed(1'b1, 0, base, 1'b1, 0, LMAX);
    mem_fill();
    cmd_fixed(1'b0, 0, base, 1'b1, 0, LMAX, {STRB_W{1'b0}});

    `uvm_info("VSEQ", "phase2 : length / memory position corners, fixed address, PSTRB, PPROT", UVM_LOW)
    cmd_fixed(1'b1, 0, base, 1'b1, 0, 1, {STRB_W{1'b1}}, 3'b001);
    cmd_fixed(1'b1, 0, base, 1'b1, MEM_DEPTH-1, 1, {STRB_W{1'b1}}, 3'b010);
    cmd_fixed(1'b0, 0, base, 1'b0, MEM_DEPTH-1, 1, {STRB_W{1'b0}}, 3'b100);
    cmd_fixed(1'b1, 0, base, 1'b0, 0, MEM_DEPTH);
    cmd_fixed(1'b0, 0, base, 1'b0, 0, MEM_DEPTH);
    for( int unsigned b=0; b<STRB_W; b++ ) begin
      mem_fill();
      cmd_fixed(1'b1, 0, base, 1'b1, 0, LMAX, STRB_W'(1) << b, 3'b000, 1'b0);
    end
    cmd_fixed(1'b1, 0, base, 1'b1, 0, LMAX, {STRB_W{1'b0}});
    for( int unsigned p=0; p<8; p++ ) begin
      cmd_fixed(p[0], 0, base, 1'b1, 0, 1, {STRB_W{1'b1}}, 3'(p), 1'b0);
    end

    `uvm_info("VSEQ", "phase3 : each slave", UVM_LOW)
    for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
      mem_fill();
      cmd_fixed(1'b1, s, base, 1'b1, 0, LMAX, {STRB_W{1'b1}}, 3'b000, 1'b0);
    end
    for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
      mem_fill();
      cmd_fixed(1'b0, s, base, 1'b1, 0, LMAX);
    end

    `uvm_info("VSEQ", "phase4 : wait states", UVM_LOW)
    set_wait(0, WAIT_MAX);
    mem_fill();
    cmd_fixed(1'b1, NUM_SLAVES-1, base, 1'b1, 0, LMAX);
    cmd_fixed(1'b0, NUM_SLAVES-1, base, 1'b1, 0, LMAX);
    set_wait(WAIT_MAX, WAIT_MAX);
    cmd_fixed(1'b1, 0, base, 1'b1, 0, LMAX);
    cmd_fixed(1'b0, 0, base, 1'b1, 0, LMAX);

    `uvm_info("VSEQ", "phase5 : PSLVERR at the first / middle / last transfer, at every transfer", UVM_LOW)
    for( int unsigned pos=0; pos<3; pos++ ) begin
      k = (pos==0) ? 0 : ((pos==1) ? (l3/2) : (l3-1));
      set_wait(0, (pos==1) ? WAIT_MAX : 0);
      p_sequencer.cfg[0].set_err_word(apbm_waddr(64'(BASE_W) + 64'(k)));
      mem_fill();
      cmd_fixed(1'b1, 0, base, 1'b1, 0, l3);
      cmd_fixed(1'b0, 0, base, 1'b1, 0, l3);
      clear_err();
      cmd_fixed(1'b0, 0, base, 1'b1, 0, l3);
    end
    // 全ての転送が PSLVERR になる (固定アドレスで、そのワードがエラー)。
    // STOP_ON_ERROR=0 では最後まで続き、err_index は最初のエラー (0) のまま
    set_wait(0, 0);
    p_sequencer.cfg[0].set_err_word(base);
    mem_fill();
    cmd_fixed(1'b1, 0, base, 1'b0, 0, MEM_DEPTH);
    cmd_fixed(1'b0, 0, base, 1'b0, 0, MEM_DEPTH);
    clear_err();

    if( TIMEOUT_CYCLES>0 ) begin
      `uvm_info("VSEQ", "phase6 : timeout (wait = limit, wait = limit + 1, no response)", UVM_LOW)
      set_wait(TIMEOUT_CYCLES-1, TIMEOUT_CYCLES-1);
      mem_fill();
      cmd_fixed(1'b1, 0, base, 1'b1, 0, l3);
      cmd_fixed(1'b0, 0, base, 1'b1, 0, l3);
      set_wait(TIMEOUT_CYCLES, TIMEOUT_CYCLES);
      cmd_fixed(1'b1, 0, base, 1'b1, 0, l3);
      cmd_fixed(1'b0, 0, base, 1'b1, 0, l3);
      for( int unsigned pos=0; pos<3; pos++ ) begin
        k = (pos==0) ? 0 : ((pos==1) ? (l3/2) : (l3-1));
        set_wait(0, WAIT_MAX);
        p_sequencer.cfg[NUM_SLAVES-1].set_hang_word(apbm_waddr(64'(BASE_W) + 64'(k)));
        mem_fill();
        cmd_fixed(1'b1, NUM_SLAVES-1, base, 1'b1, 0, l3);
        cmd_fixed(1'b0, NUM_SLAVES-1, base, 1'b1, 0, l3);
        clear_err();
        cmd_fixed(1'b0, NUM_SLAVES-1, base, 1'b1, 0, l3);
      end
    end

    `uvm_info("VSEQ", "phase7 : rejected / empty commands", UVM_LOW)
    set_wait(0, 0);
    for( int unsigned kind=0; kind<6; kind++ ) begin
      cmd_bad(kind);
    end
    cmd_fixed(1'b0, 0, base, 1'b1, 0, LMAX);

    `uvm_info("VSEQ", "phase8 : local port (gaps, out-of-range address, access in the same cycle as a command)", UVM_LOW)
    mem_write(0, MEM_DEPTH, 50);
    mem_read(0, MEM_DEPTH, 50);
    mem_read(0, MEM_DEPTH, 0);
    if( HAS_BAD_MEM ) begin
      mem_write(MEM_DEPTH, 1);
      mem_read(MEM_DEPTH, 1);
      mem_write((1<<MEM_AW)-1, 1);
      mem_read((1<<MEM_AW)-1, 1);
      mem_dump();
    end
    // コマンドと同じサイクルのローカルアクセス
    //   書き込み : コマンドが送るワード (ワード 0) を同じサイクルに書き換える → バスには書き換えた後の値が出る
    //   読み出し : 次のサイクルに元の値が返る (書き込みコマンド / 読み出しコマンドのどちらでも)
    //   読み出しコマンドと同じサイクルの書き込み : 後からコマンドが同じワードを上書きする
    mem_fill();
    cmd_with_mem(1'b1, 0, base, 0, 1, 1'b1, 0);
    cmd_with_mem(1'b1, 0, base, 0, LMAX, 1'b0, MEM_DEPTH-1);
    cmd_with_mem(1'b0, 0, base, 0, LMAX, 1'b0, MEM_DEPTH-1);
    cmd_with_mem(1'b0, 0, base, 0, LMAX, 1'b1, MEM_DEPTH-1);

    `uvm_info("VSEQ", "phase9 : top of the address space", UVM_LOW)
    set_wait(0, WAIT_MAX);
    mem_fill();
    cmd_fixed(1'b1, 0, apbm_waddr(SPACE_WORDS - 64'(LMAX)), 1'b1, 0, LMAX);
    cmd_fixed(1'b0, 0, apbm_waddr(SPACE_WORDS - 64'(LMAX)), 1'b1, 0, LMAX);
    cmd_fixed(1'b1, 0, apbm_waddr(SPACE_WORDS - 64'd1), 1'b0, 0, MEM_DEPTH);
    cmd_fixed(1'b0, 0, apbm_waddr(SPACE_WORDS - 64'd1), 1'b0, 0, MEM_DEPTH);
    set_wait(0, 0);
  endtask

endclass

//=============================================================================
// rand
//=============================================================================
class apbm_rand_vseq extends apbm_base_vseq;

  `uvm_object_utils(apbm_rand_vseq)

  int unsigned m_num = 8;

  function new(string name = "apbm_rand_vseq");
    super.new(name);
  endfunction

  task body();
    // {ウェイトの下限, 上限} (上限は WAIT_MAX で頭打ち)
    int unsigned lo_tbl[4] = '{0, 0, 1, 99};
    int unsigned hi_tbl[4] = '{0, 99, 2, 99};
    int unsigned lo;
    int unsigned hi;
    init_slaves();
    for( int unsigned p=0; p<4; p++ ) begin
      lo = (lo_tbl[p]>WAIT_MAX) ? WAIT_MAX : lo_tbl[p];
      hi = (hi_tbl[p]>WAIT_MAX) ? WAIT_MAX : hi_tbl[p];
      `uvm_info("VSEQ", $sformatf("phase%0d : %0d random commands, wait states %0d..%0d", p+1, m_num, lo, hi), UVM_LOW)
      set_wait(lo, hi);
      cmd_rand(m_num);
    end

    `uvm_info("VSEQ", "phase5 : PSLVERR injection", UVM_LOW)
    set_wait(0, WAIT_MAX);
    mem_fill();
    for( int unsigned i=0; i<m_num; i++ ) begin
      cmd_err(i%4, 1'b0);
    end
    cmd_err_all();
    cmd_err_all();

    if( TIMEOUT_CYCLES>0 ) begin
      `uvm_info("VSEQ", "phase6 : timeout injection", UVM_LOW)
      mem_fill();
      for( int unsigned i=0; i<m_num; i++ ) begin
        cmd_err(i%4, 1'b1);
      end
      set_wait(TIMEOUT_CYCLES, TIMEOUT_CYCLES);
      cmd_rand(2);
    end

    `uvm_info("VSEQ", "phase7 : rejected / empty commands", UVM_LOW)
    set_wait(0, WAIT_MAX);
    for( int unsigned kind=0; kind<6; kind++ ) begin
      cmd_bad(kind);
    end
    set_wait(0, 0);
    cmd_rand(1);
  endtask

endclass
