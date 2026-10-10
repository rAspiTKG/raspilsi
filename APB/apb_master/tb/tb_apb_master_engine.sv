//=============================================================================
// tb_apb_master_engine.sv
//-----------------------------------------------------------------------------
//  apb_master_engine の単体テストベンチ (自己チェック)。
//
//  構成:
//    要求の生成 --> apb_master_engine --> apb_slave_mem_model (NUM_SLAVES 個ぶん)
//
//  チェック:
//    - 応答は要求を受けた順に 1 つずつ返る
//    - 要求 1 つにつきバス上の転送が 1 回で、アドレス / 方向 / データ / PSTRB / PPROT /
//      PSEL の番号が要求どおり (スレーブモデルの記録と照合)
//    - rsp_rdata はスレーブが完了サイクルに出していた PRDATA、rsp_slverr はその PSLVERR
//    - 書いたデータを読み直すと同じ値が返る (TB 側の期待メモリと照合)
//    - 存在しないスレーブ番号への要求は、バスに出ずに rsp_slverr=1
//    - タイムアウト : ウェイトが TIMEOUT_CYCLES-1 までは完了し、それ以上は打ち切る
//    - FLUSH_ON_ERROR=1 : エラーの後に受け付けていた要求はバスに出ない
//    - 連続して要求したときに 2 サイクル/転送で流れる (back-to-back)
//    - スレーブモデルのプロトコルチェックが 0 件、PSEL が同時に 2 本立たない
//
//  parameter は Verilator の -G で上書きできる。
//=============================================================================
`timescale 1ns / 1ps

module tb_apb_master_engine #(
  parameter int unsigned ADDR_WIDTH     = 32
 ,parameter int unsigned DATA_WIDTH     = 32
 ,parameter int unsigned NUM_SLAVES     = 1
 ,parameter int unsigned TIMEOUT_CYCLES = 0
 ,parameter bit          FLUSH_ON_ERROR = 1'b0
 ,parameter int unsigned N_REQ          = 300
);

  localparam int unsigned STRB_W      = DATA_WIDTH / 8;
  localparam int unsigned SEL_W       = (NUM_SLAVES<2) ? 1 : $clog2(NUM_SLAVES);
  // テストで使うワード数 (アドレス空間が狭い構成では、その全ワード)
  localparam longint unsigned SPACE_WORDS = (64'd1 << ADDR_WIDTH) / 64'(STRB_W);
  localparam int unsigned N_WORDS     = (SPACE_WORDS<16) ? int'(SPACE_WORDS) : 16;
  localparam int unsigned ERR_WORD    = N_WORDS - 1;    // PSLVERR を返すワード
  localparam int unsigned HANG_WORD   = N_WORDS - 2;    // PREADY を返さないワード (タイムアウトの確認時だけ)
  // 存在しないスレーブ番号を req_sel で表せるか
  localparam bit          HAS_BAD_SEL = ((1<<SEL_W)>NUM_SLAVES);
  // ランダムウェイトの上限 (タイムアウトさせない範囲)
  localparam int unsigned WAIT_MAX    = (TIMEOUT_CYCLES==0) ? 3 : ((TIMEOUT_CYCLES>3) ? 3 : (TIMEOUT_CYCLES-1));
  localparam int unsigned HANG_LIMIT  = 20000;

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
  logic                               req_valid;
  logic                               req_ready;
  logic                               req_write;
  logic [SEL_W-1:0]                   req_sel;
  logic [ADDR_WIDTH-1:0]              req_addr;
  logic [DATA_WIDTH-1:0]              req_wdata;
  logic [STRB_W-1:0]                  req_strb;
  logic [2:0]                         req_prot;
  logic                               rsp_valid;
  logic [DATA_WIDTH-1:0]              rsp_rdata;
  logic                               rsp_slverr;
  logic                               rsp_timeout;
  logic                               busy;
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

  apb_master_engine #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.NUM_SLAVES(NUM_SLAVES)
   ,.TIMEOUT_CYCLES(TIMEOUT_CYCLES)
   ,.FLUSH_ON_ERROR(FLUSH_ON_ERROR)
  ) u_dut (
    .pclk(pclk)
   ,.presetn(presetn)
   ,.req_valid(req_valid)
   ,.req_ready(req_ready)
   ,.req_write(req_write)
   ,.req_sel(req_sel)
   ,.req_addr(req_addr)
   ,.req_wdata(req_wdata)
   ,.req_strb(req_strb)
   ,.req_prot(req_prot)
   ,.rsp_valid(rsp_valid)
   ,.rsp_rdata(rsp_rdata)
   ,.rsp_slverr(rsp_slverr)
   ,.rsp_timeout(rsp_timeout)
   ,.busy(busy)
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
  int unsigned cyc;

  task automatic tb_error( input string msg );
    err_cnt++;
    $display("[%0t] [ERROR] %s", $time, msg);
  endtask

  task automatic abort_test( input string msg );
    $display("[%0t] [ERROR] %s", $time, msg);
    $display("=== tb_apb_master_engine : TEST FAILED (aborted) ===");
    $finish;
  endtask

  always @(posedge pclk) begin
    cyc <= cyc + 1;
  end

  //---------------------------------------------------------------------------
  // 受け付けられ、まだ応答が来ていない要求 (受付順)
  //---------------------------------------------------------------------------
  bit                    acc_write [$];
  int unsigned           acc_sel   [$];
  bit [ADDR_WIDTH-1:0]   acc_addr  [$];
  bit [DATA_WIDTH-1:0]   acc_wdata [$];
  bit [STRB_W-1:0]       acc_strb  [$];
  bit [2:0]              acc_prot  [$];

  // 期待メモリ (キーは {スレーブ番号, アドレス})
  bit [DATA_WIDTH-1:0]   exp_mem [bit [63:0]];

  // 統計
  int unsigned           n_acc;
  int unsigned           n_rsp;
  int unsigned           n_rsp_err;
  int unsigned           n_rsp_to;
  int unsigned           n_rsp_nosel;
  int unsigned           n_dropped;
  int unsigned           n_abort_exp;
  int unsigned           first_fire_cyc;
  int unsigned           last_rsp_cyc;
  bit                    first_fire_seen;
  // このフェーズで、ウェイトだけでタイムアウトするか (wait_min == wait_max >= TIMEOUT_CYCLES)
  bit                    wait_times_out;

  function automatic bit [DATA_WIDTH-1:0] f_exp_peek( input int unsigned s, input bit [ADDR_WIDTH-1:0] a );
    bit [63:0] k;
    k = {32'(s), 32'(a)};
    if( exp_mem.exists(k) ) begin
      return exp_mem[k];
    end
    return {DATA_WIDTH{1'b0}};
  endfunction

  //---------------------------------------------------------------------------
  // モニタ : 要求の受付と応答の照合
  //---------------------------------------------------------------------------
  always @(posedge pclk) begin
    bit                  w;
    int unsigned         s;
    bit [ADDR_WIDTH-1:0] a;
    bit [DATA_WIDTH-1:0] d;
    bit [STRB_W-1:0]     st;
    bit [2:0]            p;
    bit                  exp_to;
    bit [DATA_WIDTH-1:0] m;
    if( presetn ) begin
      // busy は、未応答の要求がある間は 1 (応答のサイクルを除く)
      if( (acc_write.size()>0)&&!busy&&!rsp_valid ) begin
        tb_error("busy=0 while a request is outstanding");
      end
      // PSEL は高々 1 本、PENABLE=1 のときはちょうど 1 本
      if( !$onehot0(psel) ) begin
        tb_error($sformatf("more than one PSEL asserted : %b", psel));
      end
      if( penable&&!$onehot(psel) ) begin
        tb_error($sformatf("PENABLE=1 but PSEL=%b", psel));
      end

      //-----------------------------------------------------------------------
      // 応答
      //-----------------------------------------------------------------------
      if( rsp_valid ) begin
        n_rsp        <= n_rsp + 1;
        last_rsp_cyc <= cyc;
        if( acc_write.size()==0 ) begin
          tb_error("rsp_valid without an outstanding request");
        end else begin
          w  = acc_write.pop_front();
          s  = acc_sel.pop_front();
          a  = acc_addr.pop_front();
          d  = acc_wdata.pop_front();
          st = acc_strb.pop_front();
          p  = acc_prot.pop_front();
          if( s>=NUM_SLAVES ) begin
            // 存在しないスレーブ : バスに出ずにエラー応答
            n_rsp_nosel <= n_rsp_nosel + 1;
            if( !rsp_slverr||rsp_timeout||(rsp_rdata!={DATA_WIDTH{1'b0}}) ) begin
              tb_error($sformatf("response for a non-existent slave %0d : slverr=%b timeout=%b rdata=%h", s, rsp_slverr, rsp_timeout, rsp_rdata));
            end
          end else begin
            exp_to = (TIMEOUT_CYCLES>0)&&(u_slv.f_in_hang(s, a)||wait_times_out);
            if( exp_to ) begin
              n_abort_exp <= n_abort_exp + 1;
              if( !rsp_timeout||rsp_slverr||(rsp_rdata!={DATA_WIDTH{1'b0}}) ) begin
                tb_error($sformatf("expected a timeout : slave %0d addr=%h : slverr=%b timeout=%b rdata=%h", s, a, rsp_slverr, rsp_timeout, rsp_rdata));
              end
            end else begin
              if( rsp_timeout ) begin
                tb_error($sformatf("unexpected timeout : slave %0d addr=%h", s, a));
              end
              if( u_slv.log_slv.size()==0 ) begin
                tb_error($sformatf("response without a bus transfer : slave %0d addr=%h write=%b", s, a, w));
              end else begin
                if( (u_slv.log_slv[0]!=s)||(u_slv.log_addr[0]!=a)||(u_slv.log_write[0]!=w)||(u_slv.log_prot[0]!=p) ) begin
                  tb_error($sformatf("bus transfer mismatch : slave %0d addr=%h write=%b prot=%b (exp slave %0d addr=%h write=%b prot=%b)", u_slv.log_slv[0], u_slv.log_addr[0], u_slv.log_write[0], u_slv.log_prot[0], s, a, w, p));
                end
                if( w&&((u_slv.log_wdata[0]!=d)||(u_slv.log_strb[0]!=st)) ) begin
                  tb_error($sformatf("write data mismatch : PWDATA=%h PSTRB=%b (exp %h %b)", u_slv.log_wdata[0], u_slv.log_strb[0], d, st));
                end
                if( !w&&(u_slv.log_strb[0]!={STRB_W{1'b0}}) ) begin
                  tb_error($sformatf("PSTRB=%b on a read", u_slv.log_strb[0]));
                end
                if( rsp_slverr!=u_slv.log_err[0] ) begin
                  tb_error($sformatf("rsp_slverr=%b (PSLVERR was %b) : slave %0d addr=%h", rsp_slverr, u_slv.log_err[0], s, a));
                end
                if( u_slv.log_err[0]!=u_slv.f_in_err(s,a) ) begin
                  tb_error("slave model : PSLVERR does not match the error range");
                end
                if( w ) begin
                  if( rsp_rdata!={DATA_WIDTH{1'b0}} ) begin
                    tb_error($sformatf("rsp_rdata=%h on a write (exp 0)", rsp_rdata));
                  end
                  if( !u_slv.log_err[0] ) begin
                    // 期待メモリを更新
                    m = f_exp_peek(s, a);
                    for( int unsigned b=0; b<STRB_W; b++ ) begin
                      if( st[b] ) begin
                        m[8*b +: 8] = d[8*b +: 8];
                      end
                    end
                    exp_mem[{32'(s), 32'(a)}] = m;
                  end
                end else begin
                  if( rsp_rdata!=u_slv.log_rdata[0] ) begin
                    tb_error($sformatf("rsp_rdata=%h (PRDATA was %h) : slave %0d addr=%h", rsp_rdata, u_slv.log_rdata[0], s, a));
                  end
                  if( !u_slv.log_err[0]&&(rsp_rdata!=f_exp_peek(s,a)) ) begin
                    tb_error($sformatf("read data mismatch : slave %0d addr=%h : %h (exp %h)", s, a, rsp_rdata, f_exp_peek(s, a)));
                  end
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
              end
            end
          end
        end
        if( rsp_slverr ) begin
          n_rsp_err <= n_rsp_err + 1;
        end
        if( rsp_timeout ) begin
          n_rsp_to <= n_rsp_to + 1;
        end
        // FLUSH_ON_ERROR : エラーの時点で受け付けていた残りの要求は捨てられる
        if( FLUSH_ON_ERROR&&(rsp_slverr||rsp_timeout) ) begin
          if( req_ready ) begin
            tb_error("req_ready=1 in the cycle of an error response (FLUSH_ON_ERROR)");
          end
          n_dropped <= n_dropped + acc_write.size();
          acc_write.delete();
          acc_sel.delete();
          acc_addr.delete();
          acc_wdata.delete();
          acc_strb.delete();
          acc_prot.delete();
        end
      end

      //-----------------------------------------------------------------------
      // 要求の受付
      //-----------------------------------------------------------------------
      if( req_valid&&req_ready ) begin
        n_acc <= n_acc + 1;
        if( !first_fire_seen ) begin
          first_fire_seen <= 1'b1;
          first_fire_cyc  <= cyc;
        end
        acc_write.push_back(req_write);
        acc_sel.push_back(32'(req_sel));
        acc_addr.push_back(req_addr);
        acc_wdata.push_back(req_wdata);
        acc_strb.push_back(req_strb);
        acc_prot.push_back(req_prot);
      end
    end
  end

  //---------------------------------------------------------------------------
  // 要求の生成
  //   gap_pct     : 要求の間に空きサイクルを入れる確率 [%]
  //   bad_sel_pct : 存在しないスレーブ番号にする確率 [%]
  //   use_hang    : ハングするワードも使う
  //---------------------------------------------------------------------------
  task automatic send_reqs( input int unsigned n, input int unsigned gap_pct, input int unsigned bad_sel_pct, input bit use_err, input bit use_hang );
    int unsigned word;
    int unsigned guard;
    for( int unsigned i=0; i<n; i++ ) begin
      while( $urandom_range(99,0)<gap_pct ) begin
        @(negedge pclk);
      end
      // ワード位置 : エラー / ハングのワードは、使うときだけ選ぶ
      word = $urandom_range(N_WORDS-1, 0);
      if( (word==ERR_WORD)&&!use_err ) begin
        word = 0;
      end
      if( (word==HANG_WORD)&&!use_hang ) begin
        word = (N_WORDS>2) ? 1 : 0;
      end
      req_valid = 1'b1;
      req_write = 1'($urandom());
      req_addr  = ADDR_WIDTH'(word * STRB_W);
      req_prot  = 3'($urandom());
      req_strb  = STRB_W'($urandom());
      for( int unsigned b=0; b<DATA_WIDTH; b++ ) begin
        req_wdata[b] = 1'($urandom());
      end
      if( HAS_BAD_SEL&&($urandom_range(99,0)<bad_sel_pct) ) begin
        req_sel = SEL_W'($urandom_range((1<<SEL_W)-1, NUM_SLAVES));
      end else begin
        req_sel = SEL_W'($urandom_range(NUM_SLAVES-1, 0));
      end
      // 握手を待つ
      guard = 0;
      @(posedge pclk);
      while( !req_ready ) begin
        guard++;
        if( guard>HANG_LIMIT ) begin
          abort_test("req_ready did not rise");
        end
        @(posedge pclk);
      end
      @(negedge pclk);
      req_valid = 1'b0;
    end
  endtask

  // 全ての応答が返り、エンジンが止まるまで待つ
  task automatic drain();
    int unsigned guard;
    guard = 0;
    @(negedge pclk);
    while( (acc_write.size()>0)||busy||rsp_valid ) begin
      guard++;
      if( guard>HANG_LIMIT ) begin
        abort_test("engine did not become idle");
      end
      @(negedge pclk);
    end
    repeat( 3 ) begin
      @(negedge pclk);
    end
    if( u_slv.log_slv.size()!=0 ) begin
      tb_error($sformatf("%0d bus transfer(s) without a response", u_slv.log_slv.size()));
      u_slv.clear_log();
    end
    if( psel!={NUM_SLAVES{1'b0}} ) begin
      tb_error("PSEL is not 0 after all transfers");
    end
    if( penable ) begin
      tb_error("PENABLE is not 0 after all transfers");
    end
  endtask

  task automatic set_err( input bit en_err, input bit en_hang );
    u_slv.clear_err();
    for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
      if( en_err ) begin
        u_slv.err_lo[s] = ADDR_WIDTH'(ERR_WORD * STRB_W);
        u_slv.err_hi[s] = ADDR_WIDTH'((ERR_WORD * STRB_W) + (STRB_W-1));
      end
      if( en_hang ) begin
        u_slv.hang_lo[s] = ADDR_WIDTH'(HANG_WORD * STRB_W);
        u_slv.hang_hi[s] = ADDR_WIDTH'((HANG_WORD * STRB_W) + (STRB_W-1));
      end
    end
  endtask

  //---------------------------------------------------------------------------
  // テスト本体
  //---------------------------------------------------------------------------
  int unsigned acc0;
  int unsigned rsp0;

  initial begin
    err_cnt         = 0;
    cyc             = 0;
    n_acc           = 0;
    n_rsp           = 0;
    n_rsp_err       = 0;
    n_rsp_to        = 0;
    n_rsp_nosel     = 0;
    n_dropped       = 0;
    n_abort_exp     = 0;
    first_fire_seen = 1'b0;
    first_fire_cyc  = 0;
    last_rsp_cyc    = 0;
    wait_times_out  = 1'b0;
    req_valid       = 1'b0;
    req_write       = 1'b0;
    req_sel         = {SEL_W{1'b0}};
    req_addr        = {ADDR_WIDTH{1'b0}};
    req_wdata       = {DATA_WIDTH{1'b0}};
    req_strb        = {STRB_W{1'b0}};
    req_prot        = 3'b000;
    presetn         = 1'b0;
    repeat( 5 ) begin
      @(negedge pclk);
    end
    presetn = 1'b1;
    repeat( 3 ) begin
      @(negedge pclk);
    end
    $display("[INFO] ADDR_WIDTH=%0d DATA_WIDTH=%0d NUM_SLAVES=%0d TIMEOUT_CYCLES=%0d FLUSH_ON_ERROR=%0d (words used per slave = %0d)", ADDR_WIDTH, DATA_WIDTH, NUM_SLAVES, TIMEOUT_CYCLES, FLUSH_ON_ERROR, N_WORDS);

    //-------------------------------------------------------------------------
    // PHASE1 : 連続要求、ウェイト無し、エラー無し → 2 サイクル/転送で流れること
    //-------------------------------------------------------------------------
    u_slv.set_wait(0, 0);
    set_err(1'b0, 1'b0);
    first_fire_seen = 1'b0;
    acc0 = n_acc;
    rsp0 = n_rsp;
    send_reqs(N_REQ, 0, 0, 1'b0, 1'b0);
    drain();
    if( (n_rsp-rsp0)!=N_REQ ) begin
      tb_error($sformatf("PHASE1 : %0d responses (exp %0d)", n_rsp-rsp0, N_REQ));
    end
    if( (last_rsp_cyc-first_fire_cyc)!=((2*N_REQ)+1) ) begin
      tb_error($sformatf("PHASE1 : %0d transfers took %0d cycles (exp %0d = 2 cycles per transfer)", N_REQ, last_rsp_cyc-first_fire_cyc, (2*N_REQ)+1));
    end
    $display("[INFO] PHASE1 (back-to-back) done : %0d transfers in %0d cycles", N_REQ, last_rsp_cyc-first_fire_cyc);

    //-------------------------------------------------------------------------
    // PHASE2 : ランダムな間隔 + ウェイト + PSLVERR + 存在しないスレーブ番号
    //-------------------------------------------------------------------------
    u_slv.set_wait(0, WAIT_MAX);
    set_err(1'b1, 1'b0);
    send_reqs(N_REQ, 40, 10, 1'b1, 1'b0);
    drain();
    $display("[INFO] PHASE2 (gaps / wait states / PSLVERR / bad slave number) done");

    //-------------------------------------------------------------------------
    // PHASE3 : 連続要求 + ウェイト + PSLVERR (保留レジスタを使い続ける)
    //-------------------------------------------------------------------------
    send_reqs(N_REQ, 0, 10, 1'b1, 1'b0);
    drain();
    $display("[INFO] PHASE3 (continuous requests with wait states and errors) done");

    //-------------------------------------------------------------------------
    // PHASE4 : タイムアウト
    //-------------------------------------------------------------------------
    if( TIMEOUT_CYCLES>0 ) begin
      // 4a : ウェイト = TIMEOUT_CYCLES-1 (上限ちょうど) → 全て完了する
      u_slv.set_wait(TIMEOUT_CYCLES-1, TIMEOUT_CYCLES-1);
      set_err(1'b1, 1'b0);
      rsp0 = n_rsp_to;
      send_reqs(20, 30, 0, 1'b1, 1'b0);
      drain();
      if( n_rsp_to!=rsp0 ) begin
        tb_error("PHASE4a : timeout with wait = TIMEOUT_CYCLES-1");
      end
      // 4b : ウェイト = TIMEOUT_CYCLES → 全て打ち切る
      u_slv.set_wait(TIMEOUT_CYCLES, TIMEOUT_CYCLES);
      wait_times_out = 1'b1;
      rsp0 = n_rsp_to;
      acc0 = n_rsp;
      send_reqs(20, 30, 0, 1'b0, 1'b0);
      drain();
      wait_times_out = 1'b0;
      if( (n_rsp_to-rsp0)!=(n_rsp-acc0) ) begin
        tb_error($sformatf("PHASE4b : %0d timeouts in %0d responses", n_rsp_to-rsp0, n_rsp-acc0));
      end
      // 4c : ハングするワード + ランダムウェイト + PSLVERR
      u_slv.set_wait(0, WAIT_MAX);
      set_err(1'b1, 1'b1);
      send_reqs(N_REQ, 20, 10, 1'b1, 1'b1);
      drain();
      $display("[INFO] PHASE4 (timeout) done : %0d timeouts", n_rsp_to);
    end

    //-------------------------------------------------------------------------
    // 集計
    //-------------------------------------------------------------------------
    if( u_slv.n_viol!=0 ) begin
      tb_error($sformatf("slave model : %0d protocol violation(s)", u_slv.n_viol));
    end
    if( u_slv.n_abort!=n_abort_exp ) begin
      tb_error($sformatf("slave model : %0d aborted transfer(s) (exp %0d)", u_slv.n_abort, n_abort_exp));
    end
    if( n_abort_exp!=n_rsp_to ) begin
      tb_error($sformatf("%0d timeout responses, %0d expected", n_rsp_to, n_abort_exp));
    end
    if( n_acc!=(n_rsp+n_dropped) ) begin
      tb_error($sformatf("accepted %0d != responses %0d + dropped %0d", n_acc, n_rsp, n_dropped));
    end
    if( !FLUSH_ON_ERROR&&(n_dropped!=0) ) begin
      tb_error("requests were dropped although FLUSH_ON_ERROR=0");
    end
    if( u_slv.n_xfer!=(n_rsp-n_rsp_to-n_rsp_nosel) ) begin
      tb_error($sformatf("bus transfers %0d != responses %0d - timeouts %0d - bad slave %0d", u_slv.n_xfer, n_rsp, n_rsp_to, n_rsp_nosel));
    end
    $display("[INFO] requests=%0d responses=%0d (PSLVERR %0d, timeout %0d, bad slave %0d) dropped=%0d bus transfers=%0d (write %0d, read %0d) back-to-back=%0d max wait=%0d", n_acc, n_rsp, n_rsp_err, n_rsp_to, n_rsp_nosel, n_dropped, u_slv.n_xfer, u_slv.n_write, u_slv.n_read, u_slv.n_b2b, u_slv.max_wait);
    if( err_cnt==0 ) begin
      $display("=== tb_apb_master_engine : TEST PASSED ===");
    end else begin
      $display("=== tb_apb_master_engine : TEST FAILED (%0d errors) ===", err_cnt);
    end
    $finish;
  end

endmodule
