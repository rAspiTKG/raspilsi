//=============================================================================
// tb_axi4_full_master_copy.sv
//-----------------------------------------------------------------------------
//  axi4_full_master_copy の簡易自己チェックテストベンチ。
//    DUT (AXI マスタ) <--> axi4_slave_mem_model (ランダムストール付きスレーブ)
//
//    TEST1 : 16 ビートコピー (1 バースト)
//    TEST2 : src / dst とも 4KB 境界を跨ぐ 100 ビート (分割位置が src と dst で違う)
//    TEST3 : スレーブ 50% ストール下で 300 ビート (MAX_BURST 分割の連続)
//    TEST4 : 1 ビート / 0 ビート
//    TEST5 : SLVERR 注入 (dst 側 / src 側) -> done_err=1
//    TEST6 : 連続コマンド、busy 中は cmd_ready=0
//    TEST7 : スレーブが VALID を見てから READY を立てるモード
//            (マスタが READY を待って VALID を出す実装ならデッドロックする)
//  全テストでスレーブモデルのプロトコル違反 0 件、バースト本数が分割規則どおり
//  であることも確認する。
//=============================================================================
`timescale 1ns / 1ps

module tb_axi4_full_master_copy;

  //---------------------------------------------------------------------------
  // Parameters
  //---------------------------------------------------------------------------
  localparam int unsigned ADDR_WIDTH = 32;
  localparam int unsigned DATA_WIDTH = 64;
  localparam int unsigned ID_WIDTH   = 4;
  localparam int unsigned LEN_WIDTH  = 16;
  localparam int unsigned MAX_BURST  = 16;
  localparam int unsigned BUF_DEPTH  = 32;
  localparam int unsigned STRB_W     = DATA_WIDTH / 8;

  //---------------------------------------------------------------------------
  // Clock / reset
  //---------------------------------------------------------------------------
  logic        aclk;
  logic        aresetn;
  int unsigned err_cnt;

  initial begin
    aclk = 1'b0;
    forever begin
      #5 aclk = ~aclk;
    end
  end

  initial begin
    aresetn = 1'b0;
    repeat( 5 ) begin
      @(posedge aclk);
    end
    aresetn = 1'b1;
  end

  //---------------------------------------------------------------------------
  // コマンド / ステータス
  //---------------------------------------------------------------------------
  logic                  cmd_valid;
  logic                  cmd_ready;
  logic [ADDR_WIDTH-1:0] cmd_src;
  logic [ADDR_WIDTH-1:0] cmd_dst;
  logic [LEN_WIDTH-1:0]  cmd_len;
  logic                  busy;
  logic                  done;
  logic                  done_err;

  //---------------------------------------------------------------------------
  // AXI
  //---------------------------------------------------------------------------
  logic [ID_WIDTH-1:0]   awid;
  logic [ADDR_WIDTH-1:0] awaddr;
  logic [7:0]            awlen;
  logic [2:0]            awsize;
  logic [1:0]            awburst;
  logic                  awlock;
  logic [3:0]            awcache;
  logic [2:0]            awprot;
  logic [3:0]            awqos;
  logic [3:0]            awregion;
  logic                  awvalid;
  logic                  awready;
  logic [DATA_WIDTH-1:0] wdata;
  logic [STRB_W-1:0]     wstrb;
  logic                  wlast;
  logic                  wvalid;
  logic                  wready;
  logic [ID_WIDTH-1:0]   bid;
  logic [1:0]            bresp;
  logic                  bvalid;
  logic                  bready;
  logic [ID_WIDTH-1:0]   arid;
  logic [ADDR_WIDTH-1:0] araddr;
  logic [7:0]            arlen;
  logic [2:0]            arsize;
  logic [1:0]            arburst;
  logic                  arlock;
  logic [3:0]            arcache;
  logic [2:0]            arprot;
  logic [3:0]            arqos;
  logic [3:0]            arregion;
  logic                  arvalid;
  logic                  arready;
  logic [ID_WIDTH-1:0]   rid;
  logic [DATA_WIDTH-1:0] rdata;
  logic [1:0]            rresp;
  logic                  rlast;
  logic                  rvalid;
  logic                  rready;

  //---------------------------------------------------------------------------
  // DUT
  //---------------------------------------------------------------------------
  axi4_full_master_copy #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.ID_WIDTH(ID_WIDTH)
   ,.LEN_WIDTH(LEN_WIDTH)
   ,.MAX_BURST(MAX_BURST)
   ,.BUF_DEPTH(BUF_DEPTH)
  ) u_dut (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.cmd_valid(cmd_valid)
   ,.cmd_ready(cmd_ready)
   ,.cmd_src(cmd_src)
   ,.cmd_dst(cmd_dst)
   ,.cmd_len(cmd_len)
   ,.busy(busy)
   ,.done(done)
   ,.done_err(done_err)
   ,.m_axi_awid(awid)
   ,.m_axi_awaddr(awaddr)
   ,.m_axi_awlen(awlen)
   ,.m_axi_awsize(awsize)
   ,.m_axi_awburst(awburst)
   ,.m_axi_awlock(awlock)
   ,.m_axi_awcache(awcache)
   ,.m_axi_awprot(awprot)
   ,.m_axi_awqos(awqos)
   ,.m_axi_awregion(awregion)
   ,.m_axi_awvalid(awvalid)
   ,.m_axi_awready(awready)
   ,.m_axi_wdata(wdata)
   ,.m_axi_wstrb(wstrb)
   ,.m_axi_wlast(wlast)
   ,.m_axi_wvalid(wvalid)
   ,.m_axi_wready(wready)
   ,.m_axi_bid(bid)
   ,.m_axi_bresp(bresp)
   ,.m_axi_bvalid(bvalid)
   ,.m_axi_bready(bready)
   ,.m_axi_arid(arid)
   ,.m_axi_araddr(araddr)
   ,.m_axi_arlen(arlen)
   ,.m_axi_arsize(arsize)
   ,.m_axi_arburst(arburst)
   ,.m_axi_arlock(arlock)
   ,.m_axi_arcache(arcache)
   ,.m_axi_arprot(arprot)
   ,.m_axi_arqos(arqos)
   ,.m_axi_arregion(arregion)
   ,.m_axi_arvalid(arvalid)
   ,.m_axi_arready(arready)
   ,.m_axi_rid(rid)
   ,.m_axi_rdata(rdata)
   ,.m_axi_rresp(rresp)
   ,.m_axi_rlast(rlast)
   ,.m_axi_rvalid(rvalid)
   ,.m_axi_rready(rready)
  );

  //---------------------------------------------------------------------------
  // AXI スレーブメモリモデル
  //---------------------------------------------------------------------------
  axi4_slave_mem_model #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.ID_WIDTH(ID_WIDTH)
   ,.MAX_BURST(MAX_BURST)
  ) u_mem (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.s_axi_awid(awid)
   ,.s_axi_awaddr(awaddr)
   ,.s_axi_awlen(awlen)
   ,.s_axi_awsize(awsize)
   ,.s_axi_awburst(awburst)
   ,.s_axi_awvalid(awvalid)
   ,.s_axi_awready(awready)
   ,.s_axi_wdata(wdata)
   ,.s_axi_wstrb(wstrb)
   ,.s_axi_wlast(wlast)
   ,.s_axi_wvalid(wvalid)
   ,.s_axi_wready(wready)
   ,.s_axi_bid(bid)
   ,.s_axi_bresp(bresp)
   ,.s_axi_bvalid(bvalid)
   ,.s_axi_bready(bready)
   ,.s_axi_arid(arid)
   ,.s_axi_araddr(araddr)
   ,.s_axi_arlen(arlen)
   ,.s_axi_arsize(arsize)
   ,.s_axi_arburst(arburst)
   ,.s_axi_arvalid(arvalid)
   ,.s_axi_arready(arready)
   ,.s_axi_rid(rid)
   ,.s_axi_rdata(rdata)
   ,.s_axi_rresp(rresp)
   ,.s_axi_rlast(rlast)
   ,.s_axi_rvalid(rvalid)
   ,.s_axi_rready(rready)
  );

  //---------------------------------------------------------------------------
  // コマンド握手 / 完了を posedge で観測
  //---------------------------------------------------------------------------
  logic        cmd_hs_q;
  int unsigned n_done;
  logic        last_err;
  logic        busy_ready_viol;

  always_ff @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      cmd_hs_q        <= 1'b0;
      n_done          <= 0;
      last_err        <= 1'b0;
      busy_ready_viol <= 1'b0;
    end else begin
      cmd_hs_q <= cmd_valid&&cmd_ready;
      if( done ) begin
        n_done   <= n_done + 1;
        last_err <= done_err;
      end
      if( busy&&cmd_ready ) begin
        busy_ready_viol <= 1'b1;
      end
    end
  end

  //---------------------------------------------------------------------------
  // Tasks
  //---------------------------------------------------------------------------
  task automatic send_cmd
  (
    input logic [ADDR_WIDTH-1:0] src
   ,input logic [ADDR_WIDTH-1:0] dst
   ,input int unsigned           len
  );
    begin
      @(negedge aclk);
      cmd_src   = src;
      cmd_dst   = dst;
      cmd_len   = LEN_WIDTH'(len);
      cmd_valid = 1'b1;
      @(negedge aclk);
      while( !cmd_hs_q ) begin
        @(negedge aclk);
      end
      cmd_valid = 1'b0;
    end
  endtask

  task automatic wait_done( input string tag, input int unsigned n_before );
    int unsigned guard;
    begin
      guard = 0;
      while( n_done==n_before ) begin
        @(negedge aclk);
        guard++;
        if( guard>200000 ) begin
          $display("[FAIL] %s : done timeout", tag);
          err_cnt++;
          return;
        end
      end
    end
  endtask

  // copy を 1 回実行して完了まで待つ。戻り値は done_err
  task automatic run_copy
  (
    input  string                 tag
   ,input  logic [ADDR_WIDTH-1:0] src
   ,input  logic [ADDR_WIDTH-1:0] dst
   ,input  int unsigned           len
   ,output logic                  err
  );
    int unsigned nd;
    begin
      nd = n_done;
      send_cmd(src, dst, len);
      wait_done(tag, nd);
      err = last_err;
    end
  endtask

  // src にランダムデータを len ビート書いておく
  task automatic fill_src( input logic [ADDR_WIDTH-1:0] src, input int unsigned len );
    for( int unsigned i=0; i<len; i++ ) begin
      u_mem.poke_word(src+ADDR_WIDTH'(i*STRB_W), {$urandom(), $urandom()});
    end
  endtask

  task automatic check_copy
  (
    input string                 tag
   ,input logic [ADDR_WIDTH-1:0] src
   ,input logic [ADDR_WIDTH-1:0] dst
   ,input int unsigned           len
  );
    logic [DATA_WIDTH-1:0] exp;
    logic [DATA_WIDTH-1:0] act;
    int unsigned           n_mis;
    n_mis = 0;
    for( int unsigned i=0; i<len; i++ ) begin
      exp = u_mem.peek_word(src+ADDR_WIDTH'(i*STRB_W));
      act = u_mem.peek_word(dst+ADDR_WIDTH'(i*STRB_W));
      if( exp!==act ) begin
        if( n_mis<4 ) begin
          $display("[FAIL] %s beat%0d dst=%08h exp=%016h act=%016h", tag, i, dst+ADDR_WIDTH'(i*STRB_W), exp, act);
        end
        n_mis++;
      end
    end
    if( n_mis!=0 ) begin
      $display("[FAIL] %s : %0d / %0d beats mismatch", tag, n_mis, len);
      err_cnt++;
    end
  endtask

  // 分割規則 min(残り, MAX_BURST, 4KB 境界まで) で期待されるバースト本数
  function automatic int unsigned exp_bursts( input logic [ADDR_WIDTH-1:0] addr, input int unsigned len );
    int unsigned           n;
    int unsigned           rem;
    int unsigned           b4k;
    int unsigned           bl;
    logic [ADDR_WIDTH-1:0] a;
    n   = 0;
    rem = len;
    a   = addr;
    while( rem>0 ) begin
      b4k = (4096 - 32'(a[11:0])) / STRB_W;
      bl  = MAX_BURST;
      if( rem<bl ) begin
        bl = rem;
      end
      if( b4k<bl ) begin
        bl = b4k;
      end
      a   = a + ADDR_WIDTH'(bl*STRB_W);
      rem = rem - bl;
      n++;
    end
    return n;
  endfunction

  task automatic check_bursts
  (
    input string                 tag
   ,input logic [ADDR_WIDTH-1:0] src
   ,input logic [ADDR_WIDTH-1:0] dst
   ,input int unsigned           len
   ,input int unsigned           ar0
   ,input int unsigned           aw0
  );
    int unsigned ar_exp;
    int unsigned aw_exp;
    ar_exp = exp_bursts(src, len);
    aw_exp = exp_bursts(dst, len);
    if( (u_mem.n_ar-ar0)!=ar_exp||(u_mem.n_aw-aw0)!=aw_exp ) begin
      $display("[FAIL] %s : bursts AR=%0d (exp %0d) AW=%0d (exp %0d)", tag, u_mem.n_ar-ar0, ar_exp, u_mem.n_aw-aw0, aw_exp);
      err_cnt++;
    end else begin
      $display("[INFO] %s : AR bursts=%0d AW bursts=%0d", tag, ar_exp, aw_exp);
    end
  endtask

  //---------------------------------------------------------------------------
  // Test sequence
  //---------------------------------------------------------------------------
  logic        err;
  int unsigned ar0;
  int unsigned aw0;

  initial begin
    err_cnt   = 0;
    cmd_valid = 1'b0;
    cmd_src   = '0;
    cmd_dst   = '0;
    cmd_len   = '0;
    wait( aresetn===1'b1 );
    repeat( 3 ) begin
      @(posedge aclk);
    end

    //-------------------------------------------------------------------------
    // TEST1 : 16 ビート (1 バースト)
    //-------------------------------------------------------------------------
    fill_src(32'h0000_1000, 16);
    ar0 = u_mem.n_ar;
    aw0 = u_mem.n_aw;
    run_copy("TEST1", 32'h0000_1000, 32'h0002_0000, 16, err);
    if( err ) begin
      $display("[FAIL] TEST1 done_err=1");
      err_cnt++;
    end
    check_copy("TEST1", 32'h0000_1000, 32'h0002_0000, 16);
    check_bursts("TEST1", 32'h0000_1000, 32'h0002_0000, 16, ar0, aw0);
    $display("[INFO] TEST1 (16 beats) done");

    //-------------------------------------------------------------------------
    // TEST2 : src / dst とも 4KB を跨ぐ 100 ビート
    //   src 0x2F80 : 4KB まで 16 ビート / dst 0x40FC8 : 4KB まで 7 ビート
    //-------------------------------------------------------------------------
    fill_src(32'h0000_2F80, 100);
    ar0 = u_mem.n_ar;
    aw0 = u_mem.n_aw;
    run_copy("TEST2", 32'h0000_2F80, 32'h0004_0FC8, 100, err);
    if( err ) begin
      $display("[FAIL] TEST2 done_err=1");
      err_cnt++;
    end
    check_copy("TEST2", 32'h0000_2F80, 32'h0004_0FC8, 100);
    check_bursts("TEST2", 32'h0000_2F80, 32'h0004_0FC8, 100, ar0, aw0);
    $display("[INFO] TEST2 (4KB crossing) done");

    //-------------------------------------------------------------------------
    // TEST3 : スレーブ 50% ストール、300 ビート
    //-------------------------------------------------------------------------
    u_mem.stall_pct = 50;
    fill_src(32'h0001_0000, 300);
    ar0 = u_mem.n_ar;
    aw0 = u_mem.n_aw;
    run_copy("TEST3", 32'h0001_0000, 32'h0005_0000, 300, err);
    if( err ) begin
      $display("[FAIL] TEST3 done_err=1");
      err_cnt++;
    end
    check_copy("TEST3", 32'h0001_0000, 32'h0005_0000, 300);
    check_bursts("TEST3", 32'h0001_0000, 32'h0005_0000, 300, ar0, aw0);
    $display("[INFO] TEST3 (300 beats, 50%% stall) done");

    //-------------------------------------------------------------------------
    // TEST4 : 1 ビート / 0 ビート
    //-------------------------------------------------------------------------
    fill_src(32'h0000_3000, 1);
    run_copy("TEST4a", 32'h0000_3000, 32'h0006_0008, 1, err);
    check_copy("TEST4a", 32'h0000_3000, 32'h0006_0008, 1);
    ar0 = u_mem.n_ar;
    aw0 = u_mem.n_aw;
    run_copy("TEST4b", 32'h0000_3000, 32'h0006_0100, 0, err);
    if( err||(u_mem.n_ar!=ar0)||(u_mem.n_aw!=aw0) ) begin
      $display("[FAIL] TEST4b len=0 must complete without any burst");
      err_cnt++;
    end
    $display("[INFO] TEST4 (1 beat / 0 beat) done");

    //-------------------------------------------------------------------------
    // TEST5 : SLVERR 注入
    //-------------------------------------------------------------------------
    u_mem.err_lo = 32'h0007_0040;
    u_mem.err_hi = 32'h0007_007F;
    fill_src(32'h0000_4000, 32);
    run_copy("TEST5a", 32'h0000_4000, 32'h0007_0000, 32, err);
    if( !err ) begin
      $display("[FAIL] TEST5a write SLVERR not reported");
      err_cnt++;
    end
    u_mem.err_lo = 32'h0000_4080;
    u_mem.err_hi = 32'h0000_4087;
    run_copy("TEST5b", 32'h0000_4000, 32'h0007_1000, 32, err);
    if( !err ) begin
      $display("[FAIL] TEST5b read SLVERR not reported");
      err_cnt++;
    end
    u_mem.err_lo = '1;
    u_mem.err_hi = '0;
    run_copy("TEST5c", 32'h0000_4000, 32'h0007_2000, 32, err);
    if( err ) begin
      $display("[FAIL] TEST5c done_err must clear on the next command");
      err_cnt++;
    end
    check_copy("TEST5c", 32'h0000_4000, 32'h0007_2000, 32);
    $display("[INFO] TEST5 (SLVERR -> done_err) done");

    //-------------------------------------------------------------------------
    // TEST6 : 連続コマンド
    //-------------------------------------------------------------------------
    fill_src(32'h0000_5000, 40);
    for( int unsigned k=0; k<4; k++ ) begin
      run_copy("TEST6", 32'h0000_5000+ADDR_WIDTH'(k*80), 32'h0008_0000+ADDR_WIDTH'(k*1024), 10, err);
      check_copy("TEST6", 32'h0000_5000+ADDR_WIDTH'(k*80), 32'h0008_0000+ADDR_WIDTH'(k*1024), 10);
    end
    if( busy_ready_viol ) begin
      $display("[FAIL] TEST6 cmd_ready asserted while busy");
      err_cnt++;
    end
    $display("[INFO] TEST6 (back-to-back commands) done");

    //-------------------------------------------------------------------------
    // TEST7 : READY は VALID を見てから (スレーブ側の正当な実装)
    //-------------------------------------------------------------------------
    u_mem.ready_wait_valid = 1'b1;
    fill_src(32'h0000_6000, 64);
    run_copy("TEST7", 32'h0000_6000, 32'h0009_0FF0, 64, err);
    if( err ) begin
      $display("[FAIL] TEST7 done_err=1");
      err_cnt++;
    end
    check_copy("TEST7", 32'h0000_6000, 32'h0009_0FF0, 64);
    u_mem.ready_wait_valid = 1'b0;
    $display("[INFO] TEST7 (READY waits for VALID) done");

    //-------------------------------------------------------------------------
    // 終了判定
    //-------------------------------------------------------------------------
    repeat( 10 ) begin
      @(posedge aclk);
    end
    if( u_mem.n_viol!=0 ) begin
      $display("[FAIL] slave model detected %0d protocol violations", u_mem.n_viol);
      err_cnt++;
    end
    $display("[INFO] AR bursts=%0d AW bursts=%0d R beats=%0d W beats=%0d max_arlen=%0d max_awlen=%0d"
            , u_mem.n_ar, u_mem.n_aw, u_mem.n_rbeat, u_mem.n_wbeat, u_mem.max_arlen, u_mem.max_awlen);
    if( err_cnt==0 ) begin
      $display("=== tb_axi4_full_master_copy : TEST PASSED ===");
    end else begin
      $display("=== tb_axi4_full_master_copy : TEST FAILED (%0d errors) ===", err_cnt);
    end
    $finish;
  end

  //---------------------------------------------------------------------------
  // Watchdog
  //---------------------------------------------------------------------------
  initial begin
    #5000000;
    $display("=== tb_axi4_full_master_copy : TIMEOUT ===");
    $finish;
  end

endmodule
