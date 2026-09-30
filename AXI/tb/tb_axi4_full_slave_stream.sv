//=============================================================================
// tb_axi4_full_slave_stream.sv
//-----------------------------------------------------------------------------
//  axi4_full_slave_stream の簡易自己チェックテストベンチ。
//    TEST1 : INCR バースト 8 ビート -- ストリーム出力のデータ/アドレス/TLAST
//    TEST2 : ストリーム側のランダムバックプレッシャ下でも取りこぼさないこと
//    TEST3 : WRAP バースト時の m_taddr 折り返し
//    TEST4 : Read チャネルのダミー応答 (RDATA / RRESP / RLAST)
//=============================================================================
`timescale 1ns / 1ps

module tb_axi4_full_slave_stream;

  //---------------------------------------------------------------------------
  // Parameters
  //---------------------------------------------------------------------------
  localparam int unsigned ADDR_WIDTH    = 32;
  localparam int unsigned DATA_WIDTH    = 64;
  localparam int unsigned ID_WIDTH      = 4;
  localparam int unsigned STRB_WIDTH    = DATA_WIDTH / 8;
  localparam logic [63:0] RD_DUMMY_DATA = 64'hDEAD_BEEF_DEAD_BEEF;

  localparam logic [2:0] SIZE_8B    = 3'd3;
  localparam logic [1:0] BURST_INCR = 2'b01;
  localparam logic [1:0] BURST_WRAP = 2'b10;
  localparam logic [1:0] RESP_OKAY  = 2'b00;

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
  // Interconnect
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

  logic [DATA_WIDTH-1:0] tdata;
  logic [STRB_WIDTH-1:0] tstrb;
  logic                  tlast;
  logic [ID_WIDTH-1:0]   tid;
  logic [ADDR_WIDTH-1:0] taddr;
  logic                  tvalid;
  logic                  tready;

  //---------------------------------------------------------------------------
  // Master BFM
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
  axi4_full_slave_stream #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.ID_WIDTH(ID_WIDTH)
   ,.RD_DUMMY_DATA(RD_DUMMY_DATA)
   ,.RD_RESP(RESP_OKAY)
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
   ,.m_tdata(tdata)
   ,.m_tstrb(tstrb)
   ,.m_tlast(tlast)
   ,.m_tid(tid)
   ,.m_taddr(taddr)
   ,.m_tvalid(tvalid)
   ,.m_tready(tready)
  );

  //---------------------------------------------------------------------------
  // ストリーム受信モニタ
  //---------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] rx_data [0:255];
  logic [ADDR_WIDTH-1:0] rx_addr [0:255];
  logic [ID_WIDTH-1:0]   rx_id   [0:255];
  logic                  rx_last [0:255];
  int unsigned           rx_cnt;
  logic                  rx_clr;

  always_ff @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      rx_cnt <= 0;
    end else begin
      if( rx_clr ) begin
        rx_cnt <= 0;
      end else if( tvalid&&tready ) begin
        rx_data[rx_cnt] <= tdata;
        rx_addr[rx_cnt] <= taddr;
        rx_id[rx_cnt]   <= tid;
        rx_last[rx_cnt] <= tlast;
        rx_cnt          <= rx_cnt + 1;
      end
    end
  end

  //---------------------------------------------------------------------------
  // ストリーム側 READY 生成 (bp_en=1 でランダムバックプレッシャ)
  //---------------------------------------------------------------------------
  logic bp_en;

  initial begin
    tready = 1'b0;
    bp_en  = 1'b0;
    forever begin
      @(negedge aclk);
      if( bp_en ) begin
        tready = ($urandom_range(0,3)!=0);
      end else begin
        tready = 1'b1;
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

  task automatic chk_eq32
  (
    input string                 tag
   ,input logic [ADDR_WIDTH-1:0] exp
   ,input logic [ADDR_WIDTH-1:0] act
  );
    begin
      if( exp!==act ) begin
        $display("[FAIL] %s exp=%08h act=%08h", tag, exp, act);
        err_cnt = err_cnt + 1;
      end
    end
  endtask

  task automatic clear_rx();
    begin
      @(negedge aclk);
      rx_clr = 1'b1;
      @(negedge aclk);
      rx_clr = 1'b0;
    end
  endtask

  // ストリームで受け取ったビート列を検査する
  task automatic chk_stream( input string tag, input int unsigned n, input logic [ID_WIDTH-1:0] id );
    begin
      if( rx_cnt!=n ) begin
        $display("[FAIL] %s beat count exp=%0d act=%0d", tag, n, rx_cnt);
        err_cnt = err_cnt + 1;
      end else begin
        for( int unsigned i=0; i<n; i++ ) begin
          chk_eq64($sformatf("%s data beat%0d", tag, i), u_bfm.wr_buf[i], rx_data[i]);
          if( rx_last[i]!==(i==(n-1)) ) begin
            $display("[FAIL] %s TLAST beat%0d = %b", tag, i, rx_last[i]);
            err_cnt = err_cnt + 1;
          end
          if( rx_id[i]!==id ) begin
            $display("[FAIL] %s TID beat%0d exp=%0d act=%0d", tag, i, id, rx_id[i]);
            err_cnt = err_cnt + 1;
          end
        end
      end
    end
  endtask

  //---------------------------------------------------------------------------
  // Test sequence
  //---------------------------------------------------------------------------
  initial begin
    err_cnt = 0;
    rx_clr  = 1'b0;
    wait( aresetn===1'b1 );
    u_bfm.wait_clk(2);

    //-------------------------------------------------------------------------
    // TEST1 : INCR burst 8 beats -- バックプレッシャ無し
    //-------------------------------------------------------------------------
    for( int unsigned i=0; i<8; i++ ) begin
      u_bfm.wr_buf[i] = {32'hC0DE_0000 + i, 32'h0BAD_0000 + i};
    end
    clear_rx();
    u_bfm.write_burst(32'h0000_1000, 8'd7, SIZE_8B, BURST_INCR, 4'h5);
    if( u_bfm.last_bresp!==RESP_OKAY ) begin
      $display("[FAIL] TEST1 BRESP=%b", u_bfm.last_bresp);
      err_cnt = err_cnt + 1;
    end
    chk_stream("TEST1", 8, 4'h5);
    for( int unsigned i=0; i<8; i++ ) begin
      chk_eq32($sformatf("TEST1 taddr beat%0d", i), 32'h0000_1000 + ADDR_WIDTH'(i*8), rx_addr[i]);
    end
    $display("[INFO] TEST1 (INCR burst -> stream) done");

    //-------------------------------------------------------------------------
    // TEST2 : ランダムバックプレッシャ下での 16 ビートバースト
    //-------------------------------------------------------------------------
    bp_en = 1'b1;
    for( int unsigned i=0; i<16; i++ ) begin
      u_bfm.wr_buf[i] = {32'h9876_0000 + i, 32'h5432_0000 + i};
    end
    clear_rx();
    u_bfm.write_burst(32'h0000_2000, 8'd15, SIZE_8B, BURST_INCR, 4'hC);
    chk_stream("TEST2", 16, 4'hC);
    bp_en = 1'b0;
    $display("[INFO] TEST2 (random backpressure) done");

    //-------------------------------------------------------------------------
    // TEST3 : WRAP burst -- m_taddr が 0x3018,0x3000,0x3008,0x3010 になること
    //-------------------------------------------------------------------------
    for( int unsigned i=0; i<4; i++ ) begin
      u_bfm.wr_buf[i] = {32'hAAAA_0000 + i, 32'hBBBB_0000 + i};
    end
    clear_rx();
    u_bfm.write_burst(32'h0000_3018, 8'd3, SIZE_8B, BURST_WRAP, 4'h1);
    chk_stream("TEST3", 4, 4'h1);
    chk_eq32("TEST3 taddr beat0", 32'h0000_3018, rx_addr[0]);
    chk_eq32("TEST3 taddr beat1", 32'h0000_3000, rx_addr[1]);
    chk_eq32("TEST3 taddr beat2", 32'h0000_3008, rx_addr[2]);
    chk_eq32("TEST3 taddr beat3", 32'h0000_3010, rx_addr[3]);
    $display("[INFO] TEST3 (WRAP burst address) done");

    //-------------------------------------------------------------------------
    // TEST4 : Read チャネルのダミー応答
    //-------------------------------------------------------------------------
    u_bfm.read_burst(32'h0000_4000, 8'd3, SIZE_8B, BURST_INCR, 4'h8);
    if( u_bfm.last_rresp!==RESP_OKAY ) begin
      $display("[FAIL] TEST4 RRESP=%b", u_bfm.last_rresp);
      err_cnt = err_cnt + 1;
    end
    if( u_bfm.last_rid!==4'h8 ) begin
      $display("[FAIL] TEST4 RID=%0d", u_bfm.last_rid);
      err_cnt = err_cnt + 1;
    end
    if( !u_bfm.last_rlast_ok ) begin
      $display("[FAIL] TEST4 RLAST position mismatch");
      err_cnt = err_cnt + 1;
    end
    for( int unsigned i=0; i<4; i++ ) begin
      chk_eq64($sformatf("TEST4 dummy beat%0d", i), RD_DUMMY_DATA, u_bfm.rd_buf[i]);
    end
    $display("[INFO] TEST4 (read dummy response) done");

    u_bfm.wait_clk(5);
    if( err_cnt==0 ) begin
      $display("=== tb_axi4_full_slave_stream : TEST PASSED ===");
    end else begin
      $display("=== tb_axi4_full_slave_stream : TEST FAILED (%0d errors) ===", err_cnt);
    end
    $finish;
  end

  //---------------------------------------------------------------------------
  // Watchdog
  //---------------------------------------------------------------------------
  initial begin
    #200000;
    $display("=== tb_axi4_full_slave_stream : TIMEOUT ===");
    $finish;
  end

endmodule
