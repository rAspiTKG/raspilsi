//=============================================================================
// tb_axi4_full_master_stream.sv
//-----------------------------------------------------------------------------
//  axi4_full_master_stream の簡易自己チェックテストベンチ。
//    p2p_source_bfm --stream--> DUT --AXI--> axi4_slave_mem_model
//    p2p_sink_bfm   <--stream-- DUT <--AXI--
//  (p2p BFM を ready = !busy として valid/ready ストリームに使う)
//
//    TEST1 : Write 32 ビート -> 同じ場所を Read 32 ビート (データ / m_tlast)
//    TEST2 : 4KB 境界を跨ぐ 50 ビート
//    TEST3 : スレーブ 50% / 入力ギャップ 30% / 出力 busy 40% で 200 ビート
//    TEST4 : コマンドより先にデータを流しておく (FIFO に溜まる)
//    TEST5 : Write と Read を同時に実行 (別領域)
//    TEST6 : SLVERR 注入 -> wr_done_err / rd_done_err
//    TEST7 : スレーブが VALID を見てから READY を立てるモード
//=============================================================================
`timescale 1ns / 1ps

module tb_axi4_full_master_stream;

  //---------------------------------------------------------------------------
  // Parameters
  //---------------------------------------------------------------------------
  localparam int unsigned ADDR_WIDTH = 32;
  localparam int unsigned DATA_WIDTH = 64;
  localparam int unsigned ID_WIDTH   = 4;
  localparam int unsigned LEN_WIDTH  = 16;
  localparam int unsigned MAX_BURST  = 16;
  localparam int unsigned FIFO_DEPTH = 32;
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
  logic                  wr_cmd_valid;
  logic                  wr_cmd_ready;
  logic [ADDR_WIDTH-1:0] wr_cmd_addr;
  logic [LEN_WIDTH-1:0]  wr_cmd_len;
  logic                  wr_busy;
  logic                  wr_done;
  logic                  wr_done_err;
  logic                  rd_cmd_valid;
  logic                  rd_cmd_ready;
  logic [ADDR_WIDTH-1:0] rd_cmd_addr;
  logic [LEN_WIDTH-1:0]  rd_cmd_len;
  logic                  rd_busy;
  logic                  rd_done;
  logic                  rd_done_err;

  //---------------------------------------------------------------------------
  // ストリーム
  //---------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] s_tdata;
  logic                  s_tvalid;
  logic                  s_tready;
  logic [DATA_WIDTH-1:0] m_tdata;
  logic                  m_tlast;
  logic                  m_tvalid;
  logic                  m_tready;
  logic                  src_busy;
  logic                  snk_busy;

  assign src_busy = !s_tready;
  assign m_tready = !snk_busy;

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
  axi4_full_master_stream #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.ID_WIDTH(ID_WIDTH)
   ,.LEN_WIDTH(LEN_WIDTH)
   ,.MAX_BURST(MAX_BURST)
   ,.WR_FIFO_DEPTH(FIFO_DEPTH)
   ,.RD_FIFO_DEPTH(FIFO_DEPTH)
  ) u_dut (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.wr_cmd_valid(wr_cmd_valid)
   ,.wr_cmd_ready(wr_cmd_ready)
   ,.wr_cmd_addr(wr_cmd_addr)
   ,.wr_cmd_len(wr_cmd_len)
   ,.wr_busy(wr_busy)
   ,.wr_done(wr_done)
   ,.wr_done_err(wr_done_err)
   ,.rd_cmd_valid(rd_cmd_valid)
   ,.rd_cmd_ready(rd_cmd_ready)
   ,.rd_cmd_addr(rd_cmd_addr)
   ,.rd_cmd_len(rd_cmd_len)
   ,.rd_busy(rd_busy)
   ,.rd_done(rd_done)
   ,.rd_done_err(rd_done_err)
   ,.s_tdata(s_tdata)
   ,.s_tvalid(s_tvalid)
   ,.s_tready(s_tready)
   ,.m_tdata(m_tdata)
   ,.m_tlast(m_tlast)
   ,.m_tvalid(m_tvalid)
   ,.m_tready(m_tready)
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
  // ストリーム送信 / 受信モデル
  //---------------------------------------------------------------------------
  p2p_source_bfm #(
    .WIDTH(DATA_WIDTH)
  ) u_src (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.p2p_dat(s_tdata)
   ,.p2p_vld(s_tvalid)
   ,.p2p_busy(src_busy)
  );

  p2p_sink_bfm #(
    .WIDTH(DATA_WIDTH+1)
  ) u_snk (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.p2p_dat({m_tlast, m_tdata})
   ,.p2p_vld(m_tvalid)
   ,.p2p_busy(snk_busy)
  );

  //---------------------------------------------------------------------------
  // コマンド握手 / 完了を posedge で観測
  //---------------------------------------------------------------------------
  logic        wr_hs_q;
  logic        rd_hs_q;
  int unsigned n_wr_done;
  int unsigned n_rd_done;
  logic        last_wr_err;
  logic        last_rd_err;

  always_ff @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      wr_hs_q     <= 1'b0;
      rd_hs_q     <= 1'b0;
      n_wr_done   <= 0;
      n_rd_done   <= 0;
      last_wr_err <= 1'b0;
      last_rd_err <= 1'b0;
    end else begin
      wr_hs_q <= wr_cmd_valid&&wr_cmd_ready;
      rd_hs_q <= rd_cmd_valid&&rd_cmd_ready;
      if( wr_done ) begin
        n_wr_done   <= n_wr_done + 1;
        last_wr_err <= wr_done_err;
      end
      if( rd_done ) begin
        n_rd_done   <= n_rd_done + 1;
        last_rd_err <= rd_done_err;
      end
    end
  end

  //---------------------------------------------------------------------------
  // Tasks
  //---------------------------------------------------------------------------
  task automatic send_wr_cmd( input logic [ADDR_WIDTH-1:0] addr, input int unsigned len );
    begin
      @(negedge aclk);
      wr_cmd_addr  = addr;
      wr_cmd_len   = LEN_WIDTH'(len);
      wr_cmd_valid = 1'b1;
      @(negedge aclk);
      while( !wr_hs_q ) begin
        @(negedge aclk);
      end
      wr_cmd_valid = 1'b0;
    end
  endtask

  task automatic send_rd_cmd( input logic [ADDR_WIDTH-1:0] addr, input int unsigned len );
    begin
      @(negedge aclk);
      rd_cmd_addr  = addr;
      rd_cmd_len   = LEN_WIDTH'(len);
      rd_cmd_valid = 1'b1;
      @(negedge aclk);
      while( !rd_hs_q ) begin
        @(negedge aclk);
      end
      rd_cmd_valid = 1'b0;
    end
  endtask

  task automatic wait_cnt( input string tag, const ref int unsigned cnt, input int unsigned target );
    int unsigned guard;
    begin
      guard = 0;
      while( cnt<target ) begin
        @(negedge aclk);
        guard++;
        if( guard>200000 ) begin
          $display("[FAIL] %s : timeout waiting for done", tag);
          err_cnt++;
          return;
        end
      end
    end
  endtask

  // 送信データを用意
  task automatic make_tx( input int unsigned len );
    for( int unsigned i=0; i<len; i++ ) begin
      u_src.tx_buf[i] = {$urandom(), $urandom()};
    end
  endtask

  // メモリ内容 == 送信データ
  task automatic check_mem( input string tag, input logic [ADDR_WIDTH-1:0] addr, input int unsigned len );
    int unsigned n_mis;
    n_mis = 0;
    for( int unsigned i=0; i<len; i++ ) begin
      if( u_mem.peek_word(addr+ADDR_WIDTH'(i*STRB_W))!==u_src.tx_buf[i] ) begin
        n_mis++;
      end
    end
    if( n_mis!=0 ) begin
      $display("[FAIL] %s : memory %0d / %0d beats mismatch", tag, n_mis, len);
      err_cnt++;
    end
  endtask

  // 受信ストリーム == メモリ内容、m_tlast は最終ビートのみ
  task automatic check_rx( input string tag, input logic [ADDR_WIDTH-1:0] addr, input int unsigned len );
    int unsigned n_mis;
    n_mis = 0;
    if( u_snk.rx_cnt!=len ) begin
      $display("[FAIL] %s : stream beats %0d (exp %0d)", tag, u_snk.rx_cnt, len);
      err_cnt++;
      return;
    end
    for( int unsigned i=0; i<len; i++ ) begin
      if( u_snk.rx_buf[i][DATA_WIDTH-1:0]!==u_mem.peek_word(addr+ADDR_WIDTH'(i*STRB_W)) ) begin
        n_mis++;
      end
      if( u_snk.rx_buf[i][DATA_WIDTH]!==(i==(len-1)) ) begin
        $display("[FAIL] %s : m_tlast=%b at beat %0d", tag, u_snk.rx_buf[i][DATA_WIDTH], i);
        err_cnt++;
      end
    end
    if( n_mis!=0 ) begin
      $display("[FAIL] %s : stream %0d / %0d beats mismatch", tag, n_mis, len);
      err_cnt++;
    end
  endtask

  // ストリーム -> メモリ (コマンド -> データ送出 -> 完了待ち)
  task automatic do_write( input string tag, input logic [ADDR_WIDTH-1:0] addr, input int unsigned len );
    int unsigned nd;
    begin
      nd = n_wr_done;
      make_tx(len);
      send_wr_cmd(addr, len);
      u_src.send(len);
      wait_cnt(tag, n_wr_done, nd+1);
      if( last_wr_err ) begin
        $display("[FAIL] %s : wr_done_err=1", tag);
        err_cnt++;
      end
      check_mem(tag, addr, len);
    end
  endtask

  // メモリ -> ストリーム
  task automatic do_read( input string tag, input logic [ADDR_WIDTH-1:0] addr, input int unsigned len );
    int unsigned nd;
    int unsigned guard;
    begin
      nd = n_rd_done;
      u_snk.clear();
      send_rd_cmd(addr, len);
      wait_cnt(tag, n_rd_done, nd+1);
      // rd_done 後も RD FIFO にデータが残るので、全ビート受け取るまで待つ
      guard = 0;
      while( (u_snk.rx_cnt<len)&&(guard<100000) ) begin
        @(negedge aclk);
        guard++;
      end
      if( last_rd_err ) begin
        $display("[FAIL] %s : rd_done_err=1", tag);
        err_cnt++;
      end
      check_rx(tag, addr, len);
    end
  endtask

  //---------------------------------------------------------------------------
  // Test sequence
  //---------------------------------------------------------------------------
  int unsigned nw;
  int unsigned nr;

  initial begin
    err_cnt      = 0;
    wr_cmd_valid = 1'b0;
    wr_cmd_addr  = '0;
    wr_cmd_len   = '0;
    rd_cmd_valid = 1'b0;
    rd_cmd_addr  = '0;
    rd_cmd_len   = '0;
    wait( aresetn===1'b1 );
    repeat( 3 ) begin
      @(posedge aclk);
    end

    //-------------------------------------------------------------------------
    // TEST1 : Write 32 -> Read 32
    //-------------------------------------------------------------------------
    do_write("TEST1 wr", 32'h0000_1000, 32);
    do_read("TEST1 rd", 32'h0000_1000, 32);
    $display("[INFO] TEST1 (stream -> AXI -> stream, 32 beats) done");

    //-------------------------------------------------------------------------
    // TEST2 : 4KB 境界を跨ぐ 50 ビート (0x2FC0 から 4KB まで 8 ビート)
    //-------------------------------------------------------------------------
    do_write("TEST2 wr", 32'h0000_2FC0, 50);
    do_read("TEST2 rd", 32'h0000_2FC0, 50);
    $display("[INFO] TEST2 (4KB crossing) done");

    //-------------------------------------------------------------------------
    // TEST3 : ストール / ギャップ / バックプレッシャ
    //-------------------------------------------------------------------------
    u_mem.stall_pct = 50;
    u_src.gap_pct   = 30;
    u_snk.busy_pct  = 40;
    do_write("TEST3 wr", 32'h0001_0000, 200);
    do_read("TEST3 rd", 32'h0001_0000, 200);
    u_src.gap_pct   = 0;
    u_snk.busy_pct  = 0;
    $display("[INFO] TEST3 (stall 50%% / gap 30%% / busy 40%%, 200 beats) done");

    //-------------------------------------------------------------------------
    // TEST4 : コマンドより先にデータを流す (WR FIFO に溜まる)
    //-------------------------------------------------------------------------
    make_tx(20);
    u_src.send(20);
    nw = n_wr_done;
    send_wr_cmd(32'h0002_0000, 20);
    wait_cnt("TEST4", n_wr_done, nw+1);
    check_mem("TEST4", 32'h0002_0000, 20);
    $display("[INFO] TEST4 (data before command) done");

    //-------------------------------------------------------------------------
    // TEST5 : Write (page B) と Read (page A) を同時実行
    //-------------------------------------------------------------------------
    nw = n_wr_done;
    nr = n_rd_done;
    make_tx(64);
    u_snk.clear();
    send_wr_cmd(32'h0003_0000, 64);
    send_rd_cmd(32'h0001_0000, 64);
    u_src.send(64);
    wait_cnt("TEST5 wr", n_wr_done, nw+1);
    wait_cnt("TEST5 rd", n_rd_done, nr+1);
    repeat( 50 ) begin
      @(negedge aclk);
    end
    check_mem("TEST5 wr", 32'h0003_0000, 64);
    check_rx("TEST5 rd", 32'h0001_0000, 64);
    $display("[INFO] TEST5 (concurrent write / read) done");

    //-------------------------------------------------------------------------
    // TEST6 : SLVERR 注入
    //-------------------------------------------------------------------------
    u_mem.err_lo = 32'h0004_0080;
    u_mem.err_hi = 32'h0004_00FF;
    nw = n_wr_done;
    make_tx(32);
    send_wr_cmd(32'h0004_0000, 32);
    u_src.send(32);
    wait_cnt("TEST6 wr", n_wr_done, nw+1);
    if( !last_wr_err ) begin
      $display("[FAIL] TEST6 write SLVERR not reported");
      err_cnt++;
    end
    nr = n_rd_done;
    u_snk.clear();
    send_rd_cmd(32'h0004_0000, 32);
    wait_cnt("TEST6 rd", n_rd_done, nr+1);
    if( !last_rd_err ) begin
      $display("[FAIL] TEST6 read SLVERR not reported");
      err_cnt++;
    end
    u_mem.err_lo = '1;
    u_mem.err_hi = '0;
    repeat( 50 ) begin
      @(negedge aclk);
    end
    $display("[INFO] TEST6 (SLVERR -> wr/rd_done_err) done");

    //-------------------------------------------------------------------------
    // TEST7 : READY は VALID を見てから (スレーブ側の正当な実装)
    //-------------------------------------------------------------------------
    u_mem.ready_wait_valid = 1'b1;
    do_write("TEST7 wr", 32'h0005_0FC0, 64);
    do_read("TEST7 rd", 32'h0005_0FC0, 64);
    u_mem.ready_wait_valid = 1'b0;
    $display("[INFO] TEST7 (READY waits for VALID) done");

    //-------------------------------------------------------------------------
    // 終了判定
    //-------------------------------------------------------------------------
    if( u_mem.n_viol!=0 ) begin
      $display("[FAIL] slave model detected %0d protocol violations", u_mem.n_viol);
      err_cnt++;
    end
    $display("[INFO] AR bursts=%0d AW bursts=%0d R beats=%0d W beats=%0d max_arlen=%0d max_awlen=%0d"
            , u_mem.n_ar, u_mem.n_aw, u_mem.n_rbeat, u_mem.n_wbeat, u_mem.max_arlen, u_mem.max_awlen);
    if( err_cnt==0 ) begin
      $display("=== tb_axi4_full_master_stream : TEST PASSED ===");
    end else begin
      $display("=== tb_axi4_full_master_stream : TEST FAILED (%0d errors) ===", err_cnt);
    end
    $finish;
  end

  //---------------------------------------------------------------------------
  // Watchdog
  //---------------------------------------------------------------------------
  initial begin
    #5000000;
    $display("=== tb_axi4_full_master_stream : TIMEOUT ===");
    $finish;
  end

endmodule
