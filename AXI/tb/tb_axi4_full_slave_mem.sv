//=============================================================================
// tb_axi4_full_slave_mem.sv
//-----------------------------------------------------------------------------
//  axi4_full_slave_mem の簡易自己チェックテストベンチ。
//    TEST1 : INCR バースト (8 ビート) の write → read 一致確認
//    TEST2 : 単一ビート (LEN=0)
//    TEST3 : FIXED バースト (同一アドレスに上書き → 最終ビートが残る)
//    TEST4 : WRAP バースト (境界折り返しの一致確認)
//    TEST5 : WSTRB によるバイト部分書き込み
//  併せて BRESP/RRESP/BID/RID/RLAST も確認する。
//=============================================================================
`timescale 1ns / 1ps

module tb_axi4_full_slave_mem;

  //---------------------------------------------------------------------------
  // Parameters
  //---------------------------------------------------------------------------
  localparam int unsigned ADDR_WIDTH = 32;
  localparam int unsigned DATA_WIDTH = 64;
  localparam int unsigned ID_WIDTH   = 4;
  localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
  localparam int unsigned MEM_DEPTH  = 1024;

  localparam logic [2:0] SIZE_8B      = 3'd3;
  localparam logic [1:0] BURST_FIXED  = 2'b00;
  localparam logic [1:0] BURST_INCR   = 2'b01;
  localparam logic [1:0] BURST_WRAP   = 2'b10;
  localparam logic [1:0] RESP_OKAY    = 2'b00;

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
  axi4_full_slave_mem #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.ID_WIDTH(ID_WIDTH)
   ,.MEM_DEPTH(MEM_DEPTH)
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
  );

  //---------------------------------------------------------------------------
  // Checkers
  //---------------------------------------------------------------------------
  task automatic chk_eq64
  (
    input string                tag
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

  task automatic chk_resp( input string tag, input logic [ID_WIDTH-1:0] id );
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
  logic [DATA_WIDTH-1:0] exp_data [0:15];

  initial begin
    err_cnt = 0;
    wait( aresetn===1'b1 );
    u_bfm.wait_clk(2);

    //-------------------------------------------------------------------------
    // TEST1 : INCR burst 8 beats
    //-------------------------------------------------------------------------
    for( int unsigned i=0; i<8; i++ ) begin
      u_bfm.wr_buf[i] = {32'hA5A5_0000 + i, 32'h1234_0000 + i};
    end
    u_bfm.write_burst(32'h0000_0100, 8'd7, SIZE_8B, BURST_INCR, 4'h3);
    chk_resp("TEST1", 4'h3);
    u_bfm.read_burst(32'h0000_0100, 8'd7, SIZE_8B, BURST_INCR, 4'h5);
    chk_rresp("TEST1", 4'h5);
    for( int unsigned i=0; i<8; i++ ) begin
      chk_eq64($sformatf("TEST1 INCR beat%0d", i), u_bfm.wr_buf[i], u_bfm.rd_buf[i]);
    end
    $display("[INFO] TEST1 (INCR burst) done");

    //-------------------------------------------------------------------------
    // TEST2 : single beat
    //-------------------------------------------------------------------------
    u_bfm.wr_buf[0] = 64'h0123_4567_89AB_CDEF;
    u_bfm.write_burst(32'h0000_0200, 8'd0, SIZE_8B, BURST_INCR, 4'h1);
    chk_resp("TEST2", 4'h1);
    u_bfm.read_burst(32'h0000_0200, 8'd0, SIZE_8B, BURST_INCR, 4'h1);
    chk_rresp("TEST2", 4'h1);
    chk_eq64("TEST2 single", u_bfm.wr_buf[0], u_bfm.rd_buf[0]);
    $display("[INFO] TEST2 (single beat) done");

    //-------------------------------------------------------------------------
    // TEST3 : FIXED burst -- 全ビートが同一アドレスへ。最終ビートが残る
    //-------------------------------------------------------------------------
    for( int unsigned i=0; i<4; i++ ) begin
      u_bfm.wr_buf[i] = {32'hF1F1_0000 + i, 32'hCAFE_0000 + i};
    end
    u_bfm.write_burst(32'h0000_0300, 8'd3, SIZE_8B, BURST_FIXED, 4'h7);
    chk_resp("TEST3", 4'h7);
    u_bfm.read_burst(32'h0000_0300, 8'd3, SIZE_8B, BURST_FIXED, 4'h7);
    chk_rresp("TEST3", 4'h7);
    for( int unsigned i=0; i<4; i++ ) begin
      chk_eq64($sformatf("TEST3 FIXED beat%0d", i), u_bfm.wr_buf[3], u_bfm.rd_buf[i]);
    end
    $display("[INFO] TEST3 (FIXED burst) done");

    //-------------------------------------------------------------------------
    // TEST4 : WRAP burst
    //   size=8B, len+1=4 -> total 32B, start 0x418 -> 0x418,0x400,0x408,0x410
    //-------------------------------------------------------------------------
    for( int unsigned i=0; i<4; i++ ) begin
      u_bfm.wr_buf[i] = {32'h7A70_0000 + i, 32'hBEEF_0000 + i};
    end
    u_bfm.write_burst(32'h0000_0418, 8'd3, SIZE_8B, BURST_WRAP, 4'h2);
    chk_resp("TEST4", 4'h2);
    for( int unsigned i=0; i<4; i++ ) begin
      exp_data[i] = u_bfm.wr_buf[i];
    end
    u_bfm.read_burst(32'h0000_0418, 8'd3, SIZE_8B, BURST_WRAP, 4'h2);
    chk_rresp("TEST4", 4'h2);
    for( int unsigned i=0; i<4; i++ ) begin
      chk_eq64($sformatf("TEST4 WRAP beat%0d", i), exp_data[i], u_bfm.rd_buf[i]);
    end
    // 折り返し先 0x400 を INCR で読み、書いた順序どおりか確認する
    u_bfm.read_burst(32'h0000_0400, 8'd3, SIZE_8B, BURST_INCR, 4'h2);
    chk_eq64("TEST4 mem[0x400]", exp_data[1], u_bfm.rd_buf[0]);
    chk_eq64("TEST4 mem[0x408]", exp_data[2], u_bfm.rd_buf[1]);
    chk_eq64("TEST4 mem[0x410]", exp_data[3], u_bfm.rd_buf[2]);
    chk_eq64("TEST4 mem[0x418]", exp_data[0], u_bfm.rd_buf[3]);
    $display("[INFO] TEST4 (WRAP burst) done");

    //-------------------------------------------------------------------------
    // TEST5 : WSTRB によるバイト部分書き込み
    //-------------------------------------------------------------------------
    u_bfm.wr_buf[0]      = 64'hAAAA_AAAA_AAAA_AAAA;
    u_bfm.wr_strb_buf[0] = 8'hFF;
    u_bfm.write_burst(32'h0000_0500, 8'd0, SIZE_8B, BURST_INCR, 4'h0);
    u_bfm.wr_buf[0]      = 64'h5555_5555_5555_5555;
    u_bfm.wr_strb_buf[0] = 8'h0F;
    u_bfm.write_burst(32'h0000_0500, 8'd0, SIZE_8B, BURST_INCR, 4'h0);
    u_bfm.wr_strb_buf[0] = 8'hFF;
    u_bfm.read_burst(32'h0000_0500, 8'd0, SIZE_8B, BURST_INCR, 4'h0);
    chk_eq64("TEST5 WSTRB", 64'hAAAA_AAAA_5555_5555, u_bfm.rd_buf[0]);
    $display("[INFO] TEST5 (WSTRB partial write) done");

    u_bfm.wait_clk(5);
    if( err_cnt==0 ) begin
      $display("=== tb_axi4_full_slave_mem : TEST PASSED ===");
    end else begin
      $display("=== tb_axi4_full_slave_mem : TEST FAILED (%0d errors) ===", err_cnt);
    end
    $finish;
  end

  //---------------------------------------------------------------------------
  // Watchdog
  //---------------------------------------------------------------------------
  initial begin
    #200000;
    $display("=== tb_axi4_full_slave_mem : TIMEOUT ===");
    $finish;
  end

endmodule
