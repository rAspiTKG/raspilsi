//=============================================================================
// tb_apb_smp.sv
//-----------------------------------------------------------------------------
//  apb_if のサンプルの自己チェック TB。
//    1. apb_smp_top (リクエスタ -> コンプリータ 2 つ) を動かし、2 本の apb_if の転送の数と
//       PSLVERR の数を確かめる (Verilator 5.052 は、下の階層にある interface の配列の要素を
//       virtual interface に代入できないので、ここは信号を階層参照で数える)
//    2. TB が req_cb (clocking block) でリクエスタになり、apb_smp_regs (待ち 2) を直接動かす
//       (IDLE を挟まない連続転送、PSTRB の一部だけの書き込み、PSLVERR)。同じ apb_if を mon_cb でも観測する
//  +BAD を付けると 2. の最初の転送で、ACCESS の待ちの間に PADDR を変える。
//  apb_if のプロトコルチェック (a_access_hold) がエラーにすることを確かめる。
//=============================================================================
`timescale 1ns / 1ps

module tb_apb_smp;

  localparam int unsigned AW = 32;
  localparam int unsigned DW = 32;

  logic pclk;
  logic presetn;
  logic start;
  logic busy;
  logic done;
  logic err;
  bit   bad;

  initial begin
    pclk = 1'b0;
    forever begin
      #5;
      pclk = ~pclk;
    end
  end

  //---------------------------------------------------------------------------
  // 1. リクエスタ -> コンプリータ 2 つ
  //---------------------------------------------------------------------------
  apb_smp_top #(
    .ADDR_WIDTH ( AW )
   ,.DATA_WIDTH ( DW )
  ) u_top (
    .pclk    ( pclk    )
   ,.presetn ( presetn )
   ,.start   ( start   )
   ,.busy    ( busy    )
   ,.done    ( done    )
   ,.err     ( err     )
  );

  //---------------------------------------------------------------------------
  // 2. TB (clocking block) -> RTL のコンプリータ
  //---------------------------------------------------------------------------
  apb_if #(
    .ADDR_WIDTH ( AW )
   ,.DATA_WIDTH ( DW )
   ,.TB_ROLE    ( 1  )   // TB がリクエスタの信号を req_cb で駆動する
  ) u_tb_apb (
    .pclk    ( pclk    )
   ,.presetn ( presetn )
  );

  apb_smp_regs #(
    .DATA_WIDTH ( DW )
   ,.OFS_BITS   ( 12 )
   ,.WAIT       ( 2  )
  ) u_regs2 (
    .pclk    ( pclk     )
   ,.presetn ( presetn  )
   ,.s_apb   ( u_tb_apb )
  );

  virtual apb_if #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW), .TB_ROLE(1)).mon_tb vmon;
  virtual apb_if #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW), .TB_ROLE(1)).req_tb vreq;

  int unsigned n_xfer0;
  int unsigned n_xfer1;
  int unsigned n_err1;
  int unsigned n_xfer2;
  int unsigned n_err2;

  task automatic fail(input string msg);
    $display("TB FAIL : %s", msg);
    $fatal(1, "tb_apb_smp failed");
  endtask

  // 1. の 2 本のリンク (階層参照)
  always @(posedge pclk) begin
    if( u_top.u_apb[0].psel&&u_top.u_apb[0].penable&&u_top.u_apb[0].pready ) begin
      n_xfer0++;
    end
    if( u_top.u_apb[1].psel&&u_top.u_apb[1].penable&&u_top.u_apb[1].pready ) begin
      n_xfer1++;
      if( u_top.u_apb[1].pslverr ) begin
        n_err1++;
      end
    end
  end

  // 2. のリンクを mon_cb で観測する
  task automatic monitor();
    forever begin
      @(vmon.mon_cb);
      if( vmon.mon_cb.psel&&vmon.mon_cb.penable&&vmon.mon_cb.pready ) begin
        n_xfer2++;
        if( vmon.mon_cb.pslverr ) begin
          n_err2++;
        end
      end
    end
  endtask

  // 2. の TB リクエスタ : 転送 1 回 (SETUP -> ACCESS)。last=1 なら最後に IDLE に戻る。
  //   inject=1 なら ACCESS の待ちの間に PADDR を変える (プロトコル違反)
  task automatic tb_xfer(input bit write, input logic [AW-1:0] addr, input logic [DW-1:0] data, input logic [DW/8-1:0] strb, input bit exp_err, input bit last, input bit inject);
    vreq.req_cb.psel    <= 1'b1;
    vreq.req_cb.penable <= 1'b0;
    vreq.req_cb.paddr   <= addr;
    vreq.req_cb.pwrite  <= write;
    vreq.req_cb.pwdata  <= write ? data : '0;
    vreq.req_cb.pstrb   <= write ? strb : '0;
    vreq.req_cb.pprot   <= 3'b000;
    @(vreq.req_cb);
    vreq.req_cb.penable <= 1'b1;
    if( inject ) begin
      @(vreq.req_cb);
      vreq.req_cb.paddr <= addr^AW'('h4);
    end
    do begin
      @(vreq.req_cb);
    end while( !vreq.req_cb.pready );
    if( vreq.req_cb.pslverr!=exp_err ) begin
      fail($sformatf("%0h : PSLVERR=%0d, expected %0d", addr, vreq.req_cb.pslverr, exp_err));
    end
    if( !write&&!exp_err&&(vreq.req_cb.prdata!=data) ) begin
      fail($sformatf("read %0h : PRDATA %0h, expected %0h", addr, vreq.req_cb.prdata, data));
    end
    vreq.req_cb.penable <= 1'b0;
    if( last ) begin
      vreq.req_cb.psel <= 1'b0;
    end
  endtask

  initial begin
    bad     = $test$plusargs("BAD");
    vmon    = u_tb_apb;
    vreq    = u_tb_apb;
    presetn = 1'b0;
    start   = 1'b0;
    repeat( 5 ) begin
      @(posedge pclk);
    end
    #1;
    presetn = 1'b1;
    fork
      monitor();
    join_none

    //-------------------------------------------------------------------------
    // 1. RTL 同士
    //-------------------------------------------------------------------------
    @(posedge pclk);
    #1;
    start = 1'b1;
    @(posedge pclk);
    #1;
    start = 1'b0;
    for( int n=0; !done; n++ ) begin
      if( n>2000 ) begin
        fail("part 1 : timeout");
      end
      @(posedge pclk);
    end
    @(posedge pclk);
    if( err ) begin
      fail("part 1 : apb_smp_req reported an error");
    end
    if( (n_xfer0!=4)||(n_xfer1!=5)||(n_err1!=1) ) begin
      fail($sformatf("part 1 : transfers %0d / %0d, PSLVERR %0d", n_xfer0, n_xfer1, n_err1));
    end
    $display("part 1 : OK (completer 0 : %0d transfers, completer 1 : %0d transfers incl. %0d PSLVERR)", n_xfer0, n_xfer1, n_err1);

    //-------------------------------------------------------------------------
    // 2. TB リクエスタ
    //-------------------------------------------------------------------------
    @(vreq.req_cb);
    tb_xfer(1'b1, 32'h0, 32'hCAFE_0000, 4'hF, 1'b0, 1'b0, bad);
    tb_xfer(1'b1, 32'h4, 32'hCAFE_0004, 4'hF, 1'b0, 1'b0, 1'b0);
    tb_xfer(1'b1, 32'h4, 32'hEE00_0000, 4'h8, 1'b0, 1'b1, 1'b0);
    tb_xfer(1'b0, 32'h0, 32'hCAFE_0000, 4'h0, 1'b0, 1'b0, 1'b0);
    tb_xfer(1'b0, 32'h4, 32'hEEFE_0004, 4'h0, 1'b0, 1'b0, 1'b0);
    tb_xfer(1'b0, 32'h40, 32'h0, 4'h0, 1'b1, 1'b1, 1'b0);
    @(vreq.req_cb);
    if( (n_xfer2!=6)||(n_err2!=1) ) begin
      fail($sformatf("part 2 : %0d transfers, %0d PSLVERR", n_xfer2, n_err2));
    end
    $display("part 2 : OK (back-to-back transfers / partial PSTRB / PSLVERR : %0d transfers, %0d PSLVERR)", n_xfer2, n_err2);

    if( bad ) begin
      fail("+BAD : the protocol violation was not detected");
    end
    repeat( 5 ) begin
      @(posedge pclk);
    end
    $display("TB PASS");
    $finish;
  end

  // 全体のタイムアウト
  initial begin
    #200us;
    fail("global timeout");
  end

endmodule
