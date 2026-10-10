//=============================================================================
// tb_axil_master_engine.sv
//-----------------------------------------------------------------------------
//  axil_master_engine の単体テストベンチ (自己チェック)。
//
//  構成:
//    書き込み要求 / 読み出し要求 (別プロセスで同時に出す) --> axil_master_engine --> axil_slave_mem_model
//
//  チェック:
//    - 応答は要求を受けた順に 1 つずつ返り、スレーブが受け取ったトランザクション
//      (アドレス / PROT / データ / WSTRB) が要求どおり。応答の種類も一致
//    - 読み出しデータが期待値 (テストベンチ側のメモリ) と一致
//    - wr_busy / rd_busy / axi_wakeup が「受け付けて、まだ応答を受けていない要求がある」と一致
//      (AWVALID / ARVALID が 1 のときは axi_wakeup も必ず 1)
//    - 未完了の要求数が MAX_*_OUTSTANDING を超えず、上限まで使われる
//    - 理想的なスレーブ (READY が常に 1、応答の遅延 0) で、要求を受け付けるサイクルが期待どおり
//      (MAX_*_OUTSTANDING が 3 以上なら毎サイクル。読み書きは同時に動く)
//    - スレーブモデルのプロトコルチェックが 0 件、非アラインのアドレスが 0 件
//
//  parameter は Verilator の -G で上書きできる。
//=============================================================================
`timescale 1ns / 1ps

module tb_axil_master_engine #(
  parameter int unsigned ADDR_WIDTH         = 32
 ,parameter int unsigned DATA_WIDTH         = 32
 ,parameter int unsigned MAX_WR_OUTSTANDING = 4
 ,parameter int unsigned MAX_RD_OUTSTANDING = 4
 ,parameter int unsigned N_REQ              = 300
);

  localparam int unsigned STRB_W      = DATA_WIDTH / 8;
  localparam int unsigned STRB_LSB    = $clog2(STRB_W);
  // アドレス空間のワード数 (64 ワード以上あれば 64 ワードだけ使う)
  localparam longint unsigned SPACE_WORDS = (ADDR_WIDTH-STRB_LSB>=20) ? (64'd1 << 20) : (64'd1 << (ADDR_WIDTH-STRB_LSB));
  localparam int unsigned N_WORDS     = (SPACE_WORDS<64) ? int'(SPACE_WORDS) : 64;
  // 読み書きを同時に流すときは、前半を書き込み、後半を読み出しに使う (同じアドレスの読み書きの順序は決まらないため)
  localparam int unsigned HALF        = (N_WORDS<2) ? 1 : (N_WORDS / 2);
  localparam int unsigned HANG_LIMIT  = 100000;

  //---------------------------------------------------------------------------
  // クロック / リセット
  //---------------------------------------------------------------------------
  logic aclk;
  logic aresetn;

  initial begin
    aclk = 1'b0;
    forever begin
      #5 aclk = ~aclk;
    end
  end

  //---------------------------------------------------------------------------
  // DUT
  //---------------------------------------------------------------------------
  logic                  wreq_valid;
  logic                  wreq_ready;
  logic [ADDR_WIDTH-1:0] wreq_addr;
  logic [DATA_WIDTH-1:0] wreq_data;
  logic [STRB_W-1:0]     wreq_strb;
  logic [2:0]            wreq_prot;
  logic                  wrsp_valid;
  logic [1:0]            wrsp_resp;
  logic                  rreq_valid;
  logic                  rreq_ready;
  logic [ADDR_WIDTH-1:0] rreq_addr;
  logic [2:0]            rreq_prot;
  logic                  rrsp_valid;
  logic [DATA_WIDTH-1:0] rrsp_data;
  logic [1:0]            rrsp_resp;
  logic                  wr_busy;
  logic                  rd_busy;
  logic                  axi_wakeup;
  logic [ADDR_WIDTH-1:0] awaddr;
  logic [2:0]            awprot;
  logic                  awvalid;
  logic                  awready;
  logic [DATA_WIDTH-1:0] wdata;
  logic [STRB_W-1:0]     wstrb;
  logic                  wvalid;
  logic                  wready;
  logic [1:0]            bresp;
  logic                  bvalid;
  logic                  bready;
  logic [ADDR_WIDTH-1:0] araddr;
  logic [2:0]            arprot;
  logic                  arvalid;
  logic                  arready;
  logic [DATA_WIDTH-1:0] rdata;
  logic [1:0]            rresp;
  logic                  rvalid;
  logic                  rready;

  axil_master_engine #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.MAX_WR_OUTSTANDING(MAX_WR_OUTSTANDING)
   ,.MAX_RD_OUTSTANDING(MAX_RD_OUTSTANDING)
  ) u_dut (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.wreq_valid(wreq_valid)
   ,.wreq_ready(wreq_ready)
   ,.wreq_addr(wreq_addr)
   ,.wreq_data(wreq_data)
   ,.wreq_strb(wreq_strb)
   ,.wreq_prot(wreq_prot)
   ,.wrsp_valid(wrsp_valid)
   ,.wrsp_resp(wrsp_resp)
   ,.rreq_valid(rreq_valid)
   ,.rreq_ready(rreq_ready)
   ,.rreq_addr(rreq_addr)
   ,.rreq_prot(rreq_prot)
   ,.rrsp_valid(rrsp_valid)
   ,.rrsp_data(rrsp_data)
   ,.rrsp_resp(rrsp_resp)
   ,.wr_busy(wr_busy)
   ,.rd_busy(rd_busy)
   ,.axi_wakeup(axi_wakeup)
   ,.m_axi_awaddr(awaddr)
   ,.m_axi_awprot(awprot)
   ,.m_axi_awvalid(awvalid)
   ,.m_axi_awready(awready)
   ,.m_axi_wdata(wdata)
   ,.m_axi_wstrb(wstrb)
   ,.m_axi_wvalid(wvalid)
   ,.m_axi_wready(wready)
   ,.m_axi_bresp(bresp)
   ,.m_axi_bvalid(bvalid)
   ,.m_axi_bready(bready)
   ,.m_axi_araddr(araddr)
   ,.m_axi_arprot(arprot)
   ,.m_axi_arvalid(arvalid)
   ,.m_axi_arready(arready)
   ,.m_axi_rdata(rdata)
   ,.m_axi_rresp(rresp)
   ,.m_axi_rvalid(rvalid)
   ,.m_axi_rready(rready)
  );

  axil_slave_mem_model #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.MAX_WR_OUTSTANDING(MAX_WR_OUTSTANDING)
   ,.MAX_RD_OUTSTANDING(MAX_RD_OUTSTANDING)
  ) u_slv (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.awaddr(awaddr)
   ,.awprot(awprot)
   ,.awvalid(awvalid)
   ,.awready(awready)
   ,.wdata(wdata)
   ,.wstrb(wstrb)
   ,.wvalid(wvalid)
   ,.wready(wready)
   ,.bresp(bresp)
   ,.bvalid(bvalid)
   ,.bready(bready)
   ,.araddr(araddr)
   ,.arprot(arprot)
   ,.arvalid(arvalid)
   ,.arready(arready)
   ,.rdata(rdata)
   ,.rresp(rresp)
   ,.rvalid(rvalid)
   ,.rready(rready)
  );

  //---------------------------------------------------------------------------
  // エラー集計
  //---------------------------------------------------------------------------
  int unsigned err_cnt;
  int unsigned cyc = 0;

  task automatic tb_error( input string msg );
    err_cnt++;
    $display("[%0t] [ERROR] %s", $time, msg);
  endtask

  task automatic abort_test( input string msg );
    $display("[%0t] [ERROR] %s", $time, msg);
    $display("=== tb_axil_master_engine : TEST FAILED (aborted) ===");
    $finish;
  endtask

  always @(posedge aclk) begin
    cyc <= cyc + 1;
  end

  //---------------------------------------------------------------------------
  // 期待値
  //---------------------------------------------------------------------------
  bit [DATA_WIDTH-1:0] exp_mem [bit [63:0]];     // スレーブのメモリの期待値 (書き込みの応答で更新)

  // 受け付けた要求 (応答の照合に使う)
  bit [63:0]           wq_addr [$];
  bit [DATA_WIDTH-1:0] wq_data [$];
  bit [STRB_W-1:0]     wq_strb [$];
  bit [2:0]            wq_prot [$];
  bit [63:0]           rq_addr [$];
  bit [2:0]            rq_prot [$];

  // 統計
  int unsigned n_wacc;
  int unsigned n_racc;
  int unsigned n_wrsp;
  int unsigned n_rrsp;
  int unsigned n_wrsp_err;
  int unsigned n_rrsp_err;
  int unsigned max_wcnt;
  int unsigned max_rcnt;
  // 要求を受け付けたサイクル (スループットの確認用)
  int unsigned wacc_cyc [$];
  int unsigned racc_cyc [$];
  bit          rec_cyc;

  function automatic bit [DATA_WIDTH-1:0] f_rand_data();
    bit [DATA_WIDTH-1:0] d;
    for( int unsigned i=0; i<DATA_WIDTH; i++ ) begin
      d[i] = 1'($urandom());
    end
    return d;
  endfunction

  function automatic bit [ADDR_WIDTH-1:0] f_waddr( input int unsigned w );
    return ADDR_WIDTH'(64'(w) << STRB_LSB);
  endfunction

  function automatic bit [DATA_WIDTH-1:0] f_exp( input bit [63:0] a );
    if( exp_mem.exists(a) ) begin
      return exp_mem[a];
    end
    return {DATA_WIDTH{1'b0}};
  endfunction

  // 期待される応答 (スレーブのエラー範囲は、要求を出している間は変えない)
  function automatic bit [1:0] f_exp_wresp( input bit [63:0] a );
    return u_slv.f_wresp(a);
  endfunction

  function automatic bit [1:0] f_exp_rresp( input bit [63:0] a );
    return u_slv.f_rresp(a);
  endfunction

  //---------------------------------------------------------------------------
  // 受け付け / 応答の監視と照合
  //   要求の受け付けと AXI のハンドシェイクは posedge で数え、ステータスは negedge で照合する
  //---------------------------------------------------------------------------
  int unsigned tb_wcnt;     // 受け付けて、まだ B を受けていない要求の数
  int unsigned tb_rcnt;

  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      tb_wcnt <= 0;
      tb_rcnt <= 0;
    end else begin
      tb_wcnt <= tb_wcnt + ((wreq_valid&&wreq_ready) ? 1 : 0) - ((bvalid&&bready) ? 1 : 0);
      tb_rcnt <= tb_rcnt + ((rreq_valid&&rreq_ready) ? 1 : 0) - ((rvalid&&rready) ? 1 : 0);
      if( wreq_valid&&wreq_ready ) begin
        wq_addr.push_back(64'(wreq_addr));
        wq_data.push_back(wreq_data);
        wq_strb.push_back(wreq_strb);
        wq_prot.push_back(wreq_prot);
        n_wacc++;
        if( rec_cyc ) begin
          wacc_cyc.push_back(cyc);
        end
      end
      if( rreq_valid&&rreq_ready ) begin
        rq_addr.push_back(64'(rreq_addr));
        rq_prot.push_back(rreq_prot);
        n_racc++;
        if( rec_cyc ) begin
          racc_cyc.push_back(cyc);
        end
      end
    end
  end

  always @(negedge aclk) begin
    bit [63:0]           a;
    bit [DATA_WIDTH-1:0] m;
    if( aresetn ) begin
      // ステータス
      if( wr_busy!==(tb_wcnt!=0) ) begin
        tb_error($sformatf("wr_busy=%b while %0d write(s) are outstanding", wr_busy, tb_wcnt));
      end
      if( rd_busy!==(tb_rcnt!=0) ) begin
        tb_error($sformatf("rd_busy=%b while %0d read(s) are outstanding", rd_busy, tb_rcnt));
      end
      if( axi_wakeup!==((tb_wcnt!=0)||(tb_rcnt!=0)) ) begin
        tb_error($sformatf("axi_wakeup=%b while %0d write(s) and %0d read(s) are outstanding", axi_wakeup, tb_wcnt, tb_rcnt));
      end
      if( (awvalid||arvalid)&&!axi_wakeup ) begin
        tb_error("AWVALID / ARVALID is 1 while axi_wakeup=0");
      end
      if( (tb_wcnt>MAX_WR_OUTSTANDING)||(tb_rcnt>MAX_RD_OUTSTANDING) ) begin
        tb_error($sformatf("outstanding requests %0d / %0d exceed the limit %0d / %0d", tb_wcnt, tb_rcnt, MAX_WR_OUTSTANDING, MAX_RD_OUTSTANDING));
      end
      if( tb_wcnt>max_wcnt ) begin
        max_wcnt = tb_wcnt;
      end
      if( tb_rcnt>max_rcnt ) begin
        max_rcnt = tb_rcnt;
      end
      if( (bready!==1'b1)||(rready!==1'b1) ) begin
        tb_error($sformatf("BREADY=%b RREADY=%b (expected to be always 1)", bready, rready));
      end
      // 書き込み応答
      if( wrsp_valid ) begin
        n_wrsp++;
        if( wq_addr.size()==0 ) begin
          tb_error("write response without an accepted request");
        end else if( u_slv.wlog_addr.size()==0 ) begin
          tb_error($sformatf("write response without a completed bus transaction (addr=%h)", wq_addr[0]));
        end else begin
          a = wq_addr[0];
          if( (u_slv.wlog_addr[0]!=a)||(u_slv.wlog_prot[0]!=wq_prot[0])||(u_slv.wlog_data[0]!=wq_data[0])||(u_slv.wlog_strb[0]!=wq_strb[0]) ) begin
            tb_error($sformatf("write transaction mismatch : addr=%h prot=%b data=%h strb=%b (exp addr=%h prot=%b data=%h strb=%b)", u_slv.wlog_addr[0], u_slv.wlog_prot[0], u_slv.wlog_data[0], u_slv.wlog_strb[0], a, wq_prot[0], wq_data[0], wq_strb[0]));
          end
          if( wrsp_resp!==u_slv.wlog_resp[0] ) begin
            tb_error($sformatf("wrsp_resp=%b (BRESP was %b) : addr=%h", wrsp_resp, u_slv.wlog_resp[0], a));
          end
          if( u_slv.wlog_resp[0]!=f_exp_wresp(a) ) begin
            tb_error("slave model : BRESP does not match the error range");
          end
          if( wrsp_resp!=2'b00 ) begin
            n_wrsp_err++;
          end else begin
            m = f_exp(a);
            for( int unsigned b=0; b<STRB_W; b++ ) begin
              if( wq_strb[0][b] ) begin
                m[8*b +: 8] = wq_data[0][8*b +: 8];
              end
            end
            exp_mem[a] = m;
          end
          void'(u_slv.wlog_addr.pop_front());
          void'(u_slv.wlog_prot.pop_front());
          void'(u_slv.wlog_data.pop_front());
          void'(u_slv.wlog_strb.pop_front());
          void'(u_slv.wlog_resp.pop_front());
          void'(wq_addr.pop_front());
          void'(wq_data.pop_front());
          void'(wq_strb.pop_front());
          void'(wq_prot.pop_front());
        end
      end
      // 読み出し応答
      if( rrsp_valid ) begin
        n_rrsp++;
        if( rq_addr.size()==0 ) begin
          tb_error("read response without an accepted request");
        end else if( u_slv.rlog_addr.size()==0 ) begin
          tb_error($sformatf("read response without a completed bus transaction (addr=%h)", rq_addr[0]));
        end else begin
          a = rq_addr[0];
          if( (u_slv.rlog_addr[0]!=a)||(u_slv.rlog_prot[0]!=rq_prot[0]) ) begin
            tb_error($sformatf("read transaction mismatch : addr=%h prot=%b (exp addr=%h prot=%b)", u_slv.rlog_addr[0], u_slv.rlog_prot[0], a, rq_prot[0]));
          end
          if( rrsp_resp!==u_slv.rlog_resp[0] ) begin
            tb_error($sformatf("rrsp_resp=%b (RRESP was %b) : addr=%h", rrsp_resp, u_slv.rlog_resp[0], a));
          end
          if( u_slv.rlog_resp[0]!=f_exp_rresp(a) ) begin
            tb_error("slave model : RRESP does not match the error range");
          end
          if( rrsp_resp!=2'b00 ) begin
            n_rrsp_err++;
          end else begin
            if( rrsp_data!==u_slv.rlog_data[0] ) begin
              tb_error($sformatf("rrsp_data=%h (RDATA was %h) : addr=%h", rrsp_data, u_slv.rlog_data[0], a));
            end
            if( rrsp_data!==f_exp(a) ) begin
              tb_error($sformatf("read data mismatch : addr=%h : %h (exp %h)", a, rrsp_data, f_exp(a)));
            end
          end
          void'(u_slv.rlog_addr.pop_front());
          void'(u_slv.rlog_prot.pop_front());
          void'(u_slv.rlog_data.pop_front());
          void'(u_slv.rlog_resp.pop_front());
          void'(rq_addr.pop_front());
          void'(rq_prot.pop_front());
        end
      end
    end
  end

  //---------------------------------------------------------------------------
  // 要求の生成
  //   negedge で出し、ready (レジスタだけで決まる) を見て、次の posedge で受け付けられる
  //---------------------------------------------------------------------------
  // 書き込みを n 個。ワード位置は [w0, w0+nw) の乱数、間を gap_pct の確率で空ける
  task automatic send_writes( input int unsigned n, input int unsigned w0, input int unsigned nw, input int unsigned gap_pct );
    int unsigned guard;
    for( int unsigned i=0; i<n; i++ ) begin
      while( $urandom_range(99,0)<gap_pct ) begin
        wreq_valid = 1'b0;
        @(negedge aclk);
      end
      wreq_valid = 1'b1;
      wreq_addr  = f_waddr(w0 + $urandom_range(nw-1, 0));
      wreq_data  = f_rand_data();
      if( $urandom_range(3,0)==0 ) begin
        wreq_strb = STRB_W'($urandom());
      end else begin
        wreq_strb = {STRB_W{1'b1}};
      end
      wreq_prot  = 3'($urandom());
      guard      = 0;
      while( !wreq_ready ) begin
        guard++;
        if( guard>HANG_LIMIT ) begin
          abort_test("wreq_ready did not rise");
        end
        @(negedge aclk);
      end
      @(negedge aclk);
    end
    wreq_valid = 1'b0;
  endtask

  task automatic send_reads( input int unsigned n, input int unsigned w0, input int unsigned nw, input int unsigned gap_pct );
    int unsigned guard;
    for( int unsigned i=0; i<n; i++ ) begin
      while( $urandom_range(99,0)<gap_pct ) begin
        rreq_valid = 1'b0;
        @(negedge aclk);
      end
      rreq_valid = 1'b1;
      rreq_addr  = f_waddr(w0 + $urandom_range(nw-1, 0));
      rreq_prot  = 3'($urandom());
      guard      = 0;
      while( !rreq_ready ) begin
        guard++;
        if( guard>HANG_LIMIT ) begin
          abort_test("rreq_ready did not rise");
        end
        @(negedge aclk);
      end
      @(negedge aclk);
    end
    rreq_valid = 1'b0;
  endtask

  // 全ての応答を待つ
  task automatic wait_idle( input string tag );
    int unsigned guard;
    guard = 0;
    while( (n_wrsp!=n_wacc)||(n_rrsp!=n_racc) ) begin
      guard++;
      if( guard>HANG_LIMIT ) begin
        abort_test({tag, " : responses did not arrive"});
      end
      @(negedge aclk);
    end
    repeat( 2 ) begin
      @(negedge aclk);
    end
    if( wr_busy||rd_busy||axi_wakeup||awvalid||wvalid||arvalid ) begin
      tb_error($sformatf("%s : not idle after all responses (wr_busy=%b rd_busy=%b axi_wakeup=%b AWVALID=%b WVALID=%b ARVALID=%b)", tag, wr_busy, rd_busy, axi_wakeup, awvalid, wvalid, arvalid));
    end
  endtask

  // スレーブのメモリと期待値に、同じ乱数を入れる
  task automatic fill_words( input int unsigned w0, input int unsigned nw );
    bit [DATA_WIDTH-1:0] d;
    for( int unsigned i=0; i<nw; i++ ) begin
      d = f_rand_data();
      u_slv.poke_word(64'(f_waddr(w0 + i)), d);
      exp_mem[64'(f_waddr(w0 + i))] = d;
    end
  endtask

  // スレーブの振る舞いを乱数で決める
  task automatic rand_slave();
    u_slv.set_ready($urandom_range(100, 20), $urandom_range(100, 20), $urandom_range(100, 20));
    u_slv.set_lat(0, $urandom_range(6, 0), 0, $urandom_range(6, 0));
  endtask

  // 書き込み / 読み出しのエラー範囲 (2 つずつ) を乱数で決める (範囲は 1〜4 ワード、応答の種類も乱数)
  task automatic rand_err( input int unsigned w0w, input int unsigned nww, input int unsigned w0r, input int unsigned nwr );
    int unsigned k;
    for( int unsigned i=0; i<2; i++ ) begin
      k = $urandom_range(nww-1, 0);
      u_slv.set_werr(i, 2'($urandom_range(3, 1)), 64'(f_waddr(w0w + k)), 64'(f_waddr(w0w + k + $urandom_range(3, 0))) + 64'(STRB_W-1));
      k = $urandom_range(nwr-1, 0);
      u_slv.set_rerr(i, 2'($urandom_range(3, 1)), 64'(f_waddr(w0r + k)), 64'(f_waddr(w0r + k + $urandom_range(3, 0))) + 64'(STRB_W-1));
    end
  endtask

  // 理想的なスレーブで、i 番目の要求を受け付けるサイクル (最初の要求から数えて)
  //   受け付けてから B / R を受けるまで 3 サイクルかかるので、上限 MAX が 3 未満なら
  //   MAX 個ずつ 3 サイクルごと、3 以上なら毎サイクル
  function automatic int unsigned f_acc( input int unsigned i, input int unsigned max_out );
    if( max_out>=3 ) begin
      return i;
    end
    return (3 * (i / max_out)) + (i % max_out);
  endfunction

  //---------------------------------------------------------------------------
  // テスト本体
  //---------------------------------------------------------------------------
  int unsigned nmax;
  int unsigned nbad;

  initial begin
    err_cnt    = 0;
    n_wacc     = 0;
    n_racc     = 0;
    n_wrsp     = 0;
    n_rrsp     = 0;
    n_wrsp_err = 0;
    n_rrsp_err = 0;
    max_wcnt   = 0;
    max_rcnt   = 0;
    rec_cyc    = 1'b0;
    wreq_valid = 1'b0;
    wreq_addr  = {ADDR_WIDTH{1'b0}};
    wreq_data  = {DATA_WIDTH{1'b0}};
    wreq_strb  = {STRB_W{1'b0}};
    wreq_prot  = 3'b000;
    rreq_valid = 1'b0;
    rreq_addr  = {ADDR_WIDTH{1'b0}};
    rreq_prot  = 3'b000;
    aresetn    = 1'b0;
    repeat( 5 ) begin
      @(negedge aclk);
    end
    aresetn = 1'b1;
    repeat( 3 ) begin
      @(negedge aclk);
    end
    $display("[INFO] ADDR_WIDTH=%0d DATA_WIDTH=%0d MAX_WR_OUTSTANDING=%0d MAX_RD_OUTSTANDING=%0d (words used = %0d)", ADDR_WIDTH, DATA_WIDTH, MAX_WR_OUTSTANDING, MAX_RD_OUTSTANDING, N_WORDS);
    if( N_WORDS<4 ) begin
      abort_test("this testbench needs an address space of 4 words or more (ADDR_WIDTH >= log2(DATA_WIDTH/8)+2)");
    end
    fill_words(0, N_WORDS);

    //-------------------------------------------------------------------------
    // PHASE1 : 理想的なスレーブで、書き込みと読み出しを同時に連続して出す
    //          要求を受け付けるサイクルが期待どおりであること (読み書きは互いに影響しない)
    //-------------------------------------------------------------------------
    u_slv.set_ready(100, 100, 100);
    u_slv.set_lat(0, 0, 0, 0);
    rec_cyc = 1'b1;
    fork
      begin
        send_writes(N_REQ, 0, HALF, 0);
      end
      begin
        send_reads(N_REQ, HALF, N_WORDS - HALF, 0);
      end
    join
    wait_idle("PHASE1");
    rec_cyc = 1'b0;
    nbad = 0;
    for( int unsigned i=0; i<wacc_cyc.size(); i++ ) begin
      if( (wacc_cyc[i]-wacc_cyc[0])!=f_acc(i,MAX_WR_OUTSTANDING) ) begin
        nbad++;
        if( nbad<=4 ) begin
          tb_error($sformatf("PHASE1 : write request %0d was accepted %0d cycles after the first (exp %0d)", i, wacc_cyc[i]-wacc_cyc[0], f_acc(i, MAX_WR_OUTSTANDING)));
        end
      end
    end
    for( int unsigned i=0; i<racc_cyc.size(); i++ ) begin
      if( (racc_cyc[i]-racc_cyc[0])!=f_acc(i,MAX_RD_OUTSTANDING) ) begin
        nbad++;
        if( nbad<=4 ) begin
          tb_error($sformatf("PHASE1 : read request %0d was accepted %0d cycles after the first (exp %0d)", i, racc_cyc[i]-racc_cyc[0], f_acc(i, MAX_RD_OUTSTANDING)));
        end
      end
    end
    if( (wacc_cyc.size()!=N_REQ)||(racc_cyc.size()!=N_REQ)||(wacc_cyc[0]!=racc_cyc[0]) ) begin
      tb_error($sformatf("PHASE1 : %0d writes / %0d reads accepted, first at cycle %0d / %0d (exp %0d each, same cycle)", wacc_cyc.size(), racc_cyc.size(), wacc_cyc[0], racc_cyc[0], N_REQ));
    end
    if( u_slv.n_both==0 ) begin
      tb_error("PHASE1 : writes and reads were never outstanding at the same time");
    end
    $display("[INFO] PHASE1 (back-to-back, writes and reads at the same time) done : %0d + %0d requests in %0d / %0d cycles", N_REQ, N_REQ, wacc_cyc[N_REQ-1]-wacc_cyc[0]+1, racc_cyc[N_REQ-1]-racc_cyc[0]+1);

    //-------------------------------------------------------------------------
    // PHASE2 : READY / 応答の遅延 / エラー応答を乱数にして、読み書きを同時に (間を空けながら)
    //-------------------------------------------------------------------------
    for( int unsigned p=0; p<6; p++ ) begin
      rand_slave();
      rand_err(0, HALF, HALF, N_WORDS - HALF);
      fork
        begin
          send_writes(N_REQ / 6, 0, HALF, (p%2)*30);
        end
        begin
          send_reads(N_REQ / 6, HALF, N_WORDS - HALF, (p%3)*20);
        end
      join
      wait_idle("PHASE2");
    end
    u_slv.clear_err();
    $display("[INFO] PHASE2 (random READY / latency / error responses) done");

    //-------------------------------------------------------------------------
    // PHASE3 : AWREADY は W が来てから / WREADY は AW が来てから
    //          (AW と W を独立に出していなければデッドロックする)
    //-------------------------------------------------------------------------
    for( int unsigned p=0; p<3; p++ ) begin
      rand_slave();
      u_slv.aw_wait_w = (p!=1);
      u_slv.w_wait_aw = (p!=0);
      send_writes(N_REQ / 6, 0, N_WORDS, 0);
      wait_idle("PHASE3");
    end
    u_slv.aw_wait_w = 1'b0;
    u_slv.w_wait_aw = 1'b0;
    $display("[INFO] PHASE3 (AWREADY waits for W / WREADY waits for AW) done");

    //-------------------------------------------------------------------------
    // PHASE4 : 書いてから読み戻す (同じアドレス)。応答の遅延を長くして上限まで使う
    //-------------------------------------------------------------------------
    // (受け付けから B / R を受けるまで「遅延 + 2」サイクルかかるので、遅延を上限以上にすれば上限に達する)
    u_slv.set_ready(100, 100, 100);
    u_slv.set_lat(MAX_WR_OUTSTANDING, MAX_WR_OUTSTANDING + 4, MAX_RD_OUTSTANDING, MAX_RD_OUTSTANDING + 4);
    send_writes(N_REQ / 2, 0, N_WORDS, 0);
    wait_idle("PHASE4 write");
    send_reads(N_REQ / 2, 0, N_WORDS, 0);
    wait_idle("PHASE4 read");
    if( (max_wcnt!=MAX_WR_OUTSTANDING)||(max_rcnt!=MAX_RD_OUTSTANDING) ) begin
      tb_error($sformatf("PHASE4 : max outstanding requests %0d / %0d (exp %0d / %0d)", max_wcnt, max_rcnt, MAX_WR_OUTSTANDING, MAX_RD_OUTSTANDING));
    end
    $display("[INFO] PHASE4 (write then read back, long latency) done : max outstanding %0d / %0d", max_wcnt, max_rcnt);

    //-------------------------------------------------------------------------
    // PHASE5 : 要求が残っている途中でリセット
    //-------------------------------------------------------------------------
    // (応答の遅延を、要求を出し切る時間より長くして、上限まで未完了にしたままリセットする)
    u_slv.set_lat(40, 40, 40, 40);
    fork
      begin
        send_writes(MAX_WR_OUTSTANDING, 0, HALF, 0);
      end
      begin
        send_reads(MAX_RD_OUTSTANDING, HALF, N_WORDS - HALF, 0);
      end
    join
    if( (tb_wcnt!=MAX_WR_OUTSTANDING)||(tb_rcnt!=MAX_RD_OUTSTANDING) ) begin
      tb_error($sformatf("PHASE5 : %0d / %0d requests outstanding at reset (exp %0d / %0d)", tb_wcnt, tb_rcnt, MAX_WR_OUTSTANDING, MAX_RD_OUTSTANDING));
    end
    aresetn = 1'b0;
    repeat( 2 ) begin
      @(negedge aclk);
    end
    if( wr_busy||rd_busy||axi_wakeup||awvalid||wvalid||arvalid||wrsp_valid||rrsp_valid ) begin
      tb_error("PHASE5 : outputs are not idle during reset");
    end
    aresetn = 1'b1;
    // 途中で消えた要求は照合しない。スレーブのメモリは期待値に写し直す
    wq_addr.delete();
    wq_data.delete();
    wq_strb.delete();
    wq_prot.delete();
    rq_addr.delete();
    rq_prot.delete();
    u_slv.clear_log();
    n_wacc = n_wrsp;
    n_racc = n_rrsp;
    for( int unsigned i=0; i<N_WORDS; i++ ) begin
      exp_mem[64'(f_waddr(i))] = u_slv.peek_word(64'(f_waddr(i)));
    end
    repeat( 2 ) begin
      @(negedge aclk);
    end
    u_slv.set_lat(0, 3, 0, 3);
    fork
      begin
        send_writes(N_REQ / 6, 0, HALF, 10);
      end
      begin
        send_reads(N_REQ / 6, HALF, N_WORDS - HALF, 10);
      end
    join
    wait_idle("PHASE5");
    $display("[INFO] PHASE5 (reset with requests outstanding) done");

    //-------------------------------------------------------------------------
    // 集計
    //-------------------------------------------------------------------------
    repeat( 4 ) begin
      @(negedge aclk);
    end
    if( u_slv.n_viol!=0 ) begin
      tb_error($sformatf("slave model : %0d protocol violation(s)", u_slv.n_viol));
    end
    if( u_slv.n_unaligned!=0 ) begin
      tb_error($sformatf("slave model : %0d unaligned address(es)", u_slv.n_unaligned));
    end
    if( (wq_addr.size()!=0)||(rq_addr.size()!=0)||(u_slv.wlog_addr.size()!=0)||(u_slv.rlog_addr.size()!=0) ) begin
      tb_error($sformatf("requests without responses : %0d writes / %0d reads, bus transactions without responses : %0d / %0d", wq_addr.size(), rq_addr.size(), u_slv.wlog_addr.size(), u_slv.rlog_addr.size()));
    end
    $display("[INFO] responses: writes=%0d (errors %0d) reads=%0d (errors %0d), bus: writes=%0d reads=%0d, AW first=%0d W first=%0d, both outstanding=%0d cycles, max outstanding on the bus=%0d / %0d", n_wrsp, n_wrsp_err, n_rrsp, n_rrsp_err, u_slv.n_wr, u_slv.n_rd, u_slv.n_aw_first, u_slv.n_w_first, u_slv.n_both, u_slv.max_wr_out, u_slv.max_rd_out);
    if( err_cnt==0 ) begin
      $display("=== tb_axil_master_engine : TEST PASSED ===");
    end else begin
      $display("=== tb_axil_master_engine : TEST FAILED (%0d errors) ===", err_cnt);
    end
    $finish;
  end

endmodule
