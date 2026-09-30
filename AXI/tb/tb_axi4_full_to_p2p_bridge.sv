//=============================================================================
// tb_axi4_full_to_p2p_bridge.sv
//-----------------------------------------------------------------------------
//  axi4_full_to_p2p_bridge の簡易自己チェックテストベンチ。
//
//    axi4_full_master_bfm --AXI4-Full--> bridge --p2p out--> p2p_sink_bfm
//    p2p_source_bfm --p2p in--> bridge --AXI4-Full--> axi4_full_master_bfm
//
//    TEST1 : Write 8 ビート -> p2p 出力 (データ / strb / last / BRESP)
//    TEST2 : p2p 出力にランダム busy を掛けた 16 ビート Write
//    TEST3 : p2p 出力を固定 busy にして FIFO 深さを超える 24 ビート Write
//            (WREADY が下がること / busy 解除後に全ビート到達すること)
//    TEST4 : p2p 入力を先行投入してから Read バースト 8 ビート
//    TEST5 : Read バースト先行 (アンダーラン) + p2p 入力にランダムギャップ
//=============================================================================
`timescale 1ns / 1ps

module tb_axi4_full_to_p2p_bridge #(
  // -GTB_B_WAIT_DRAIN=1 / -GTB_RD_TIMEOUT=200 のように切り替えられる
  parameter bit          TB_B_WAIT_DRAIN = 1'b0
 ,parameter int unsigned TB_RD_TIMEOUT   = 0
) ();

  //---------------------------------------------------------------------------
  // Parameters
  //---------------------------------------------------------------------------
  localparam int unsigned ADDR_WIDTH    = 32;
  localparam int unsigned DATA_WIDTH    = 64;
  localparam int unsigned ID_WIDTH      = 4;
  localparam int unsigned STRB_WIDTH    = DATA_WIDTH / 8;
  localparam int unsigned WR_FIFO_DEPTH = 16;
  localparam int unsigned RD_FIFO_DEPTH = 16;
  localparam int unsigned SINK_W        = 1 + STRB_WIDTH + DATA_WIDTH;

  localparam logic [2:0] SIZE_8B    = 3'd3;
  localparam logic [1:0] BURST_INCR = 2'b01;
  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;

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
  // AXI interconnect
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
  logic [STRB_WIDTH-1:0] wstrb;
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
  // p2p interconnect
  //---------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] p2p_out_dat;
  logic [STRB_WIDTH-1:0] p2p_out_strb;
  logic                  p2p_out_last;
  logic                  p2p_out_vld;
  logic                  p2p_out_busy;
  logic [DATA_WIDTH-1:0] p2p_in_dat;
  logic                  p2p_in_vld;
  logic                  p2p_in_busy;

  logic [$clog2(WR_FIFO_DEPTH+1)-1:0] wr_fifo_level;
  logic [$clog2(RD_FIFO_DEPTH+1)-1:0] rd_fifo_level;

  //---------------------------------------------------------------------------
  // AXI master BFM
  //---------------------------------------------------------------------------
  axi4_full_master_bfm #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.ID_WIDTH(ID_WIDTH)
  ) u_bfm (
    .aclk(aclk)
   ,.aresetn(aresetn)
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
  // DUT
  //---------------------------------------------------------------------------
  axi4_full_to_p2p_bridge #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.ID_WIDTH(ID_WIDTH)
   ,.WR_FIFO_DEPTH(WR_FIFO_DEPTH)
   ,.RD_FIFO_DEPTH(RD_FIFO_DEPTH)
   ,.B_WAIT_DRAIN(TB_B_WAIT_DRAIN)
   ,.RD_TIMEOUT(TB_RD_TIMEOUT)
  ) u_dut (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.s_axi_awid(awid)
   ,.s_axi_awaddr(awaddr)
   ,.s_axi_awlen(awlen)
   ,.s_axi_awsize(awsize)
   ,.s_axi_awburst(awburst)
   ,.s_axi_awlock(awlock)
   ,.s_axi_awcache(awcache)
   ,.s_axi_awprot(awprot)
   ,.s_axi_awqos(awqos)
   ,.s_axi_awregion(awregion)
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
   ,.s_axi_arlock(arlock)
   ,.s_axi_arcache(arcache)
   ,.s_axi_arprot(arprot)
   ,.s_axi_arqos(arqos)
   ,.s_axi_arregion(arregion)
   ,.s_axi_arvalid(arvalid)
   ,.s_axi_arready(arready)
   ,.s_axi_rid(rid)
   ,.s_axi_rdata(rdata)
   ,.s_axi_rresp(rresp)
   ,.s_axi_rlast(rlast)
   ,.s_axi_rvalid(rvalid)
   ,.s_axi_rready(rready)
   ,.p2p_out_dat(p2p_out_dat)
   ,.p2p_out_strb(p2p_out_strb)
   ,.p2p_out_last(p2p_out_last)
   ,.p2p_out_vld(p2p_out_vld)
   ,.p2p_out_busy(p2p_out_busy)
   ,.p2p_in_dat(p2p_in_dat)
   ,.p2p_in_vld(p2p_in_vld)
   ,.p2p_in_busy(p2p_in_busy)
   ,.wr_fifo_level(wr_fifo_level)
   ,.rd_fifo_level(rd_fifo_level)
  );

  //---------------------------------------------------------------------------
  // p2p 受信側モデル (bridge の p2p 出力を受ける)
  //---------------------------------------------------------------------------
  p2p_sink_bfm #(
    .WIDTH(SINK_W)
  ) u_sink (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.p2p_dat({p2p_out_last, p2p_out_strb, p2p_out_dat})
   ,.p2p_vld(p2p_out_vld)
   ,.p2p_busy(p2p_out_busy)
  );

  //---------------------------------------------------------------------------
  // p2p 送信側モデル (bridge の p2p 入力へ流す)
  //---------------------------------------------------------------------------
  p2p_source_bfm #(
    .WIDTH(DATA_WIDTH)
  ) u_src (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.p2p_dat(p2p_in_dat)
   ,.p2p_vld(p2p_in_vld)
   ,.p2p_busy(p2p_in_busy)
  );

  //---------------------------------------------------------------------------
  // WREADY が下がったことを記録するモニタ
  //---------------------------------------------------------------------------
  logic wstall_seen;
  logic wstall_clr;

  // fork 内で使うカウンタ (プロセス寿命の問題を避けるためモジュールスコープの static)
  int unsigned fork_cnt_a;
  int unsigned fork_cnt_b;

  always_ff @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      wstall_seen <= 1'b0;
    end else begin
      if( wstall_clr ) begin
        wstall_seen <= 1'b0;
      end else if( wvalid&&!wready ) begin
        wstall_seen <= 1'b1;
      end
    end
  end

  //---------------------------------------------------------------------------
  // Checkers
  //---------------------------------------------------------------------------
  task automatic chk_eq64
  (
    input string                 tag
   ,input logic [DATA_WIDTH-1:0] exp
   ,input logic [DATA_WIDTH-1:0] act
  );
    begin
      if( exp!==act ) begin
        $display("[FAIL] %s exp=%016h act=%016h", tag, exp, act);
        err_cnt = err_cnt + 1;
      end
    end
  endtask

  // p2p 出力に n ビート届くまで待つ
  task automatic wait_rx( input string tag, input int unsigned n );
    int unsigned guard;
    begin
      guard = 0;
      @(negedge aclk);
      while( u_sink.rx_cnt<n ) begin
        @(negedge aclk);
        guard = guard + 1;
        if( guard>5000 ) begin
          $display("[FAIL] %s p2p out timeout (rx_cnt=%0d exp=%0d)", tag, u_sink.rx_cnt, n);
          err_cnt = err_cnt + 1;
          return;
        end
      end
    end
  endtask

  // p2p 出力に届いた n ビートを wr_buf と突き合わせる
  task automatic chk_p2p_out( input string tag, input int unsigned n );
    logic [DATA_WIDTH-1:0] dat;
    logic [STRB_WIDTH-1:0] strb;
    logic                  last;
    begin
      if( u_sink.rx_cnt!=n ) begin
        $display("[FAIL] %s p2p out beat count exp=%0d act=%0d", tag, n, u_sink.rx_cnt);
        err_cnt = err_cnt + 1;
        return;
      end
      for( int unsigned i=0; i<n; i++ ) begin
        dat  = u_sink.rx_buf[i][DATA_WIDTH-1:0];
        strb = u_sink.rx_buf[i][DATA_WIDTH+:STRB_WIDTH];
        last = u_sink.rx_buf[i][DATA_WIDTH+STRB_WIDTH];
        chk_eq64($sformatf("%s dat beat%0d", tag, i), u_bfm.wr_buf[i], dat);
        if( strb!=={STRB_WIDTH{1'b1}} ) begin
          $display("[FAIL] %s strb beat%0d = %02h", tag, i, strb);
          err_cnt = err_cnt + 1;
        end
        if( last!==(i==(n-1)) ) begin
          $display("[FAIL] %s last beat%0d = %b", tag, i, last);
          err_cnt = err_cnt + 1;
        end
      end
    end
  endtask

  task automatic chk_bresp( input string tag, input logic [ID_WIDTH-1:0] id );
    begin
      if( u_bfm.last_bresp!==RESP_OKAY ) begin
        $display("[FAIL] %s BRESP=%b", tag, u_bfm.last_bresp);
        err_cnt = err_cnt + 1;
      end
      if( u_bfm.last_bid!==id ) begin
        $display("[FAIL] %s BID exp=%0d act=%0d", tag, id, u_bfm.last_bid);
        err_cnt = err_cnt + 1;
      end
    end
  endtask

  // B_WAIT_DRAIN=1 なら B 応答時点で送信 FIFO は空のはず
  task automatic chk_drained( input string tag );
    begin
      if( TB_B_WAIT_DRAIN&&(wr_fifo_level!=0) ) begin
        $display("[FAIL] %s B returned with wr_fifo_level=%0d (B_WAIT_DRAIN=1)", tag, wr_fifo_level);
        err_cnt = err_cnt + 1;
      end
    end
  endtask

  task automatic chk_rresp( input string tag, input logic [ID_WIDTH-1:0] id );
    begin
      if( u_bfm.last_rresp!==RESP_OKAY ) begin
        $display("[FAIL] %s RRESP=%b", tag, u_bfm.last_rresp);
        err_cnt = err_cnt + 1;
      end
      if( u_bfm.last_rid!==id ) begin
        $display("[FAIL] %s RID exp=%0d act=%0d", tag, id, u_bfm.last_rid);
        err_cnt = err_cnt + 1;
      end
      if( !u_bfm.last_rlast_ok ) begin
        $display("[FAIL] %s RLAST position mismatch", tag);
        err_cnt = err_cnt + 1;
      end
    end
  endtask

  //---------------------------------------------------------------------------
  // Test sequence
  //---------------------------------------------------------------------------
  initial begin
    err_cnt    = 0;
    wstall_clr = 1'b0;
    fork_cnt_a = 0;
    fork_cnt_b = 0;
    wait( aresetn===1'b1 );
    u_bfm.wait_clk(2);

    //-------------------------------------------------------------------------
    // TEST1 : Write 8 ビート -> p2p 出力
    //-------------------------------------------------------------------------
    for( int unsigned i=0; i<8; i++ ) begin
      u_bfm.wr_buf[i] = {32'h0A0A_0000 + i, 32'h1111_0000 + i};
    end
    u_sink.clear();
    u_bfm.write_burst(32'h0000_0000, 8'd7, SIZE_8B, BURST_INCR, 4'h3);
    chk_drained("TEST1");
    chk_bresp("TEST1", 4'h3);
    wait_rx("TEST1", 8);
    chk_p2p_out("TEST1", 8);
    $display("[INFO] TEST1 (write 8 beats -> p2p out) done");

    //-------------------------------------------------------------------------
    // TEST2 : p2p 出力にランダム busy
    //-------------------------------------------------------------------------
    u_sink.busy_pct = 50;
    for( int unsigned i=0; i<16; i++ ) begin
      u_bfm.wr_buf[i] = {32'h2222_0000 + i, 32'h3333_0000 + i};
    end
    u_sink.clear();
    u_bfm.write_burst(32'h0000_0000, 8'd15, SIZE_8B, BURST_INCR, 4'h5);
    chk_drained("TEST2");
    chk_bresp("TEST2", 4'h5);
    wait_rx("TEST2", 16);
    chk_p2p_out("TEST2", 16);
    u_sink.busy_pct = 0;
    $display("[INFO] TEST2 (random busy backpressure) done");

    //-------------------------------------------------------------------------
    // TEST3 : 固定 busy で FIFO 深さ (16) を超える 24 ビート Write
    //-------------------------------------------------------------------------
    for( int unsigned i=0; i<24; i++ ) begin
      u_bfm.wr_buf[i] = {32'h4444_0000 + i, 32'h5555_0000 + i};
    end
    u_sink.clear();
    u_sink.force_busy = 1'b1;
    @(negedge aclk);
    wstall_clr = 1'b1;
    @(negedge aclk);
    wstall_clr = 1'b0;
    fork
      begin
        fork_cnt_a = 0;
        while( fork_cnt_a<60 ) begin
          @(negedge aclk);
          fork_cnt_a = fork_cnt_a + 1;
        end
        u_sink.force_busy = 1'b0;
      end
    join_none
    u_bfm.write_burst(32'h0000_0000, 8'd23, SIZE_8B, BURST_INCR, 4'h7);
    chk_drained("TEST3");
    chk_bresp("TEST3", 4'h7);
    if( !wstall_seen ) begin
      $display("[FAIL] TEST3 WREADY did not deassert despite full FIFO");
      err_cnt = err_cnt + 1;
    end
    wait_rx("TEST3", 24);
    chk_p2p_out("TEST3", 24);
    $display("[INFO] TEST3 (FIFO full -> WREADY stall) done");

    //-------------------------------------------------------------------------
    // TEST4 : p2p 入力を先行投入してから Read バースト 8 ビート
    //-------------------------------------------------------------------------
    for( int unsigned i=0; i<8; i++ ) begin
      u_src.tx_buf[i] = {32'h6666_0000 + i, 32'h7777_0000 + i};
    end
    u_src.send(8);
    u_bfm.read_burst(32'h0000_0000, 8'd7, SIZE_8B, BURST_INCR, 4'h9);
    chk_rresp("TEST4", 4'h9);
    for( int unsigned i=0; i<8; i++ ) begin
      chk_eq64($sformatf("TEST4 rdata beat%0d", i), u_src.tx_buf[i], u_bfm.rd_buf[i]);
    end
    $display("[INFO] TEST4 (p2p in -> read burst) done");

    //-------------------------------------------------------------------------
    // TEST5 : Read 先行 (アンダーラン) + p2p 入力にランダムギャップ
    //-------------------------------------------------------------------------
    for( int unsigned i=0; i<8; i++ ) begin
      u_src.tx_buf[i] = {32'h8888_0000 + i, 32'h9999_0000 + i};
    end
    u_src.gap_pct = 40;
    fork
      begin
        fork_cnt_b = 0;
        while( fork_cnt_b<40 ) begin
          @(negedge aclk);
          fork_cnt_b = fork_cnt_b + 1;
        end
        u_src.send(8);
      end
    join_none
    u_bfm.read_burst(32'h0000_0000, 8'd7, SIZE_8B, BURST_INCR, 4'hB);
    chk_rresp("TEST5", 4'hB);
    for( int unsigned i=0; i<8; i++ ) begin
      chk_eq64($sformatf("TEST5 rdata beat%0d", i), u_src.tx_buf[i], u_bfm.rd_buf[i]);
    end
    u_src.gap_pct = 0;
    $display("[INFO] TEST5 (read under-run + source gap) done");

    //-------------------------------------------------------------------------
    // TEST6 : Read タイムアウト (TB_RD_TIMEOUT>0 のときのみ)
    //   p2p 入力が来ないまま Read バーストを発行し、残りビートが SLVERR で
    //   返り切ること (AXI バスがハングしないこと) を確認する
    //-------------------------------------------------------------------------
    if( TB_RD_TIMEOUT!=0 ) begin
      u_bfm.read_burst(32'h0000_0000, 8'd3, SIZE_8B, BURST_INCR, 4'hD);
      if( u_bfm.last_rresp!==RESP_SLVERR ) begin
        $display("[FAIL] TEST6 RRESP exp=%b act=%b", RESP_SLVERR, u_bfm.last_rresp);
        err_cnt = err_cnt + 1;
      end
      if( !u_bfm.last_rlast_ok ) begin
        $display("[FAIL] TEST6 RLAST position mismatch");
        err_cnt = err_cnt + 1;
      end
      $display("[INFO] TEST6 (read timeout -> SLVERR) done");
    end

    u_bfm.wait_clk(10);
    $display("[INFO] config : B_WAIT_DRAIN=%0d RD_TIMEOUT=%0d", TB_B_WAIT_DRAIN, TB_RD_TIMEOUT);
    if( err_cnt==0 ) begin
      $display("=== tb_axi4_full_to_p2p_bridge : TEST PASSED ===");
    end else begin
      $display("=== tb_axi4_full_to_p2p_bridge : TEST FAILED (%0d errors) ===", err_cnt);
    end
    $finish;
  end

  //---------------------------------------------------------------------------
  // Watchdog
  //---------------------------------------------------------------------------
  initial begin
    #500000;
    $display("=== tb_axi4_full_to_p2p_bridge : TIMEOUT ===");
    $finish;
  end

endmodule
