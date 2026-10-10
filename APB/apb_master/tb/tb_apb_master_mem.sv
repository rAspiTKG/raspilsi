//=============================================================================
// tb_apb_master_mem.sv
//-----------------------------------------------------------------------------
//  apb_master_mem の簡易テストベンチ (自己チェック)。
//
//  構成:
//    コマンド / ローカルポート --> apb_master_mem --> apb_slave_mem_model (NUM_SLAVES 個ぶん)
//
//  コマンドごとの確認 (run_cmd):
//    - done_err / err_flags / err_index / done_count が期待どおり
//    - 受付から done までのサイクル数が期待どおり (転送しないコマンドは 1 サイクル。
//      転送するコマンドは 書き込み 4 / 読み出し 3 + 各転送の SETUP 1 + ACCESS (1 + ウェイト数)。
//      打ち切った転送は SETUP 1 + ACCESS TIMEOUT_CYCLES)
//    - 転送が IDLE を挟まずに続くこと (2 本目以降の転送は全て、前の転送の直後に始まる)
//    - バス上の転送の列 (スレーブ番号 / アドレス / 方向 / PWDATA / PSTRB / PPROT / PSLVERR) が
//      期待どおりで、余分な転送が無い
//    - 書き込み : スレーブのメモリが期待値 (PSTRB のバイトだけ更新、エラーの転送は反映しない)
//    - 読み出し : 内部メモリが期待値 (エラーの転送のワードは元の値のまま)
//    - 内部メモリの全ワードをローカルポートで読み直して照合
//  常時の確認:
//    - busy / cmd_ready / mem_ready / done の関係、mem_rvalid のタイミング
//    - PSEL が同時に 2 本立たない、PENABLE=1 のとき PSEL がちょうど 1 本
//    - スレーブモデルのプロトコルチェック 0 件、非アラインの PADDR 0 件、
//      打ち切った転送数 == タイムアウトの期待数、内部メモリの範囲外アクセス 0 件
//
//  parameter は Verilator の -G で上書きできる。
//=============================================================================
`timescale 1ns / 1ps

module tb_apb_master_mem #(
  parameter int unsigned ADDR_WIDTH     = 32
 ,parameter int unsigned DATA_WIDTH     = 32
 ,parameter int unsigned NUM_SLAVES     = 1
 ,parameter int unsigned MEM_DEPTH      = 16
 ,parameter int unsigned TIMEOUT_CYCLES = 0
 ,parameter bit          STOP_ON_ERROR  = 1'b1
 ,parameter int unsigned N_RAND         = 200
);

  localparam int unsigned STRB_W  = DATA_WIDTH / 8;
  localparam int unsigned SEL_W   = (NUM_SLAVES<2) ? 1 : $clog2(NUM_SLAVES);
  localparam int unsigned MEM_AW  = (MEM_DEPTH<2) ? 1 : $clog2(MEM_DEPTH);
  localparam int unsigned LEN_W   = $clog2(MEM_DEPTH+1);

  // アドレス空間の大きさ
  localparam longint unsigned SPACE_BYTES = 64'd1 << ADDR_WIDTH;
  localparam longint unsigned SPACE_WORDS = SPACE_BYTES / 64'(STRB_W);
  // 有効なコマンドで使える最大ワード数
  localparam int unsigned LMAX    = (SPACE_WORDS<64'(MEM_DEPTH)) ? int'(SPACE_WORDS) : MEM_DEPTH;
  // 指定テストで使う先頭ワード位置 (アドレス空間に余裕があれば 0 以外にする)
  localparam int unsigned BASE_W  = (SPACE_WORDS>=(64'(LMAX)+64'd8)) ? 4 : 0;
  // 存在しないスレーブ番号 / 範囲外のメモリアドレスを表せるか
  localparam bit          HAS_BAD_SEL = ((1<<SEL_W)>NUM_SLAVES);
  localparam bit          HAS_BAD_MEM = ((1<<MEM_AW)>MEM_DEPTH);
  // ランダムウェイトの上限 (タイムアウトさせない範囲)
  localparam int unsigned WAIT_MAX    = (TIMEOUT_CYCLES==0) ? 4 : ((TIMEOUT_CYCLES>4) ? 4 : (TIMEOUT_CYCLES-1));
  localparam int unsigned HANG_LIMIT  = 200000;

  //---------------------------------------------------------------------------
  // クロック / リセット
  //---------------------------------------------------------------------------
  logic pclk;
  logic presetn;

  initial begin
    pclk = 1'b0;
    forever begin
      #5 pclk = ~pclk;
    end
  end

  //---------------------------------------------------------------------------
  // DUT
  //---------------------------------------------------------------------------
  logic                               cmd_valid;
  logic                               cmd_ready;
  logic                               cmd_write;
  logic [SEL_W-1:0]                   cmd_sel;
  logic [ADDR_WIDTH-1:0]              cmd_addr;
  logic                               cmd_incr;
  logic [MEM_AW-1:0]                  cmd_mem_addr;
  logic [LEN_W-1:0]                   cmd_len;
  logic [STRB_W-1:0]                  cmd_strb;
  logic [2:0]                         cmd_prot;
  logic                               busy;
  logic                               done;
  logic                               done_err;
  logic [2:0]                         err_flags;
  logic [LEN_W-1:0]                   err_index;
  logic [LEN_W-1:0]                   done_count;
  logic                               mem_valid;
  logic                               mem_ready;
  logic                               mem_write;
  logic [MEM_AW-1:0]                  mem_addr;
  logic [DATA_WIDTH-1:0]              mem_wdata;
  logic                               mem_rvalid;
  logic [DATA_WIDTH-1:0]              mem_rdata;
  logic [ADDR_WIDTH-1:0]              paddr;
  logic [2:0]                         pprot;
  logic [NUM_SLAVES-1:0]              psel;
  logic                               penable;
  logic                               pwrite;
  logic [DATA_WIDTH-1:0]              pwdata;
  logic [STRB_W-1:0]                  pstrb;
  logic [NUM_SLAVES-1:0]              pready;
  logic [(NUM_SLAVES*DATA_WIDTH)-1:0] prdata;
  logic [NUM_SLAVES-1:0]              pslverr;

  apb_master_mem #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.NUM_SLAVES(NUM_SLAVES)
   ,.MEM_DEPTH(MEM_DEPTH)
   ,.TIMEOUT_CYCLES(TIMEOUT_CYCLES)
   ,.STOP_ON_ERROR(STOP_ON_ERROR)
  ) u_dut (
    .pclk(pclk)
   ,.presetn(presetn)
   ,.cmd_valid(cmd_valid)
   ,.cmd_ready(cmd_ready)
   ,.cmd_write(cmd_write)
   ,.cmd_sel(cmd_sel)
   ,.cmd_addr(cmd_addr)
   ,.cmd_incr(cmd_incr)
   ,.cmd_mem_addr(cmd_mem_addr)
   ,.cmd_len(cmd_len)
   ,.cmd_strb(cmd_strb)
   ,.cmd_prot(cmd_prot)
   ,.busy(busy)
   ,.done(done)
   ,.done_err(done_err)
   ,.err_flags(err_flags)
   ,.err_index(err_index)
   ,.done_count(done_count)
   ,.mem_valid(mem_valid)
   ,.mem_ready(mem_ready)
   ,.mem_write(mem_write)
   ,.mem_addr(mem_addr)
   ,.mem_wdata(mem_wdata)
   ,.mem_rvalid(mem_rvalid)
   ,.mem_rdata(mem_rdata)
   ,.paddr(paddr)
   ,.pprot(pprot)
   ,.psel(psel)
   ,.penable(penable)
   ,.pwrite(pwrite)
   ,.pwdata(pwdata)
   ,.pstrb(pstrb)
   ,.pready(pready)
   ,.prdata(prdata)
   ,.pslverr(pslverr)
  );

  apb_slave_mem_model #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.NUM_SLAVES(NUM_SLAVES)
  ) u_slv (
    .pclk(pclk)
   ,.presetn(presetn)
   ,.paddr(paddr)
   ,.pprot(pprot)
   ,.psel(psel)
   ,.penable(penable)
   ,.pwrite(pwrite)
   ,.pwdata(pwdata)
   ,.pstrb(pstrb)
   ,.pready(pready)
   ,.prdata(prdata)
   ,.pslverr(pslverr)
  );

  //---------------------------------------------------------------------------
  // エラー集計
  //---------------------------------------------------------------------------
  int unsigned err_cnt;
  int unsigned mon_err_cnt;
  int unsigned cyc;               // これまでに来た posedge の数

  task automatic tb_error( input string msg );
    err_cnt++;
    $display("[%0t] [ERROR] %s", $time, msg);
  endtask

  task automatic abort_test( input string msg );
    $display("[%0t] [ERROR] %s", $time, msg);
    $display("=== tb_apb_master_mem : TEST FAILED (aborted) ===");
    $finish;
  endtask

  always @(posedge pclk) begin
    cyc <= cyc + 1;
  end

  //---------------------------------------------------------------------------
  // 期待値
  //---------------------------------------------------------------------------
  bit [DATA_WIDTH-1:0] ref_mem [MEM_DEPTH];          // 内部メモリの期待値
  bit [DATA_WIDTH-1:0] exp_smem [bit [63:0]];        // スレーブのメモリの期待値 ({スレーブ番号, アドレス})

  // 統計
  int unsigned n_cmd;
  int unsigned n_cmd_wr;
  int unsigned n_cmd_rd;
  int unsigned n_cmd_bad;
  int unsigned n_cmd_empty;
  int unsigned n_cmd_slverr;
  int unsigned n_cmd_timeout;
  int unsigned n_xfer_exp;
  int unsigned n_abort_exp;
  // run_cmd が最後に測った値
  int unsigned last_acc_cyc;
  int unsigned last_done_cyc;
  int unsigned last_acc_b2b;      // 受付時点の u_slv.n_b2b
  // ウェイトだけで全転送がタイムアウトする設定にしている (wait_min == wait_max >= TIMEOUT_CYCLES)
  bit          wait_times_out;

  function automatic bit [63:0] f_key( input int unsigned s, input bit [ADDR_WIDTH-1:0] a );
    return {32'(s), 32'(a)};
  endfunction

  function automatic bit [DATA_WIDTH-1:0] f_smem( input int unsigned s, input bit [ADDR_WIDTH-1:0] a );
    if( exp_smem.exists(f_key(s,a)) ) begin
      return exp_smem[f_key(s, a)];
    end
    return {DATA_WIDTH{1'b0}};
  endfunction

  function automatic bit [DATA_WIDTH-1:0] f_rand_data();
    bit [DATA_WIDTH-1:0] d;
    for( int unsigned i=0; i<DATA_WIDTH; i++ ) begin
      d[i] = 1'($urandom());
    end
    return d;
  endfunction

  // ワード位置 → アドレス
  function automatic bit [ADDR_WIDTH-1:0] f_waddr( input longint unsigned w );
    return ADDR_WIDTH'(w * STRB_W);
  endfunction

  // コマンドの i 番目の転送のアドレス
  function automatic bit [ADDR_WIDTH-1:0] f_xaddr( input bit [ADDR_WIDTH-1:0] addr, input bit incr, input int unsigned i );
    if( incr ) begin
      return addr + ADDR_WIDTH'(i * STRB_W);
    end
    return addr;
  endfunction

  // DUT が err_flags[2] で断るべきコマンドか
  function automatic bit f_cmd_bad( input int unsigned sel, input bit [ADDR_WIDTH-1:0] addr, input bit incr, input int unsigned maddr, input int unsigned len );
    bit sel_bad;
    bit mem_bad;
    bit align_bad;
    bit range_bad;
    sel_bad   = (sel>=NUM_SLAVES);
    mem_bad   = ((maddr+len)>MEM_DEPTH);
    align_bad = ((64'(addr) % 64'(STRB_W))!=64'd0);
    range_bad = incr&&((64'(addr) + (64'(len) * 64'(STRB_W)))>SPACE_BYTES);
    return sel_bad||mem_bad||align_bad||range_bad;
  endfunction

  //---------------------------------------------------------------------------
  // 常時モニタ
  //---------------------------------------------------------------------------
  logic done_q;
  logic exp_rvalid_q;

  always @(posedge pclk or negedge presetn) begin
    if( !presetn ) begin
      done_q       <= 1'b0;
      exp_rvalid_q <= 1'b0;
    end else begin
      done_q       <= done;
      exp_rvalid_q <= mem_valid&&mem_ready&&!mem_write;
      if( busy==cmd_ready ) begin
        mon_err_cnt <= mon_err_cnt + 1;
        $display("[%0t] [ERROR] busy=%b cmd_ready=%b", $time, busy, cmd_ready);
      end
      if( mem_ready!=cmd_ready ) begin
        mon_err_cnt <= mon_err_cnt + 1;
        $display("[%0t] [ERROR] mem_ready=%b cmd_ready=%b", $time, mem_ready, cmd_ready);
      end
      if( done&&done_q ) begin
        mon_err_cnt <= mon_err_cnt + 1;
        $display("[%0t] [ERROR] done is longer than 1 cycle", $time);
      end
      if( done&&!busy ) begin
        mon_err_cnt <= mon_err_cnt + 1;
        $display("[%0t] [ERROR] done=1 while busy=0", $time);
      end
      if( done&&(done_err!=(|err_flags)) ) begin
        mon_err_cnt <= mon_err_cnt + 1;
        $display("[%0t] [ERROR] done_err=%b err_flags=%b", $time, done_err, err_flags);
      end
      if( mem_rvalid!=exp_rvalid_q ) begin
        mon_err_cnt <= mon_err_cnt + 1;
        $display("[%0t] [ERROR] mem_rvalid=%b (exp %b)", $time, mem_rvalid, exp_rvalid_q);
      end
      if( !$onehot0(psel) ) begin
        mon_err_cnt <= mon_err_cnt + 1;
        $display("[%0t] [ERROR] more than one PSEL asserted : %b", $time, psel);
      end
      if( penable&&!$onehot(psel) ) begin
        mon_err_cnt <= mon_err_cnt + 1;
        $display("[%0t] [ERROR] PENABLE=1 but PSEL=%b", $time, psel);
      end
      if( !busy&&((psel!={NUM_SLAVES{1'b0}})||penable) ) begin
        mon_err_cnt <= mon_err_cnt + 1;
        $display("[%0t] [ERROR] bus activity while busy=0 : PSEL=%b PENABLE=%b", $time, psel, penable);
      end
    end
  end

  //---------------------------------------------------------------------------
  // ローカルポート
  //   どのタスクも negedge で入り、negedge で戻る。
  //   ready は登録値なので、negedge で見た値が次の posedge でも成り立つ
  //---------------------------------------------------------------------------
  task automatic wait_mem_ready();
    int unsigned guard;
    guard = 0;
    while( !mem_ready ) begin
      guard++;
      if( guard>HANG_LIMIT ) begin
        abort_test("mem_ready did not rise");
      end
      @(negedge pclk);
    end
  endtask

  task automatic mem_wr( input int unsigned a, input bit [DATA_WIDTH-1:0] d );
    mem_valid = 1'b1;
    mem_write = 1'b1;
    mem_addr  = MEM_AW'(a);
    mem_wdata = d;
    wait_mem_ready();
    @(negedge pclk);
    mem_valid = 1'b0;
    if( a<MEM_DEPTH ) begin
      ref_mem[a] = d;
    end
  endtask

  task automatic mem_rd( input int unsigned a, output bit [DATA_WIDTH-1:0] d );
    mem_valid = 1'b1;
    mem_write = 1'b0;
    mem_addr  = MEM_AW'(a);
    wait_mem_ready();
    @(negedge pclk);
    mem_valid = 1'b0;
    if( !mem_rvalid ) begin
      tb_error($sformatf("mem_rvalid=0 in the cycle after a local read of word %0d", a));
    end
    d = mem_rdata;
  endtask

  // 内部メモリを乱数で埋める
  task automatic mem_fill_random();
    for( int unsigned i=0; i<MEM_DEPTH; i++ ) begin
      mem_wr(i, f_rand_data());
    end
  endtask

  // 内部メモリの全ワードを読み、期待値と照合する
  task automatic mem_check_all( input string tag );
    bit [DATA_WIDTH-1:0] d;
    int unsigned         nbad;
    nbad = 0;
    for( int unsigned i=0; i<MEM_DEPTH; i++ ) begin
      mem_rd(i, d);
      if( d!=ref_mem[i] ) begin
        nbad++;
        if( nbad<=4 ) begin
          tb_error($sformatf("%s : internal memory word %0d = %h (exp %h)", tag, i, d, ref_mem[i]));
        end
      end
    end
    if( nbad>4 ) begin
      tb_error($sformatf("%s : %0d internal memory words mismatch in total", tag, nbad));
    end
  endtask

  //---------------------------------------------------------------------------
  // スレーブのメモリ
  //---------------------------------------------------------------------------
  // スレーブ s の [ワード位置 w0 から n ワード] を乱数で埋める (期待値にも反映)
  task automatic slv_fill_random( input int unsigned s, input longint unsigned w0, input int unsigned n );
    bit [DATA_WIDTH-1:0] d;
    for( int unsigned i=0; i<n; i++ ) begin
      if( (w0+64'(i))<SPACE_WORDS ) begin
        d = f_rand_data();
        u_slv.poke_word(s, f_waddr(w0+64'(i)), d);
        exp_smem[f_key(s, f_waddr(w0+64'(i)))] = d;
      end
    end
  endtask

  // スレーブのメモリ全体を期待値と照合する (書いていないはずの場所が変わっていないことも見る)
  task automatic slv_check_all( input string tag );
    bit [63:0]   k;
    int unsigned nbad;
    nbad = 0;
    if( u_slv.mem.num()!=exp_smem.num() ) begin
      tb_error($sformatf("%s : slave memory has %0d words, expected %0d", tag, u_slv.mem.num(), exp_smem.num()));
    end
    if( exp_smem.first(k)!=0 ) begin
      do begin
        if( !u_slv.mem.exists(k) ) begin
          nbad++;
          tb_error($sformatf("%s : slave %0d addr=%h was never written", tag, k[63:32], k[31:0]));
        end else if( u_slv.mem[k]!=exp_smem[k] ) begin
          nbad++;
          if( nbad<=4 ) begin
            tb_error($sformatf("%s : slave %0d addr=%h = %h (exp %h)", tag, k[63:32], k[31:0], u_slv.mem[k], exp_smem[k]));
          end
        end
      end while( exp_smem.next(k)!=0 );
    end
    if( nbad>4 ) begin
      tb_error($sformatf("%s : %0d slave memory words mismatch in total", tag, nbad));
    end
  endtask

  //---------------------------------------------------------------------------
  // コマンド 1 本 : 期待値の作成 → 発行 → 完了待ち → 全項目の照合
  //   run_cmd がまとめて行う。busy 中にコマンドを出したまま待つテスト (TEST9) のために、
  //   exp_build / cmd_drive / cmd_wait_accept / cmd_finish に分けてある
  //---------------------------------------------------------------------------
  // exp_build が作る、コマンド 1 本ぶんの期待値
  bit                  x_empty;
  bit                  x_bad;
  bit [ADDR_WIDTH-1:0] x_addr [$];    // 実行されるはずの転送のアドレス
  bit                  x_to   [$];    // その転送はタイムアウトする
  bit                  x_er   [$];    // その転送は PSLVERR になる
  bit                  x_got_err;
  bit                  x_e_slv;
  bit                  x_e_to;
  int unsigned         x_e_idx;

  function automatic string f_cmd_str
  (
    input string               tag
   ,input bit                  wr
   ,input int unsigned         sel
   ,input bit [ADDR_WIDTH-1:0] addr
   ,input bit                  incr
   ,input int unsigned         maddr
   ,input int unsigned         len
   ,input bit [STRB_W-1:0]     strb
   ,input bit [2:0]            prot
  );
    return $sformatf("%s [%s sel=%0d addr=%h incr=%0d mem=%0d len=%0d strb=%b prot=%b]", tag, wr ? "WR" : "RD", sel, addr, incr, maddr, len, strb, prot);
  endfunction

  // 期待される転送の列を作る (スレーブの設定と wait_times_out は、この時点の値を使う)
  task automatic exp_build( input int unsigned sel, input bit [ADDR_WIDTH-1:0] addr, input bit incr, input int unsigned maddr, input int unsigned len );
    bit [ADDR_WIDTH-1:0] a;
    bit                  to;
    bit                  er;
    x_addr.delete();
    x_to.delete();
    x_er.delete();
    x_empty   = (len==0);
    x_bad     = f_cmd_bad(sel, addr, incr, maddr, len);
    x_got_err = 1'b0;
    x_e_slv   = 1'b0;
    x_e_to    = 1'b0;
    x_e_idx   = 0;
    if( !x_empty&&!x_bad ) begin
      for( int unsigned i=0; i<len; i++ ) begin
        a  = f_xaddr(addr, incr, i);
        to = (TIMEOUT_CYCLES>0)&&(u_slv.f_in_hang(sel, a)||wait_times_out);
        er = !to&&u_slv.f_in_err(sel, a);
        x_addr.push_back(a);
        x_to.push_back(to);
        x_er.push_back(er);
        if( to||er ) begin
          if( !x_got_err ) begin
            x_got_err = 1'b1;
            x_e_idx   = i;
          end
          if( to ) begin
            x_e_to = 1'b1;
          end else begin
            x_e_slv = 1'b1;
          end
          if( STOP_ON_ERROR ) begin
            break;
          end
        end
      end
    end
  endtask

  // コマンドを出す (cmd_valid=1 にするだけ。握手は待たない)
  task automatic cmd_drive
  (
    input bit                  wr
   ,input int unsigned         sel
   ,input bit [ADDR_WIDTH-1:0] addr
   ,input bit                  incr
   ,input int unsigned         maddr
   ,input int unsigned         len
   ,input bit [STRB_W-1:0]     strb
   ,input bit [2:0]            prot
  );
    if( (sel>=(1<<SEL_W))||(maddr>=(1<<MEM_AW))||(len>=(1<<LEN_W)) ) begin
      tb_error($sformatf("testbench : command field does not fit in the port (sel=%0d mem=%0d len=%0d)", sel, maddr, len));
    end
    cmd_valid    = 1'b1;
    cmd_write    = wr;
    cmd_sel      = SEL_W'(sel);
    cmd_addr     = addr;
    cmd_incr     = incr;
    cmd_mem_addr = MEM_AW'(maddr);
    cmd_len      = LEN_W'(len);
    cmd_strb     = strb;
    cmd_prot     = prot;
  endtask

  // 握手を待つ。戻ったときは受付の posedge の次の negedge (cmd_valid はそのまま)
  task automatic cmd_wait_accept( input string id );
    int unsigned guard;
    guard = 0;
    while( !cmd_ready ) begin
      guard++;
      if( guard>HANG_LIMIT ) begin
        abort_test({id, " : cmd_ready did not rise"});
      end
      @(negedge pclk);
    end
    last_acc_cyc = cyc;
    last_acc_b2b = u_slv.n_b2b;
    @(negedge pclk);
  endtask

  // 完了を待ち、exp_build の期待値と照合する
  task automatic cmd_finish
  (
    input string           id
   ,input bit              wr
   ,input int unsigned     sel
   ,input int unsigned     maddr
   ,input bit [STRB_W-1:0] strb
   ,input bit [2:0]        prot
   ,input bit              check_mem
  );
    int unsigned         guard;
    int unsigned         n_exp;
    int unsigned         exp_cyc;
    int unsigned         exp_b2b;
    bit [2:0]            exp_flags;
    bit [DATA_WIDTH-1:0] m;
    bit [DATA_WIDTH-1:0] wd;

    n_exp     = x_addr.size();
    exp_flags = {(x_bad&&!x_empty), x_e_to, x_e_slv};
    // 受付から done までのサイクル数の期待値 (下で転送ごとの長さを足す)
    //   転送しないコマンドは 1。転送するコマンドは、書き込み 4 / 読み出し 3 + 各転送の長さ
    if( n_exp==0 ) begin
      exp_cyc = 1;
    end else if( wr ) begin
      exp_cyc = 4;
    end else begin
      exp_cyc = 3;
    end
    // 完了待ち
    guard = 0;
    while( !done ) begin
      guard++;
      if( guard>HANG_LIMIT ) begin
        abort_test({id, " : done did not arrive"});
      end
      @(negedge pclk);
    end
    last_done_cyc = cyc;

    // ステータス (done と同じサイクルで見る)
    if( err_flags!==exp_flags ) begin
      tb_error($sformatf("%s : err_flags=%b (exp %b)", id, err_flags, exp_flags));
    end
    if( done_err!==(|exp_flags) ) begin
      tb_error($sformatf("%s : done_err=%b (exp %b)", id, done_err, |exp_flags));
    end
    if( 32'(done_count)!=n_exp ) begin
      tb_error($sformatf("%s : done_count=%0d (exp %0d)", id, done_count, n_exp));
    end
    if( x_got_err&&(32'(err_index)!=x_e_idx) ) begin
      tb_error($sformatf("%s : err_index=%0d (exp %0d)", id, err_index, x_e_idx));
    end
    @(negedge pclk);

    // バス上の転送の列
    for( int unsigned i=0; i<n_exp; i++ ) begin
      if( x_to[i] ) begin
        // 打ち切った転送はスレーブ側では完了していない (SETUP 1 + ACCESS TIMEOUT_CYCLES サイクル)
        n_abort_exp++;
        exp_cyc = exp_cyc + 1 + TIMEOUT_CYCLES;
      end else begin
        n_xfer_exp++;
        if( u_slv.log_slv.size()==0 ) begin
          tb_error($sformatf("%s : transfer %0d (addr=%h) did not appear on the bus", id, i, x_addr[i]));
        end else begin
          // 完了した転送は SETUP 1 + ACCESS (1 + ウェイト数) サイクル
          exp_cyc = exp_cyc + 2 + u_slv.log_wait[0];
          wd = ref_mem[(maddr+i) % MEM_DEPTH];
          if( (u_slv.log_slv[0]!=sel)||(u_slv.log_addr[0]!=x_addr[i])||(u_slv.log_write[0]!=wr)||(u_slv.log_prot[0]!=prot) ) begin
            tb_error($sformatf("%s : transfer %0d : slave %0d addr=%h write=%b prot=%b (exp slave %0d addr=%h write=%b prot=%b)", id, i, u_slv.log_slv[0], u_slv.log_addr[0], u_slv.log_write[0], u_slv.log_prot[0], sel, x_addr[i], wr, prot));
          end
          if( wr&&((u_slv.log_wdata[0]!=wd)||(u_slv.log_strb[0]!=strb)) ) begin
            tb_error($sformatf("%s : transfer %0d : PWDATA=%h PSTRB=%b (exp %h %b)", id, i, u_slv.log_wdata[0], u_slv.log_strb[0], wd, strb));
          end
          if( !wr&&(u_slv.log_strb[0]!={STRB_W{1'b0}}) ) begin
            tb_error($sformatf("%s : transfer %0d : PSTRB=%b on a read", id, i, u_slv.log_strb[0]));
          end
          if( u_slv.log_err[0]!=x_er[i] ) begin
            tb_error($sformatf("%s : transfer %0d : PSLVERR=%b (exp %b)", id, i, u_slv.log_err[0], x_er[i]));
          end
          void'(u_slv.log_slv.pop_front());
          void'(u_slv.log_addr.pop_front());
          void'(u_slv.log_write.pop_front());
          void'(u_slv.log_wdata.pop_front());
          void'(u_slv.log_strb.pop_front());
          void'(u_slv.log_prot.pop_front());
          void'(u_slv.log_rdata.pop_front());
          void'(u_slv.log_err.pop_front());
          void'(u_slv.log_wait.pop_front());
          // 期待値の更新
          if( !x_er[i] ) begin
            if( wr ) begin
              m = f_smem(sel, x_addr[i]);
              for( int unsigned b=0; b<STRB_W; b++ ) begin
                if( strb[b] ) begin
                  m[8*b +: 8] = wd[8*b +: 8];
                end
              end
              exp_smem[f_key(sel, x_addr[i])] = m;
            end else begin
              ref_mem[maddr+i] = f_smem(sel, x_addr[i]);
            end
          end
        end
      end
    end
    if( u_slv.log_slv.size()!=0 ) begin
      tb_error($sformatf("%s : %0d extra transfer(s) on the bus (first : slave %0d addr=%h write=%b)", id, u_slv.log_slv.size(), u_slv.log_slv[0], u_slv.log_addr[0], u_slv.log_write[0]));
      u_slv.clear_log();
    end
    // 所要サイクル数 (転送の前後や間に、余分なサイクルが入っていないこと)
    if( (last_done_cyc-last_acc_cyc)!=exp_cyc ) begin
      tb_error($sformatf("%s : done came %0d cycles after the command was accepted (exp %0d)", id, last_done_cyc-last_acc_cyc, exp_cyc));
    end
    // 1 コマンドの中の転送は IDLE を挟まずに続く (2 本目以降は全て back-to-back、最初の転送は違う)
    exp_b2b = (n_exp>1) ? (n_exp-1) : 0;
    if( (u_slv.n_b2b-last_acc_b2b)!=exp_b2b ) begin
      tb_error($sformatf("%s : %0d back-to-back transfer(s) (exp %0d : every transfer of the command except the first)", id, u_slv.n_b2b-last_acc_b2b, exp_b2b));
    end

    // 書き込み : 触ったワードをスレーブのメモリと照合
    if( wr ) begin
      for( int unsigned i=0; i<n_exp; i++ ) begin
        if( u_slv.peek_word(sel,x_addr[i])!=f_smem(sel,x_addr[i]) ) begin
          tb_error($sformatf("%s : slave %0d addr=%h = %h (exp %h)", id, sel, x_addr[i], u_slv.peek_word(sel, x_addr[i]), f_smem(sel, x_addr[i])));
        end
      end
    end
    // 内部メモリを全ワード照合
    if( check_mem ) begin
      mem_check_all(id);
    end

    // 統計
    n_cmd++;
    if( x_empty ) begin
      n_cmd_empty++;
    end else if( x_bad ) begin
      n_cmd_bad++;
    end else if( wr ) begin
      n_cmd_wr++;
    end else begin
      n_cmd_rd++;
    end
    if( x_e_slv ) begin
      n_cmd_slverr++;
    end
    if( x_e_to ) begin
      n_cmd_timeout++;
    end
  endtask

  task automatic run_cmd
  (
    input string               tag
   ,input bit                  wr
   ,input int unsigned         sel
   ,input bit [ADDR_WIDTH-1:0] addr
   ,input bit                  incr
   ,input int unsigned         maddr
   ,input int unsigned         len
   ,input bit [STRB_W-1:0]     strb
   ,input bit [2:0]            prot
   ,input bit                  check_mem
  );
    string id;
    id = f_cmd_str(tag, wr, sel, addr, incr, maddr, len, strb, prot);
    exp_build(sel, addr, incr, maddr, len);
    cmd_drive(wr, sel, addr, incr, maddr, len, strb, prot);
    cmd_wait_accept(id);
    cmd_valid = 1'b0;
    cmd_finish(id, wr, sel, maddr, strb, prot, check_mem);
  endtask

  // エラー / ハングの範囲 (1 ワード) を設定する
  task automatic set_err_word( input int unsigned s, input bit [ADDR_WIDTH-1:0] a );
    u_slv.err_lo[s] = a;
    u_slv.err_hi[s] = a + ADDR_WIDTH'(STRB_W-1);
  endtask

  task automatic set_hang_word( input int unsigned s, input bit [ADDR_WIDTH-1:0] a );
    u_slv.hang_lo[s] = a;
    u_slv.hang_hi[s] = a + ADDR_WIDTH'(STRB_W-1);
  endtask

  //---------------------------------------------------------------------------
  // ランダムなコマンド 1 本
  //---------------------------------------------------------------------------
  task automatic rand_cmd( input string tag );
    bit                  wr;
    int unsigned         sel;
    longint unsigned     w0;
    bit [ADDR_WIDTH-1:0] addr;
    bit                  incr;
    int unsigned         maddr;
    int unsigned         len;
    bit [STRB_W-1:0]     strb;
    int unsigned         r;
    int unsigned         k;
    longint unsigned     back;

    wr   = 1'($urandom());
    incr = ($urandom_range(99, 0)<80);
    // 転送数
    r = $urandom_range(99, 0);
    if( r<5 ) begin
      len = 0;
    end else if( r<20 ) begin
      len = 1;
    end else if( r<35 ) begin
      len = MEM_DEPTH;
    end else begin
      len = $urandom_range(MEM_DEPTH, 1);
    end
    // 内部メモリの位置 (6% は範囲を超え得る)
    maddr = $urandom_range(MEM_DEPTH-1, 0);
    if( ($urandom_range(99,0)>=6)&&((maddr+len)>MEM_DEPTH) ) begin
      maddr = MEM_DEPTH - len;
    end
    // スレーブ番号 (4% は存在しない番号)
    if( HAS_BAD_SEL&&($urandom_range(99,0)<4) ) begin
      sel = $urandom_range((1<<SEL_W)-1, NUM_SLAVES);
    end else begin
      sel = $urandom_range(NUM_SLAVES-1, 0);
    end
    // アドレス : 75% は下位の領域、25% はアドレス空間の末尾付近
    if( $urandom_range(99,0)<75 ) begin
      w0 = 64'($urandom_range(47, 0));
      // アドレス空間が狭い構成では、8 割を収まる位置へ寄せる
      if( ((w0+64'(len))>SPACE_WORDS)&&($urandom_range(99,0)<80) ) begin
        if( 64'(len)<=SPACE_WORDS ) begin
          back = SPACE_WORDS - 64'(len);
          if( back>64'd47 ) begin
            back = 64'd47;
          end
          w0 = 64'($urandom_range(32'(back), 0));
        end else begin
          w0 = 64'd0;
        end
      end
      if( w0>=SPACE_WORDS ) begin
        w0 = 64'd0;
      end
    end else begin
      // 末尾ちょうど〜2 ワード手前に収まる (70%) / はみ出す (30%)
      if( $urandom_range(99,0)<70 ) begin
        back = 64'(len) + 64'($urandom_range(2, 0));
      end else begin
        back = 64'($urandom_range(len, 0));
      end
      if( back>SPACE_WORDS ) begin
        back = SPACE_WORDS;
      end
      w0 = SPACE_WORDS - back;
      if( w0>=SPACE_WORDS ) begin
        w0 = SPACE_WORDS - 64'd1;
      end
    end
    addr = f_waddr(w0);
    // 4% は非アライン
    if( (STRB_W>1)&&($urandom_range(99,0)<4) ) begin
      addr = addr + ADDR_WIDTH'($urandom_range(STRB_W-1, 1));
    end
    // PSTRB : 30% は全バイト、残りは乱数 (0 を含む)
    if( $urandom_range(99,0)<30 ) begin
      strb = {STRB_W{1'b1}};
    end else begin
      strb = STRB_W'($urandom());
    end

    // スレーブの振る舞い
    if( $urandom_range(99,0)<40 ) begin
      u_slv.set_wait(0, 0);
    end else begin
      u_slv.set_wait(0, WAIT_MAX);
    end
    u_slv.clear_err();
    if( (sel<NUM_SLAVES)&&(len>0) ) begin
      k = $urandom_range(len-1, 0);
      r = $urandom_range(99, 0);
      if( r<25 ) begin
        set_err_word(sel, f_xaddr(f_waddr(w0), incr, k));
      end else if( (r<40)&&(TIMEOUT_CYCLES>0) ) begin
        set_hang_word(sel, f_xaddr(f_waddr(w0), incr, k));
      end
    end
    run_cmd(tag, wr, sel, addr, incr, maddr, len, strb, 3'($urandom()), 1'b1);
    u_slv.clear_err();
  endtask

  //---------------------------------------------------------------------------
  // テスト本体
  //---------------------------------------------------------------------------
  bit [DATA_WIDTH-1:0] d0;
  bit [DATA_WIDTH-1:0] d1;
  int unsigned         n_tmp;
  int unsigned         l3;
  int unsigned         kk;
  string               id1;
  string               id2;

  initial begin
    err_cnt        = 0;
    mon_err_cnt    = 0;
    cyc            = 0;
    n_cmd          = 0;
    n_cmd_wr       = 0;
    n_cmd_rd       = 0;
    n_cmd_bad      = 0;
    n_cmd_empty    = 0;
    n_cmd_slverr   = 0;
    n_cmd_timeout  = 0;
    n_xfer_exp     = 0;
    n_abort_exp    = 0;
    last_acc_cyc   = 0;
    last_done_cyc  = 0;
    last_acc_b2b   = 0;
    wait_times_out = 1'b0;
    cmd_valid      = 1'b0;
    cmd_write      = 1'b0;
    cmd_sel        = {SEL_W{1'b0}};
    cmd_addr       = {ADDR_WIDTH{1'b0}};
    cmd_incr       = 1'b0;
    cmd_mem_addr   = {MEM_AW{1'b0}};
    cmd_len        = {LEN_W{1'b0}};
    cmd_strb       = {STRB_W{1'b0}};
    cmd_prot       = 3'b000;
    mem_valid      = 1'b0;
    mem_write      = 1'b0;
    mem_addr       = {MEM_AW{1'b0}};
    mem_wdata      = {DATA_WIDTH{1'b0}};
    presetn        = 1'b0;
    repeat( 5 ) begin
      @(negedge pclk);
    end
    presetn = 1'b1;
    repeat( 3 ) begin
      @(negedge pclk);
    end
    $display("[INFO] ADDR_WIDTH=%0d DATA_WIDTH=%0d NUM_SLAVES=%0d MEM_DEPTH=%0d TIMEOUT_CYCLES=%0d STOP_ON_ERROR=%0d (LMAX=%0d)", ADDR_WIDTH, DATA_WIDTH, NUM_SLAVES, MEM_DEPTH, TIMEOUT_CYCLES, STOP_ON_ERROR, LMAX);

    // スレーブのメモリに初期値を入れておく (下位の領域と、アドレス空間の末尾付近)
    for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
      slv_fill_random(s, 64'd0, 64);
      if( SPACE_WORDS>=(64'(MEM_DEPTH)+64'd68) ) begin
        slv_fill_random(s, SPACE_WORDS - 64'(MEM_DEPTH) - 64'd4, MEM_DEPTH + 4);
      end
    end
    mem_fill_random();
    mem_check_all("init");

    //-------------------------------------------------------------------------
    // TEST1 : 基本。内部メモリ全体を書き込み → 内部メモリを書き換え → 読み戻すと元に戻る
    //         ウェイト無しのときの所要サイクル (2 サイクル/転送) も確認する
    //-------------------------------------------------------------------------
    u_slv.set_wait(0, 0);
    run_cmd("TEST1 write", 1'b1, 0, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX, {STRB_W{1'b1}}, 3'b000, 1'b1);
    if( (last_done_cyc-last_acc_cyc)!=((2*LMAX)+4) ) begin
      tb_error($sformatf("TEST1 : write of %0d words took %0d cycles (exp %0d)", LMAX, last_done_cyc-last_acc_cyc, (2*LMAX)+4));
    end
    $display("[INFO] PERF : write %0d words in %0d cycles, from command accept to done", LMAX, last_done_cyc-last_acc_cyc);
    mem_fill_random();
    run_cmd("TEST1 read", 1'b0, 0, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX, {STRB_W{1'b0}}, 3'b000, 1'b1);
    if( (last_done_cyc-last_acc_cyc)!=((2*LMAX)+3) ) begin
      tb_error($sformatf("TEST1 : read of %0d words took %0d cycles (exp %0d)", LMAX, last_done_cyc-last_acc_cyc, (2*LMAX)+3));
    end
    $display("[INFO] PERF : read  %0d words in %0d cycles, from command accept to done", LMAX, last_done_cyc-last_acc_cyc);
    slv_check_all("TEST1");
    $display("[INFO] TEST1 (basic write / read back) done");

    //-------------------------------------------------------------------------
    // TEST2 : 転送数とメモリ位置の端、固定アドレス、PSTRB、PPROT
    //-------------------------------------------------------------------------
    mem_fill_random();
    run_cmd("TEST2 len=1 first", 1'b1, 0, f_waddr(64'(BASE_W)), 1'b1, 0, 1, {STRB_W{1'b1}}, 3'b001, 1'b1);
    run_cmd("TEST2 len=1 last", 1'b1, 0, f_waddr(64'(BASE_W)), 1'b1, MEM_DEPTH-1, 1, {STRB_W{1'b1}}, 3'b010, 1'b1);
    run_cmd("TEST2 len=1 read last", 1'b0, 0, f_waddr(64'(BASE_W)), 1'b0, MEM_DEPTH-1, 1, {STRB_W{1'b1}}, 3'b100, 1'b1);
    if( LMAX>=2 ) begin
      run_cmd("TEST2 tail", 1'b1, 0, f_waddr(64'(BASE_W)), 1'b1, MEM_DEPTH-2, 2, {STRB_W{1'b1}}, 3'b111, 1'b1);
      run_cmd("TEST2 read tail", 1'b0, 0, f_waddr(64'(BASE_W)), 1'b1, MEM_DEPTH-2, 2, {STRB_W{1'b1}}, 3'b101, 1'b1);
    end
    // 固定アドレス : 同じアドレスへ繰り返し書く (最後の値が残る) / 繰り返し読む (同じ値が並ぶ)
    run_cmd("TEST2 fixed write", 1'b1, 0, f_waddr(64'(BASE_W)), 1'b0, 0, MEM_DEPTH, {STRB_W{1'b1}}, 3'b000, 1'b1);
    run_cmd("TEST2 fixed read", 1'b0, 0, f_waddr(64'(BASE_W)), 1'b0, 0, MEM_DEPTH, {STRB_W{1'b0}}, 3'b000, 1'b1);
    // PSTRB : 1 バイトずつ、および 0
    mem_fill_random();
    for( int unsigned b=0; b<STRB_W; b++ ) begin
      run_cmd("TEST2 strb", 1'b1, 0, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX, STRB_W'(1) << b, 3'b000, 1'b0);
      mem_fill_random();
    end
    run_cmd("TEST2 strb=0", 1'b1, 0, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX, {STRB_W{1'b0}}, 3'b000, 1'b1);
    // PPROT 全値
    for( int unsigned p=0; p<8; p++ ) begin
      run_cmd("TEST2 prot", 1'($urandom()), 0, f_waddr(64'(BASE_W)), 1'b1, 0, 1, {STRB_W{1'b1}}, 3'(p), 1'b0);
    end
    slv_check_all("TEST2");
    $display("[INFO] TEST2 (length / memory position corners, fixed address, PSTRB, PPROT) done");

    //-------------------------------------------------------------------------
    // TEST3 : スレーブごとに書いて読む (他のスレーブを触らないこと)
    //-------------------------------------------------------------------------
    for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
      mem_fill_random();
      run_cmd("TEST3 write", 1'b1, s, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX, {STRB_W{1'b1}}, 3'b000, 1'b0);
    end
    for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
      mem_fill_random();
      run_cmd("TEST3 read", 1'b0, s, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX, {STRB_W{1'b0}}, 3'b000, 1'b1);
    end
    slv_check_all("TEST3");
    $display("[INFO] TEST3 (each slave) done");

    //-------------------------------------------------------------------------
    // TEST4 : ウェイトあり
    //-------------------------------------------------------------------------
    u_slv.set_wait(0, WAIT_MAX);
    mem_fill_random();
    run_cmd("TEST4 write", 1'b1, NUM_SLAVES-1, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX, {STRB_W{1'b1}}, 3'b000, 1'b1);
    mem_fill_random();
    run_cmd("TEST4 read", 1'b0, NUM_SLAVES-1, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX, {STRB_W{1'b0}}, 3'b000, 1'b1);
    u_slv.set_wait(WAIT_MAX, WAIT_MAX);
    run_cmd("TEST4 write max wait", 1'b1, 0, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX, {STRB_W{1'b1}}, 3'b000, 1'b1);
    run_cmd("TEST4 read max wait", 1'b0, 0, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX, {STRB_W{1'b0}}, 3'b000, 1'b1);
    $display("[INFO] TEST4 (wait states) done : max wait seen = %0d", u_slv.max_wait);

    //-------------------------------------------------------------------------
    // TEST5 : PSLVERR (先頭 / 中間 / 最後の転送)。その後の正常なコマンド
    //-------------------------------------------------------------------------
    l3 = (LMAX>=3) ? LMAX : 1;
    for( int unsigned pos=0; pos<3; pos++ ) begin
      kk = (pos==0) ? 0 : ((pos==1) ? (l3/2) : (l3-1));
      for( int unsigned w=0; w<2; w++ ) begin
        u_slv.set_wait(0, (w==0) ? 0 : WAIT_MAX);
        set_err_word(0, f_waddr(64'(BASE_W) + 64'(kk)));
        mem_fill_random();
        run_cmd("TEST5 write", 1'b1, 0, f_waddr(64'(BASE_W)), 1'b1, 0, l3, {STRB_W{1'b1}}, 3'b000, 1'b1);
        run_cmd("TEST5 read", 1'b0, 0, f_waddr(64'(BASE_W)), 1'b1, 0, l3, {STRB_W{1'b0}}, 3'b000, 1'b1);
        u_slv.clear_err();
        run_cmd("TEST5 read after error", 1'b0, 0, f_waddr(64'(BASE_W)), 1'b1, 0, l3, {STRB_W{1'b0}}, 3'b000, 1'b1);
      end
    end
    // 全転送がエラー (固定アドレス)
    set_err_word(0, f_waddr(64'(BASE_W)));
    run_cmd("TEST5 all errors", 1'b1, 0, f_waddr(64'(BASE_W)), 1'b0, 0, MEM_DEPTH, {STRB_W{1'b1}}, 3'b000, 1'b1);
    run_cmd("TEST5 all errors", 1'b0, 0, f_waddr(64'(BASE_W)), 1'b0, 0, MEM_DEPTH, {STRB_W{1'b0}}, 3'b000, 1'b1);
    u_slv.clear_err();
    slv_check_all("TEST5");
    $display("[INFO] TEST5 (PSLVERR at the first / middle / last transfer) done");

    //-------------------------------------------------------------------------
    // TEST6 : タイムアウト
    //-------------------------------------------------------------------------
    if( TIMEOUT_CYCLES>0 ) begin
      // 上限ちょうどのウェイト (TIMEOUT_CYCLES-1) は完了する
      u_slv.set_wait(TIMEOUT_CYCLES-1, TIMEOUT_CYCLES-1);
      mem_fill_random();
      run_cmd("TEST6 wait = limit", 1'b1, 0, f_waddr(64'(BASE_W)), 1'b1, 0, l3, {STRB_W{1'b1}}, 3'b000, 1'b1);
      run_cmd("TEST6 wait = limit", 1'b0, 0, f_waddr(64'(BASE_W)), 1'b1, 0, l3, {STRB_W{1'b0}}, 3'b000, 1'b1);
      // 上限を 1 超えるウェイトは打ち切る
      u_slv.set_wait(TIMEOUT_CYCLES, TIMEOUT_CYCLES);
      wait_times_out = 1'b1;
      run_cmd("TEST6 wait = limit+1", 1'b1, 0, f_waddr(64'(BASE_W)), 1'b1, 0, l3, {STRB_W{1'b1}}, 3'b000, 1'b1);
      run_cmd("TEST6 wait = limit+1", 1'b0, 0, f_waddr(64'(BASE_W)), 1'b1, 0, l3, {STRB_W{1'b0}}, 3'b000, 1'b1);
      wait_times_out = 1'b0;
      // 応答しないワード (先頭 / 中間 / 最後)
      for( int unsigned pos=0; pos<3; pos++ ) begin
        kk = (pos==0) ? 0 : ((pos==1) ? (l3/2) : (l3-1));
        u_slv.set_wait(0, WAIT_MAX);
        set_hang_word(NUM_SLAVES-1, f_waddr(64'(BASE_W) + 64'(kk)));
        mem_fill_random();
        run_cmd("TEST6 hang write", 1'b1, NUM_SLAVES-1, f_waddr(64'(BASE_W)), 1'b1, 0, l3, {STRB_W{1'b1}}, 3'b000, 1'b1);
        run_cmd("TEST6 hang read", 1'b0, NUM_SLAVES-1, f_waddr(64'(BASE_W)), 1'b1, 0, l3, {STRB_W{1'b0}}, 3'b000, 1'b1);
        u_slv.clear_err();
        run_cmd("TEST6 read after timeout", 1'b0, NUM_SLAVES-1, f_waddr(64'(BASE_W)), 1'b1, 0, l3, {STRB_W{1'b0}}, 3'b000, 1'b1);
      end
      slv_check_all("TEST6");
      $display("[INFO] TEST6 (timeout) done : %0d transfers aborted", u_slv.n_abort);
    end

    //-------------------------------------------------------------------------
    // TEST7 : コマンドの誤り / 0 ワード
    //-------------------------------------------------------------------------
    u_slv.set_wait(0, 0);
    // メモリ範囲超え (1 ワードだけはみ出す)
    if( MEM_DEPTH>=2 ) begin
      run_cmd("TEST7 mem range", 1'b1, 0, f_waddr(64'(BASE_W)), 1'b0, MEM_DEPTH-1, 2, {STRB_W{1'b1}}, 3'b000, 1'b1);
    end
    run_cmd("TEST7 mem range", 1'b0, 0, f_waddr(64'(BASE_W)), 1'b0, 1, MEM_DEPTH, {STRB_W{1'b1}}, 3'b000, 1'b1);
    // 存在しないスレーブ番号
    if( HAS_BAD_SEL ) begin
      run_cmd("TEST7 bad slave", 1'b1, NUM_SLAVES, f_waddr(64'(BASE_W)), 1'b1, 0, 1, {STRB_W{1'b1}}, 3'b000, 1'b1);
      run_cmd("TEST7 bad slave", 1'b0, (1<<SEL_W)-1, f_waddr(64'(BASE_W)), 1'b1, 0, 1, {STRB_W{1'b1}}, 3'b000, 1'b1);
    end
    // 非アライン
    if( STRB_W>1 ) begin
      run_cmd("TEST7 unaligned", 1'b1, 0, f_waddr(64'(BASE_W)) + ADDR_WIDTH'(1), 1'b1, 0, 1, {STRB_W{1'b1}}, 3'b000, 1'b1);
      run_cmd("TEST7 unaligned", 1'b0, 0, f_waddr(64'(BASE_W)) + ADDR_WIDTH'(STRB_W-1), 1'b0, 0, 1, {STRB_W{1'b1}}, 3'b000, 1'b1);
    end
    // アドレス空間の末尾 : ちょうど収まる / 1 ワード超える / 固定アドレスなら超えない
    run_cmd("TEST7 top fits", 1'b1, 0, f_waddr(SPACE_WORDS - 64'(LMAX)), 1'b1, 0, LMAX, {STRB_W{1'b1}}, 3'b000, 1'b1);
    run_cmd("TEST7 top fits", 1'b0, 0, f_waddr(SPACE_WORDS - 64'(LMAX)), 1'b1, 0, LMAX, {STRB_W{1'b0}}, 3'b000, 1'b1);
    if( MEM_DEPTH>=2 ) begin
      run_cmd("TEST7 top overflow", 1'b1, 0, f_waddr(SPACE_WORDS - 64'd1), 1'b1, 0, 2, {STRB_W{1'b1}}, 3'b000, 1'b1);
      run_cmd("TEST7 top fixed", 1'b1, 0, f_waddr(SPACE_WORDS - 64'd1), 1'b0, 0, 2, {STRB_W{1'b1}}, 3'b000, 1'b1);
    end
    // 0 ワード (他の項目が誤っていてもエラーにしない)
    run_cmd("TEST7 empty", 1'b1, 0, f_waddr(64'(BASE_W)), 1'b1, 0, 0, {STRB_W{1'b1}}, 3'b000, 1'b1);
    run_cmd("TEST7 empty", 1'b0, (1<<SEL_W)-1, {ADDR_WIDTH{1'b1}}, 1'b1, MEM_DEPTH-1, 0, {STRB_W{1'b1}}, 3'b000, 1'b1);
    // 誤ったコマンドの後も正常に動く
    run_cmd("TEST7 after bad", 1'b0, 0, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX, {STRB_W{1'b0}}, 3'b000, 1'b1);
    slv_check_all("TEST7");
    $display("[INFO] TEST7 (rejected / empty commands) done");

    //-------------------------------------------------------------------------
    // TEST8 : ローカルポート
    //-------------------------------------------------------------------------
    // (a) 連続した読み出し (mem_valid を上げたまま)
    mem_fill_random();
    mem_valid = 1'b1;
    mem_write = 1'b0;
    for( int unsigned i=0; i<=MEM_DEPTH; i++ ) begin
      if( i>0 ) begin
        if( !mem_rvalid||(mem_rdata!=ref_mem[i-1]) ) begin
          tb_error($sformatf("TEST8 : continuous read word %0d : rvalid=%b rdata=%h (exp %h)", i-1, mem_rvalid, mem_rdata, ref_mem[i-1]));
        end
      end
      if( i<MEM_DEPTH ) begin
        mem_addr = MEM_AW'(i);
      end else begin
        mem_valid = 1'b0;
      end
      @(negedge pclk);
    end
    // (b) 範囲外のアドレス : 書き込みは無視、読み出しは 0
    if( HAS_BAD_MEM ) begin
      mem_wr(MEM_DEPTH, {DATA_WIDTH{1'b1}});
      mem_rd(MEM_DEPTH, d0);
      if( d0!={DATA_WIDTH{1'b0}} ) begin
        tb_error($sformatf("TEST8 : out-of-range local read returned %h (exp 0)", d0));
      end
      mem_wr((1<<MEM_AW)-1, {DATA_WIDTH{1'b1}});
      mem_rd((1<<MEM_AW)-1, d0);
      if( d0!={DATA_WIDTH{1'b0}} ) begin
        tb_error($sformatf("TEST8 : out-of-range local read returned %h (exp 0)", d0));
      end
      mem_check_all("TEST8 out-of-range");
    end
    // (c) コマンド実行中はローカルポートを受け付けない
    //     コマンドと同じサイクルに出した書き込みは受け付けられ、その後は done まで待たされる。
    //     コマンドが転送するワード (内部メモリのワード 0) を同じサイクルに書き換えているので、
    //     バスに出る PWDATA は書き換えた後の値 d0 になる (run_cmd が照合する)
    u_slv.set_wait(WAIT_MAX, WAIT_MAX);
    d0        = ~ref_mem[0];
    d1        = f_rand_data();
    mem_valid = 1'b1;
    mem_write = 1'b1;
    mem_addr  = {MEM_AW{1'b0}};
    mem_wdata = d0;
    fork
      begin
        run_cmd("TEST8 busy", 1'b1, 0, f_waddr(64'(BASE_W)), 1'b1, 0, 1, {STRB_W{1'b1}}, 3'b000, 1'b0);
      end
      begin
        // コマンド受付と同じ posedge で 1 回目の書き込みが入る
        @(negedge pclk);
        ref_mem[0] = d0;
        mem_wdata  = d1;
        // 以降は busy の間、受け付けられないこと
        n_tmp = 0;
        while( !mem_ready ) begin
          n_tmp++;
          @(negedge pclk);
        end
        // done の次のサイクルで受け付けられる
        @(negedge pclk);
        mem_valid  = 1'b0;
        ref_mem[0] = d1;
        if( n_tmp<4 ) begin
          tb_error($sformatf("TEST8 : local port was blocked for only %0d cycles during a command", n_tmp));
        end
      end
    join
    mem_check_all("TEST8 busy");
    // (d) コマンドと同じサイクルに出した読み出しも受け付けられ、次のサイクルに元の値が返る
    //     (書き込みコマンドは次のサイクルから内部メモリを読み始め、読み出しコマンドは後で
    //      同じワードを書き換える。どちらもローカルポートの読み出しデータを壊さないこと)
    u_slv.set_wait(0, 0);
    for( int unsigned w=0; w<2; w++ ) begin
      mem_fill_random();
      kk        = MEM_DEPTH - 1;
      d0        = ref_mem[kk];
      mem_valid = 1'b1;
      mem_write = 1'b0;
      mem_addr  = MEM_AW'(kk);
      fork
        begin
          run_cmd("TEST8 read with command", 1'(w), 0, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX, {STRB_W{1'b1}}, 3'b000, 1'b1);
        end
        begin
          // コマンド受付と同じ posedge で読み出しが入り、ここ (次の negedge) でデータが出ている
          @(negedge pclk);
          mem_valid = 1'b0;
          if( !mem_rvalid||(mem_rdata!=d0) ) begin
            tb_error($sformatf("TEST8 : local read accepted together with a command (cmd_write=%0d) : rvalid=%b rdata=%h (exp %h)", w, mem_rvalid, mem_rdata, d0));
          end
          // コマンドが内部メモリを使っている間は mem_rvalid を出さない
          @(negedge pclk);
          if( mem_rvalid ) begin
            tb_error("TEST8 : mem_rvalid=1 in the second cycle of a command");
          end
        end
      join
    end
    slv_check_all("TEST8");
    $display("[INFO] TEST8 (local port) done");

    //-------------------------------------------------------------------------
    // TEST9 : busy 中に次のコマンドを出したまま待つ
    //         1 本目の実行中は受け付けず、done の次のサイクル (アイドルの最初) で受け付けること
    //-------------------------------------------------------------------------
    u_slv.set_wait(0, WAIT_MAX);
    mem_fill_random();
    id1 = f_cmd_str("TEST9 first", 1'b1, 0, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX, {STRB_W{1'b1}}, 3'b011);
    id2 = f_cmd_str("TEST9 second", 1'b0, NUM_SLAVES-1, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX, {STRB_W{1'b0}}, 3'b100);
    exp_build(0, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX);
    cmd_drive(1'b1, 0, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX, {STRB_W{1'b1}}, 3'b011);
    cmd_wait_accept(id1);
    // 1 本目を受け付けた直後から、2 本目を出したままにする
    cmd_drive(1'b0, NUM_SLAVES-1, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX, {STRB_W{1'b0}}, 3'b100);
    cmd_finish(id1, 1'b1, 0, 0, {STRB_W{1'b1}}, 3'b011, 1'b0);
    // ここは done の次のサイクル。この posedge で 2 本目が受け付けられるはず
    if( !cmd_ready ) begin
      tb_error("TEST9 : cmd_ready=0 in the cycle after done");
    end
    n_tmp = cyc;
    exp_build(NUM_SLAVES-1, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX);
    cmd_wait_accept(id2);
    cmd_valid = 1'b0;
    if( (last_acc_cyc!=n_tmp)||!busy ) begin
      tb_error("TEST9 : the waiting command was not accepted in the first idle cycle");
    end
    cmd_finish(id2, 1'b0, NUM_SLAVES-1, 0, {STRB_W{1'b0}}, 3'b100, 1'b1);
    slv_check_all("TEST9");
    $display("[INFO] TEST9 (command held while busy) done");

    //-------------------------------------------------------------------------
    // TEST10 : ランダム
    //-------------------------------------------------------------------------
    for( int unsigned n=0; n<N_RAND; n++ ) begin
      if( (n%8)==0 ) begin
        mem_fill_random();
      end
      rand_cmd($sformatf("TEST10 #%0d", n));
    end
    slv_check_all("TEST10");
    $display("[INFO] TEST10 (%0d random commands) done", N_RAND);

    //-------------------------------------------------------------------------
    // TEST11 : コマンド実行中のリセット
    //-------------------------------------------------------------------------
    u_slv.set_wait(WAIT_MAX, WAIT_MAX);
    u_slv.clear_err();
    cmd_valid    = 1'b1;
    cmd_write    = 1'b1;
    cmd_sel      = {SEL_W{1'b0}};
    cmd_addr     = f_waddr(64'(BASE_W));
    cmd_incr     = 1'b1;
    cmd_mem_addr = {MEM_AW{1'b0}};
    cmd_len      = LEN_W'(LMAX);
    cmd_strb     = {STRB_W{1'b1}};
    cmd_prot     = 3'b000;
    @(negedge pclk);
    cmd_valid = 1'b0;
    repeat( 5 ) begin
      @(negedge pclk);
    end
    presetn = 1'b0;
    repeat( 2 ) begin
      @(negedge pclk);
    end
    if( busy||done||(psel!={NUM_SLAVES{1'b0}})||penable||!cmd_ready||!mem_ready||mem_rvalid ) begin
      tb_error($sformatf("TEST11 : outputs during reset : busy=%b done=%b psel=%b penable=%b cmd_ready=%b mem_ready=%b mem_rvalid=%b", busy, done, psel, penable, cmd_ready, mem_ready, mem_rvalid));
    end
    presetn = 1'b1;
    repeat( 2 ) begin
      @(negedge pclk);
    end
    // リセットで途中まで進んだ書き込みは期待値に入れていないので、スレーブ 0 の領域を入れ直す
    u_slv.clear_log();
    for( int unsigned i=0; i<LMAX; i++ ) begin
      exp_smem[f_key(0, f_waddr(64'(BASE_W) + 64'(i)))] = u_slv.peek_word(0, f_waddr(64'(BASE_W) + 64'(i)));
    end
    u_slv.set_wait(0, WAIT_MAX);
    mem_fill_random();
    run_cmd("TEST11 after reset", 1'b1, 0, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX, {STRB_W{1'b1}}, 3'b000, 1'b1);
    mem_fill_random();
    run_cmd("TEST11 after reset", 1'b0, 0, f_waddr(64'(BASE_W)), 1'b1, 0, LMAX, {STRB_W{1'b0}}, 3'b000, 1'b1);
    slv_check_all("TEST11");
    $display("[INFO] TEST11 (reset during a command) done");

    //-------------------------------------------------------------------------
    // 集計
    //-------------------------------------------------------------------------
    repeat( 4 ) begin
      @(negedge pclk);
    end
    if( u_slv.n_viol!=0 ) begin
      tb_error($sformatf("slave model : %0d protocol violation(s)", u_slv.n_viol));
    end
    if( u_slv.n_unaligned!=0 ) begin
      tb_error($sformatf("slave model : %0d transfer(s) with unaligned PADDR", u_slv.n_unaligned));
    end
    if( u_slv.n_abort!=n_abort_exp ) begin
      tb_error($sformatf("slave model : %0d aborted transfer(s) (exp %0d)", u_slv.n_abort, n_abort_exp));
    end
    if( u_dut.u_mem.sim_oor_cnt!=0 ) begin
      tb_error($sformatf("internal memory : %0d out-of-range access(es)", u_dut.u_mem.sim_oor_cnt));
    end
    if( mon_err_cnt!=0 ) begin
      tb_error($sformatf("monitor : %0d error(s)", mon_err_cnt));
    end
    $display("[INFO] commands=%0d (write %0d, read %0d, rejected %0d, empty %0d) with PSLVERR=%0d with timeout=%0d bus transfers=%0d (write %0d, read %0d) aborted=%0d back-to-back=%0d max wait=%0d", n_cmd, n_cmd_wr, n_cmd_rd, n_cmd_bad, n_cmd_empty, n_cmd_slverr, n_cmd_timeout, u_slv.n_xfer, u_slv.n_write, u_slv.n_read, u_slv.n_abort, u_slv.n_b2b, u_slv.max_wait);
    if( err_cnt==0 ) begin
      $display("=== tb_apb_master_mem : TEST PASSED ===");
    end else begin
      $display("=== tb_apb_master_mem : TEST FAILED (%0d errors) ===", err_cnt);
    end
    $finish;
  end

endmodule
