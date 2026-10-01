//=============================================================================
// tb_axi4_full_passthrough.sv
//-----------------------------------------------------------------------------
//  axi4_full_passthrough の簡易自己チェックテストベンチ。
//    BFM(master) --> axi4_full_passthrough --> axi4_full_slave_mem
//  下流に検証済みのループバックスレーブを置き、パススルー経由で
//  write したデータが read で戻ることを確認する。
//    TEST1 : INCR バースト 8 ビート
//    TEST2 : WRAP バースト 4 ビート
//    TEST3 : 16 ビートの連続バースト (スキッドバッファのスループット確認)
//=============================================================================
`timescale 1ns / 1ps

module tb_axi4_full_passthrough #(
  // 0 : スキッドバッファ挿入 / 1 : 単純結線。-GPT_BYPASS=1 で切り替えられる
  parameter bit PT_BYPASS = 1'b0
) ();

  //---------------------------------------------------------------------------
  // Parameters
  //---------------------------------------------------------------------------
  localparam int unsigned ADDR_WIDTH = 32;
  localparam int unsigned DATA_WIDTH = 64;
  localparam int unsigned ID_WIDTH   = 4;
  localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
  localparam int unsigned MEM_DEPTH  = 1024;

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
  // Upstream : BFM <-> passthrough slave port
  //---------------------------------------------------------------------------
  logic [ID_WIDTH-1:0]   s_awid;
  logic [ADDR_WIDTH-1:0] s_awaddr;
  logic [7:0]            s_awlen;
  logic [2:0]            s_awsize;
  logic [1:0]            s_awburst;
  logic                  s_awlock;
  logic [3:0]            s_awcache;
  logic [2:0]            s_awprot;
  logic [3:0]            s_awqos;
  logic [3:0]            s_awregion;
  logic                  s_awvalid;
  logic                  s_awready;
  logic [DATA_WIDTH-1:0] s_wdata;
  logic [STRB_WIDTH-1:0] s_wstrb;
  logic                  s_wlast;
  logic                  s_wvalid;
  logic                  s_wready;
  logic [ID_WIDTH-1:0]   s_bid;
  logic [1:0]            s_bresp;
  logic                  s_bvalid;
  logic                  s_bready;
  logic [ID_WIDTH-1:0]   s_arid;
  logic [ADDR_WIDTH-1:0] s_araddr;
  logic [7:0]            s_arlen;
  logic [2:0]            s_arsize;
  logic [1:0]            s_arburst;
  logic                  s_arlock;
  logic [3:0]            s_arcache;
  logic [2:0]            s_arprot;
  logic [3:0]            s_arqos;
  logic [3:0]            s_arregion;
  logic                  s_arvalid;
  logic                  s_arready;
  logic [ID_WIDTH-1:0]   s_rid;
  logic [DATA_WIDTH-1:0] s_rdata;
  logic [1:0]            s_rresp;
  logic                  s_rlast;
  logic                  s_rvalid;
  logic                  s_rready;

  //---------------------------------------------------------------------------
  // Downstream : passthrough master port <-> slave memory
  //---------------------------------------------------------------------------
  logic [ID_WIDTH-1:0]   m_awid;
  logic [ADDR_WIDTH-1:0] m_awaddr;
  logic [7:0]            m_awlen;
  logic [2:0]            m_awsize;
  logic [1:0]            m_awburst;
  logic                  m_awlock;
  logic [3:0]            m_awcache;
  logic [2:0]            m_awprot;
  logic [3:0]            m_awqos;
  logic [3:0]            m_awregion;
  logic                  m_awvalid;
  logic                  m_awready;
  logic [DATA_WIDTH-1:0] m_wdata;
  logic [STRB_WIDTH-1:0] m_wstrb;
  logic                  m_wlast;
  logic                  m_wvalid;
  logic                  m_wready;
  logic [ID_WIDTH-1:0]   m_bid;
  logic [1:0]            m_bresp;
  logic                  m_bvalid;
  logic                  m_bready;
  logic [ID_WIDTH-1:0]   m_arid;
  logic [ADDR_WIDTH-1:0] m_araddr;
  logic [7:0]            m_arlen;
  logic [2:0]            m_arsize;
  logic [1:0]            m_arburst;
  logic                  m_arlock;
  logic [3:0]            m_arcache;
  logic [2:0]            m_arprot;
  logic [3:0]            m_arqos;
  logic [3:0]            m_arregion;
  logic                  m_arvalid;
  logic                  m_arready;
  logic [ID_WIDTH-1:0]   m_rid;
  logic [DATA_WIDTH-1:0] m_rdata;
  logic [1:0]            m_rresp;
  logic                  m_rlast;
  logic                  m_rvalid;
  logic                  m_rready;

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
   ,.m_axi_awid(s_awid)
   ,.m_axi_awaddr(s_awaddr)
   ,.m_axi_awlen(s_awlen)
   ,.m_axi_awsize(s_awsize)
   ,.m_axi_awburst(s_awburst)
   ,.m_axi_awlock(s_awlock)
   ,.m_axi_awcache(s_awcache)
   ,.m_axi_awprot(s_awprot)
   ,.m_axi_awqos(s_awqos)
   ,.m_axi_awregion(s_awregion)
   ,.m_axi_awvalid(s_awvalid)
   ,.m_axi_awready(s_awready)
   ,.m_axi_wdata(s_wdata)
   ,.m_axi_wstrb(s_wstrb)
   ,.m_axi_wlast(s_wlast)
   ,.m_axi_wvalid(s_wvalid)
   ,.m_axi_wready(s_wready)
   ,.m_axi_bid(s_bid)
   ,.m_axi_bresp(s_bresp)
   ,.m_axi_bvalid(s_bvalid)
   ,.m_axi_bready(s_bready)
   ,.m_axi_arid(s_arid)
   ,.m_axi_araddr(s_araddr)
   ,.m_axi_arlen(s_arlen)
   ,.m_axi_arsize(s_arsize)
   ,.m_axi_arburst(s_arburst)
   ,.m_axi_arlock(s_arlock)
   ,.m_axi_arcache(s_arcache)
   ,.m_axi_arprot(s_arprot)
   ,.m_axi_arqos(s_arqos)
   ,.m_axi_arregion(s_arregion)
   ,.m_axi_arvalid(s_arvalid)
   ,.m_axi_arready(s_arready)
   ,.m_axi_rid(s_rid)
   ,.m_axi_rdata(s_rdata)
   ,.m_axi_rresp(s_rresp)
   ,.m_axi_rlast(s_rlast)
   ,.m_axi_rvalid(s_rvalid)
   ,.m_axi_rready(s_rready)
  );

  //---------------------------------------------------------------------------
  // DUT : passthrough
  //---------------------------------------------------------------------------
  axi4_full_passthrough #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.ID_WIDTH(ID_WIDTH)
   ,.BYPASS(PT_BYPASS)
  ) u_dut (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.s_axi_awid(s_awid)
   ,.s_axi_awaddr(s_awaddr)
   ,.s_axi_awlen(s_awlen)
   ,.s_axi_awsize(s_awsize)
   ,.s_axi_awburst(s_awburst)
   ,.s_axi_awlock(s_awlock)
   ,.s_axi_awcache(s_awcache)
   ,.s_axi_awprot(s_awprot)
   ,.s_axi_awqos(s_awqos)
   ,.s_axi_awregion(s_awregion)
   ,.s_axi_awvalid(s_awvalid)
   ,.s_axi_awready(s_awready)
   ,.s_axi_wdata(s_wdata)
   ,.s_axi_wstrb(s_wstrb)
   ,.s_axi_wlast(s_wlast)
   ,.s_axi_wvalid(s_wvalid)
   ,.s_axi_wready(s_wready)
   ,.s_axi_bid(s_bid)
   ,.s_axi_bresp(s_bresp)
   ,.s_axi_bvalid(s_bvalid)
   ,.s_axi_bready(s_bready)
   ,.s_axi_arid(s_arid)
   ,.s_axi_araddr(s_araddr)
   ,.s_axi_arlen(s_arlen)
   ,.s_axi_arsize(s_arsize)
   ,.s_axi_arburst(s_arburst)
   ,.s_axi_arlock(s_arlock)
   ,.s_axi_arcache(s_arcache)
   ,.s_axi_arprot(s_arprot)
   ,.s_axi_arqos(s_arqos)
   ,.s_axi_arregion(s_arregion)
   ,.s_axi_arvalid(s_arvalid)
   ,.s_axi_arready(s_arready)
   ,.s_axi_rid(s_rid)
   ,.s_axi_rdata(s_rdata)
   ,.s_axi_rresp(s_rresp)
   ,.s_axi_rlast(s_rlast)
   ,.s_axi_rvalid(s_rvalid)
   ,.s_axi_rready(s_rready)
   ,.m_axi_awid(m_awid)
   ,.m_axi_awaddr(m_awaddr)
   ,.m_axi_awlen(m_awlen)
   ,.m_axi_awsize(m_awsize)
   ,.m_axi_awburst(m_awburst)
   ,.m_axi_awlock(m_awlock)
   ,.m_axi_awcache(m_awcache)
   ,.m_axi_awprot(m_awprot)
   ,.m_axi_awqos(m_awqos)
   ,.m_axi_awregion(m_awregion)
   ,.m_axi_awvalid(m_awvalid)
   ,.m_axi_awready(m_awready)
   ,.m_axi_wdata(m_wdata)
   ,.m_axi_wstrb(m_wstrb)
   ,.m_axi_wlast(m_wlast)
   ,.m_axi_wvalid(m_wvalid)
   ,.m_axi_wready(m_wready)
   ,.m_axi_bid(m_bid)
   ,.m_axi_bresp(m_bresp)
   ,.m_axi_bvalid(m_bvalid)
   ,.m_axi_bready(m_bready)
   ,.m_axi_arid(m_arid)
   ,.m_axi_araddr(m_araddr)
   ,.m_axi_arlen(m_arlen)
   ,.m_axi_arsize(m_arsize)
   ,.m_axi_arburst(m_arburst)
   ,.m_axi_arlock(m_arlock)
   ,.m_axi_arcache(m_arcache)
   ,.m_axi_arprot(m_arprot)
   ,.m_axi_arqos(m_arqos)
   ,.m_axi_arregion(m_arregion)
   ,.m_axi_arvalid(m_arvalid)
   ,.m_axi_arready(m_arready)
   ,.m_axi_rid(m_rid)
   ,.m_axi_rdata(m_rdata)
   ,.m_axi_rresp(m_rresp)
   ,.m_axi_rlast(m_rlast)
   ,.m_axi_rvalid(m_rvalid)
   ,.m_axi_rready(m_rready)
  );

  //---------------------------------------------------------------------------
  // 下流スレーブ (ループバックメモリ)
  //---------------------------------------------------------------------------
  axi4_full_slave_mem #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.ID_WIDTH(ID_WIDTH)
   ,.MEM_DEPTH(MEM_DEPTH)
  ) u_slv (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.s_axi_awid(m_awid)
   ,.s_axi_awaddr(m_awaddr)
   ,.s_axi_awlen(m_awlen)
   ,.s_axi_awsize(m_awsize)
   ,.s_axi_awburst(m_awburst)
   ,.s_axi_awlock(m_awlock)
   ,.s_axi_awcache(m_awcache)
   ,.s_axi_awprot(m_awprot)
   ,.s_axi_awqos(m_awqos)
   ,.s_axi_awregion(m_awregion)
   ,.s_axi_awvalid(m_awvalid)
   ,.s_axi_awready(m_awready)
   ,.s_axi_wdata(m_wdata)
   ,.s_axi_wstrb(m_wstrb)
   ,.s_axi_wlast(m_wlast)
   ,.s_axi_wvalid(m_wvalid)
   ,.s_axi_wready(m_wready)
   ,.s_axi_bid(m_bid)
   ,.s_axi_bresp(m_bresp)
   ,.s_axi_bvalid(m_bvalid)
   ,.s_axi_bready(m_bready)
   ,.s_axi_arid(m_arid)
   ,.s_axi_araddr(m_araddr)
   ,.s_axi_arlen(m_arlen)
   ,.s_axi_arsize(m_arsize)
   ,.s_axi_arburst(m_arburst)
   ,.s_axi_arlock(m_arlock)
   ,.s_axi_arcache(m_arcache)
   ,.s_axi_arprot(m_arprot)
   ,.s_axi_arqos(m_arqos)
   ,.s_axi_arregion(m_arregion)
   ,.s_axi_arvalid(m_arvalid)
   ,.s_axi_arready(m_arready)
   ,.s_axi_rid(m_rid)
   ,.s_axi_rdata(m_rdata)
   ,.s_axi_rresp(m_rresp)
   ,.s_axi_rlast(m_rlast)
   ,.s_axi_rvalid(m_rvalid)
   ,.s_axi_rready(m_rready)
  );

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
  // W チャネルのビート数が上流と下流で一致するか監視する
  //---------------------------------------------------------------------------
  int unsigned s_w_beats;
  int unsigned m_w_beats;

  always_ff @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      s_w_beats <= 0;
      m_w_beats <= 0;
    end else begin
      if( s_wvalid&&s_wready ) begin
        s_w_beats <= s_w_beats + 1;
      end
      if( m_wvalid&&m_wready ) begin
        m_w_beats <= m_w_beats + 1;
      end
    end
  end

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
      u_bfm.wr_buf[i] = {32'h1111_0000 + i, 32'h2222_0000 + i};
    end
    u_bfm.write_burst(32'h0000_0080, 8'd7, SIZE_8B, BURST_INCR, 4'h6);
    chk_resp("TEST1", 4'h6);
    u_bfm.read_burst(32'h0000_0080, 8'd7, SIZE_8B, BURST_INCR, 4'h9);
    chk_rresp("TEST1", 4'h9);
    for( int unsigned i=0; i<8; i++ ) begin
      chk_eq64($sformatf("TEST1 INCR beat%0d", i), u_bfm.wr_buf[i], u_bfm.rd_buf[i]);
    end
    $display("[INFO] TEST1 (INCR burst through passthrough) done");

    //-------------------------------------------------------------------------
    // TEST2 : WRAP burst 4 beats
    //-------------------------------------------------------------------------
    for( int unsigned i=0; i<4; i++ ) begin
      u_bfm.wr_buf[i] = {32'h3333_0000 + i, 32'h4444_0000 + i};
      exp_data[i]     = {32'h3333_0000 + i, 32'h4444_0000 + i};
    end
    u_bfm.write_burst(32'h0000_0218, 8'd3, SIZE_8B, BURST_WRAP, 4'hA);
    chk_resp("TEST2", 4'hA);
    u_bfm.read_burst(32'h0000_0218, 8'd3, SIZE_8B, BURST_WRAP, 4'hA);
    chk_rresp("TEST2", 4'hA);
    for( int unsigned i=0; i<4; i++ ) begin
      chk_eq64($sformatf("TEST2 WRAP beat%0d", i), exp_data[i], u_bfm.rd_buf[i]);
    end
    $display("[INFO] TEST2 (WRAP burst through passthrough) done");

    //-------------------------------------------------------------------------
    // TEST3 : 16 ビートバースト + ビート数一致確認
    //-------------------------------------------------------------------------
    for( int unsigned i=0; i<16; i++ ) begin
      u_bfm.wr_buf[i] = {32'h5A5A_0000 + i, 32'h0F0F_0000 + i};
    end
    u_bfm.write_burst(32'h0000_0400, 8'd15, SIZE_8B, BURST_INCR, 4'h4);
    chk_resp("TEST3", 4'h4);
    u_bfm.read_burst(32'h0000_0400, 8'd15, SIZE_8B, BURST_INCR, 4'h4);
    chk_rresp("TEST3", 4'h4);
    for( int unsigned i=0; i<16; i++ ) begin
      chk_eq64($sformatf("TEST3 beat%0d", i), u_bfm.wr_buf[i], u_bfm.rd_buf[i]);
    end
    if( s_w_beats!=m_w_beats ) begin
      $display("[FAIL] W beat count mismatch slave=%0d master=%0d", s_w_beats, m_w_beats);
      err_cnt = err_cnt + 1;
    end
    $display("[INFO] TEST3 (16-beat burst, W beats s=%0d m=%0d) done", s_w_beats, m_w_beats);
    $display("[INFO] PT_BYPASS=%0d", PT_BYPASS);

    u_bfm.wait_clk(5);
    if( err_cnt==0 ) begin
      $display("=== tb_axi4_full_passthrough : TEST PASSED ===");
    end else begin
      $display("=== tb_axi4_full_passthrough : TEST FAILED (%0d errors) ===", err_cnt);
    end
    $finish;
  end

  //---------------------------------------------------------------------------
  // Watchdog
  //---------------------------------------------------------------------------
  initial begin
    #200000;
    $display("=== tb_axi4_full_passthrough : TIMEOUT ===");
    $finish;
  end

endmodule
