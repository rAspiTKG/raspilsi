//=============================================================================
// tb_role_chk.sv
//-----------------------------------------------------------------------------
//  TB_ROLE の確認 ($warning) の自己テスト。
//  6 種類の interface をそれぞれ TB_ROLE=1 と TB_ROLE=2 で置き、
//    - TB_ROLE がつなぐ側の clocking block に書く   : 信号が変わること (警告は出ない)
//    - TB_ROLE がつながない側の clocking block に書く : 信号は変わらず、$warning が出ること
//  を確かめる。警告は 6 x 2 = 12 個出る (数と中身は Makefile がログで確かめる)。
//  プロトコルチェックは CHECK=0 で止める (片側だけ VALID を上げたままにするため)。
//=============================================================================
`timescale 1ns / 1ps

module tb_role_chk;

  logic clk;
  logic rst_n;
  int   n_err;

  initial begin
    clk = 1'b0;
    forever begin
      #5;
      clk = ~clk;
    end
  end

  //---------------------------------------------------------------------------
  // interface (x1 : TB_ROLE=1、x2 : TB_ROLE=2)
  //---------------------------------------------------------------------------
  axi4_if #(
    .CHECK   ( 1'b0 )
   ,.TB_ROLE ( 1    )
  ) u_axi4_1 (
    .aclk    ( clk   )
   ,.aresetn ( rst_n )
  );

  axi4_if #(
    .CHECK   ( 1'b0 )
   ,.TB_ROLE ( 2    )
  ) u_axi4_2 (
    .aclk    ( clk   )
   ,.aresetn ( rst_n )
  );

  axil_if #(
    .CHECK   ( 1'b0 )
   ,.TB_ROLE ( 1    )
  ) u_axil_1 (
    .aclk    ( clk   )
   ,.aresetn ( rst_n )
  );

  axil_if #(
    .CHECK   ( 1'b0 )
   ,.TB_ROLE ( 2    )
  ) u_axil_2 (
    .aclk    ( clk   )
   ,.aresetn ( rst_n )
  );

  ahb_if #(
    .CHECK   ( 1'b0 )
   ,.TB_ROLE ( 1    )
  ) u_ahb_1 (
    .hclk    ( clk   )
   ,.hresetn ( rst_n )
  );

  ahb_if #(
    .CHECK   ( 1'b0 )
   ,.TB_ROLE ( 2    )
  ) u_ahb_2 (
    .hclk    ( clk   )
   ,.hresetn ( rst_n )
  );

  apb_if #(
    .CHECK   ( 1'b0 )
   ,.TB_ROLE ( 1    )
  ) u_apb_1 (
    .pclk    ( clk   )
   ,.presetn ( rst_n )
  );

  apb_if #(
    .CHECK   ( 1'b0 )
   ,.TB_ROLE ( 2    )
  ) u_apb_2 (
    .pclk    ( clk   )
   ,.presetn ( rst_n )
  );

  p2p_if #(
    .CHECK   ( 1'b0 )
   ,.TB_ROLE ( 1    )
  ) u_p2p_1 (
    .clk   ( clk   )
   ,.rst_n ( rst_n )
  );

  p2p_if #(
    .CHECK   ( 1'b0 )
   ,.TB_ROLE ( 2    )
  ) u_p2p_2 (
    .clk   ( clk   )
   ,.rst_n ( rst_n )
  );

  strm_if #(
    .CHECK   ( 1'b0 )
   ,.TB_ROLE ( 1    )
  ) u_strm_1 (
    .clk   ( clk   )
   ,.rst_n ( rst_n )
  );

  strm_if #(
    .CHECK   ( 1'b0 )
   ,.TB_ROLE ( 2    )
  ) u_strm_2 (
    .clk   ( clk   )
   ,.rst_n ( rst_n )
  );

  virtual axi4_if #(.CHECK(1'b0), .TB_ROLE(1)) v_axi4_1;
  virtual axi4_if #(.CHECK(1'b0), .TB_ROLE(2)) v_axi4_2;
  virtual axil_if #(.CHECK(1'b0), .TB_ROLE(1)) v_axil_1;
  virtual axil_if #(.CHECK(1'b0), .TB_ROLE(2)) v_axil_2;
  virtual ahb_if  #(.CHECK(1'b0), .TB_ROLE(1)) v_ahb_1;
  virtual ahb_if  #(.CHECK(1'b0), .TB_ROLE(2)) v_ahb_2;
  virtual apb_if  #(.CHECK(1'b0), .TB_ROLE(1)) v_apb_1;
  virtual apb_if  #(.CHECK(1'b0), .TB_ROLE(2)) v_apb_2;
  virtual p2p_if  #(.CHECK(1'b0), .TB_ROLE(1)) v_p2p_1;
  virtual p2p_if  #(.CHECK(1'b0), .TB_ROLE(2)) v_p2p_2;
  virtual strm_if #(.CHECK(1'b0), .TB_ROLE(1)) v_strm_1;
  virtual strm_if #(.CHECK(1'b0), .TB_ROLE(2)) v_strm_2;

  // つながる側 : 書いた値 (1) になっていること
  task automatic expect_driven(input string name, input logic got);
    if( got!==1'b1 ) begin
      $display("ROLE FAIL : %s = %b (expected 1 : TB_ROLE connects this side)", name, got);
      n_err++;
    end
  endtask

  // つながらない側 : 1 になっていないこと (誰も駆動しないので 2 値シミュレータでは 0、4 値なら X)
  task automatic expect_quiet(input string name, input logic got);
    if( got===1'b1 ) begin
      $display("ROLE FAIL : %s = 1 (expected not driven : TB_ROLE does not connect this side)", name);
      n_err++;
    end
  endtask

  initial begin
    n_err    = 0;
    v_axi4_1 = u_axi4_1;
    v_axi4_2 = u_axi4_2;
    v_axil_1 = u_axil_1;
    v_axil_2 = u_axil_2;
    v_ahb_1  = u_ahb_1;
    v_ahb_2  = u_ahb_2;
    v_apb_1  = u_apb_1;
    v_apb_2  = u_apb_2;
    v_p2p_1  = u_p2p_1;
    v_p2p_2  = u_p2p_2;
    v_strm_1 = u_strm_1;
    v_strm_2 = u_strm_2;
    rst_n    = 1'b0;
    repeat( 3 ) begin
      @(posedge clk);
    end
    #1;
    rst_n = 1'b1;
    @(posedge clk);

    //-------------------------------------------------------------------------
    // TB_ROLE=1 : 1 側 (マネージャ / リクエスタ / 送信側) は信号につながる。2 側に書くと警告
    //-------------------------------------------------------------------------
    v_axi4_1.mgr_cb.awvalid <= 1'b1;
    v_axi4_1.sub_cb.awready <= 1'b1;
    v_axil_1.mgr_cb.arvalid <= 1'b1;
    v_axil_1.sub_cb.arready <= 1'b1;
    v_ahb_1.mgr_cb.htrans   <= 2'b10;
    v_ahb_1.sub_cb.hresp    <= 1'b1;
    v_apb_1.req_cb.psel     <= 1'b1;
    v_apb_1.cmp_cb.pready   <= 1'b1;
    v_p2p_1.src_cb.vld      <= 1'b1;
    v_p2p_1.snk_cb.busy     <= 1'b1;
    v_strm_1.src_cb.tvalid  <= 1'b1;
    v_strm_1.snk_cb.tready  <= 1'b1;

    //-------------------------------------------------------------------------
    // TB_ROLE=2 : 2 側 (サブオーディネート / コンプリータ / 受信側) は信号につながる。1 側に書くと警告
    //-------------------------------------------------------------------------
    v_axi4_2.sub_cb.bvalid  <= 1'b1;
    v_axi4_2.mgr_cb.wvalid  <= 1'b1;
    v_axil_2.sub_cb.rvalid  <= 1'b1;
    v_axil_2.mgr_cb.rready  <= 1'b1;
    v_ahb_2.sub_cb.hresp    <= 1'b1;
    v_ahb_2.mgr_cb.hwrite   <= 1'b1;
    v_apb_2.cmp_cb.pslverr  <= 1'b1;
    v_apb_2.req_cb.penable  <= 1'b1;
    v_p2p_2.snk_cb.busy     <= 1'b1;
    v_p2p_2.src_cb.last     <= 1'b1;
    v_strm_2.snk_cb.tready  <= 1'b1;
    v_strm_2.src_cb.tlast   <= 1'b1;

    repeat( 3 ) begin
      @(posedge clk);
    end

    // つながる側は信号が変わり、つながらない側は変わらない
    expect_driven("axi4 TB_ROLE=1 awvalid", u_axi4_1.awvalid);
    expect_quiet("axi4 TB_ROLE=1 awready", u_axi4_1.awready);
    expect_driven("axil TB_ROLE=1 arvalid", u_axil_1.arvalid);
    expect_quiet("axil TB_ROLE=1 arready", u_axil_1.arready);
    expect_driven("ahb  TB_ROLE=1 htrans[1]", u_ahb_1.htrans[1]);
    expect_quiet("ahb  TB_ROLE=1 hresp", u_ahb_1.hresp);
    expect_driven("apb  TB_ROLE=1 psel", u_apb_1.psel);
    expect_quiet("apb  TB_ROLE=1 pready", u_apb_1.pready);
    expect_driven("p2p  TB_ROLE=1 vld", u_p2p_1.vld);
    expect_quiet("p2p  TB_ROLE=1 busy", u_p2p_1.busy);
    expect_driven("strm TB_ROLE=1 tvalid", u_strm_1.tvalid);
    expect_quiet("strm TB_ROLE=1 tready", u_strm_1.tready);
    expect_driven("axi4 TB_ROLE=2 bvalid", u_axi4_2.bvalid);
    expect_quiet("axi4 TB_ROLE=2 wvalid", u_axi4_2.wvalid);
    expect_driven("axil TB_ROLE=2 rvalid", u_axil_2.rvalid);
    expect_quiet("axil TB_ROLE=2 rready", u_axil_2.rready);
    expect_driven("ahb  TB_ROLE=2 hresp", u_ahb_2.hresp);
    expect_quiet("ahb  TB_ROLE=2 hwrite", u_ahb_2.hwrite);
    expect_driven("apb  TB_ROLE=2 pslverr", u_apb_2.pslverr);
    expect_quiet("apb  TB_ROLE=2 penable", u_apb_2.penable);
    expect_driven("p2p  TB_ROLE=2 busy", u_p2p_2.busy);
    expect_quiet("p2p  TB_ROLE=2 last", u_p2p_2.last);
    expect_driven("strm TB_ROLE=2 tready", u_strm_2.tready);
    expect_quiet("strm TB_ROLE=2 tlast", u_strm_2.tlast);

    if( n_err==0 ) begin
      $display("ROLE PASS : connected sides drive the signals, unconnected sides do not");
    end else begin
      $display("ROLE FAIL : %0d mismatches", n_err);
    end
    $finish;
  end

endmodule
