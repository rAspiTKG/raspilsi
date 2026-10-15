//=============================================================================
// tb_axi4_smp.sv
//-----------------------------------------------------------------------------
//  axi4_if のサンプルの自己チェック TB。
//    1. axi4_smp_top (RTL のマネージャ -> RTL のサブオーディネート) を動かし、
//       同じ axi4_if を mon_cb で観測してハンドシェイクの数を確かめる
//    2. TB が mgr_cb (clocking block) でマネージャになり、axi4_smp_mem を直接動かす
//       (INCR / WRAP / FIXED / 狭い書き込み。読み出したデータを照合する)
//  +BAD を付けると 2. の最初の書き込みで AWREADY を待たずに AWVALID を下げる。
//  axi4_if のプロトコルチェック (a_aw_hold) がエラーにすること (Makefile の bad ターゲット) で、
//  チェックが働いていることを確かめる。
//=============================================================================
`timescale 1ns / 1ps

module tb_axi4_smp #(
  parameter int unsigned AW = 32
 ,parameter int unsigned DW = 64
 ,parameter int unsigned IW = 4
);

  localparam int unsigned SB    = DW/8;
  localparam int unsigned OFSW  = $clog2(SB);
  localparam int unsigned NBEAT = 8;
  localparam logic [SB-1:0] ALL = '1;

  logic aclk;
  logic aresetn;
  logic start;
  logic busy;
  logic done;
  logic err;
  bit   bad;

  initial begin
    aclk = 1'b0;
    forever begin
      #5;
      aclk = ~aclk;
    end
  end

  //---------------------------------------------------------------------------
  // 1. RTL のマネージャ -> RTL のサブオーディネート
  //---------------------------------------------------------------------------
  axi4_smp_top #(
    .ADDR_WIDTH ( AW    )
   ,.DATA_WIDTH ( DW    )
   ,.ID_WIDTH   ( IW    )
   ,.NBEAT      ( NBEAT )
   ,.READY_DLY  ( 1     )
  ) u_top (
    .aclk    ( aclk    )
   ,.aresetn ( aresetn )
   ,.start   ( start   )
   ,.busy    ( busy    )
   ,.done    ( done    )
   ,.err     ( err     )
  );

  //---------------------------------------------------------------------------
  // 2. TB (clocking block) -> RTL のサブオーディネート
  //---------------------------------------------------------------------------
  axi4_if #(
    .ADDR_WIDTH ( AW )
   ,.DATA_WIDTH ( DW )
   ,.ID_WIDTH   ( IW )
   ,.TB_ROLE    ( 1  )   // TB がマネージャの信号を mgr_cb で駆動する
  ) u_tb_axi (
    .aclk    ( aclk    )
   ,.aresetn ( aresetn )
  );

  axi4_smp_mem #(
    .ADDR_WIDTH ( AW )
   ,.DATA_WIDTH ( DW )
   ,.ID_WIDTH   ( IW )
   ,.READY_DLY  ( 2  )
  ) u_mem2 (
    .aclk    ( aclk     )
   ,.aresetn ( aresetn  )
   ,.s_axi   ( u_tb_axi )
  );

  virtual axi4_if #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW), .ID_WIDTH(IW)).mon_tb vmon;
  virtual axi4_if #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW), .ID_WIDTH(IW), .TB_ROLE(1)).mgr_tb vmgr;

  int unsigned n_aw;
  int unsigned n_w;
  int unsigned n_b;
  int unsigned n_ar;
  int unsigned n_r;

  task automatic fail(input string msg);
    $display("TB FAIL : %s", msg);
    $fatal(1, "tb_axi4_smp failed");
  endtask

  // 1. のバスを mon_cb で観測する
  task automatic monitor();
    forever begin
      @(vmon.mon_cb);
      if( vmon.mon_cb.awvalid&&vmon.mon_cb.awready ) begin
        n_aw++;
      end
      if( vmon.mon_cb.wvalid&&vmon.mon_cb.wready ) begin
        n_w++;
      end
      if( vmon.mon_cb.bvalid&&vmon.mon_cb.bready ) begin
        n_b++;
      end
      if( vmon.mon_cb.arvalid&&vmon.mon_cb.arready ) begin
        n_ar++;
      end
      if( vmon.mon_cb.rvalid&&vmon.mon_cb.rready ) begin
        n_r++;
      end
    end
  endtask

  // 2. の TB マネージャ : 書き込み (AW -> W -> B)
  //   inject=1 なら AWREADY を待たずに AWVALID を下げる (プロトコル違反)
  task automatic tb_write(input logic [AW-1:0] addr, input logic [7:0] len, input logic [2:0] size, input logic [1:0] burst, input logic [DW-1:0] d [$], input logic [SB-1:0] s [$], input bit inject);
    vmgr.mgr_cb.awid    <= IW'(2);
    vmgr.mgr_cb.awaddr  <= addr;
    vmgr.mgr_cb.awlen   <= len;
    vmgr.mgr_cb.awsize  <= size;
    vmgr.mgr_cb.awburst <= burst;
    vmgr.mgr_cb.awvalid <= 1'b1;
    if( inject ) begin
      @(vmgr.mgr_cb);
      vmgr.mgr_cb.awvalid <= 1'b0;
      @(vmgr.mgr_cb);
      vmgr.mgr_cb.awvalid <= 1'b1;
    end
    do begin
      @(vmgr.mgr_cb);
    end while( !vmgr.mgr_cb.awready );
    vmgr.mgr_cb.awvalid <= 1'b0;
    for( int i=0; i<=int'(len); i++ ) begin
      vmgr.mgr_cb.wdata  <= d[i];
      vmgr.mgr_cb.wstrb  <= s[i];
      vmgr.mgr_cb.wlast  <= (i==int'(len));
      vmgr.mgr_cb.wvalid <= 1'b1;
      do begin
        @(vmgr.mgr_cb);
      end while( !vmgr.mgr_cb.wready );
    end
    vmgr.mgr_cb.wvalid <= 1'b0;
    vmgr.mgr_cb.bready <= 1'b1;
    do begin
      @(vmgr.mgr_cb);
    end while( !vmgr.mgr_cb.bvalid );
    vmgr.mgr_cb.bready <= 1'b0;
    if( vmgr.mgr_cb.bresp!=2'b00 ) begin
      fail($sformatf("BRESP=%0d (addr %0h)", vmgr.mgr_cb.bresp, addr));
    end
  endtask

  // 2. の TB マネージャ : 読み出し (AR -> R)。e[i] と照合する
  task automatic tb_read(input logic [AW-1:0] addr, input logic [7:0] len, input logic [2:0] size, input logic [1:0] burst, input logic [DW-1:0] e [$]);
    vmgr.mgr_cb.arid    <= IW'(3);
    vmgr.mgr_cb.araddr  <= addr;
    vmgr.mgr_cb.arlen   <= len;
    vmgr.mgr_cb.arsize  <= size;
    vmgr.mgr_cb.arburst <= burst;
    vmgr.mgr_cb.arvalid <= 1'b1;
    do begin
      @(vmgr.mgr_cb);
    end while( !vmgr.mgr_cb.arready );
    vmgr.mgr_cb.arvalid <= 1'b0;
    vmgr.mgr_cb.rready  <= 1'b1;
    for( int i=0; i<=int'(len); i++ ) begin
      do begin
        @(vmgr.mgr_cb);
      end while( !vmgr.mgr_cb.rvalid );
      if( vmgr.mgr_cb.rdata!=e[i] ) begin
        fail($sformatf("read %0h beat %0d : RDATA %0h, expected %0h", addr, i, vmgr.mgr_cb.rdata, e[i]));
      end
      if( (vmgr.mgr_cb.rresp!=2'b00)||(vmgr.mgr_cb.rid!=IW'(3)) ) begin
        fail($sformatf("read %0h beat %0d : RRESP=%0d RID=%0h", addr, i, vmgr.mgr_cb.rresp, vmgr.mgr_cb.rid));
      end
    end
    vmgr.mgr_cb.rready <= 1'b0;
  endtask

  // TB で使うデータ
  function automatic logic [DW-1:0] dat(input int unsigned i);
    return {DW/32{32'hC0DE_0000+32'(i)}};
  endfunction

  logic [DW-1:0] d [$];
  logic [SB-1:0] s [$];
  logic [DW-1:0] e [$];
  logic [DW-1:0] w0;

  initial begin
    bad  = $test$plusargs("BAD");
    vmon = u_top.u_axi;
    vmgr = u_tb_axi;
    aresetn = 1'b0;
    start   = 1'b0;
    repeat( 5 ) begin
      @(posedge aclk);
    end
    #1;
    aresetn = 1'b1;
    fork
      monitor();
    join_none

    //-------------------------------------------------------------------------
    // 1. RTL 同士
    //-------------------------------------------------------------------------
    @(posedge aclk);
    #1;
    start = 1'b1;
    @(posedge aclk);
    #1;
    start = 1'b0;
    for( int n=0; !done; n++ ) begin
      if( n>2000 ) begin
        fail("part 1 : timeout");
      end
      @(posedge aclk);
    end
    @(posedge aclk);
    if( err ) begin
      fail("part 1 : axi4_smp_mgr reported an error");
    end
    if( (n_aw!=1)||(n_w!=NBEAT)||(n_b!=1)||(n_ar!=2)||(n_r!=NBEAT+4) ) begin
      fail($sformatf("part 1 : handshakes AW=%0d W=%0d B=%0d AR=%0d R=%0d", n_aw, n_w, n_b, n_ar, n_r));
    end
    $display("part 1 : OK (AW=%0d W=%0d B=%0d AR=%0d R=%0d)", n_aw, n_w, n_b, n_ar, n_r);

    //-------------------------------------------------------------------------
    // 2. TB マネージャ
    //-------------------------------------------------------------------------
    @(vmgr.mgr_cb);
    // INCR 4 ビートの書き込み (0x100〜)
    d = {dat(0), dat(1), dat(2), dat(3)};
    s = {ALL, ALL, ALL, ALL};
    tb_write(AW'('h100), 8'd3, 3'(OFSW), 2'b01, d, s, bad);
    // WRAP 4 ビートの読み出し (3 ワード目から : 2, 3, 0, 1)
    e = {dat(2), dat(3), dat(0), dat(1)};
    tb_read(AW'('h100+2*SB), 8'd3, 3'(OFSW), 2'b10, e);
    // FIXED 2 ビートの書き込み (同じワードに 2 回。後のデータが残る)
    d = {dat(10), dat(11)};
    s = {ALL, ALL};
    tb_write(AW'('h100+SB), 8'd1, 3'(OFSW), 2'b00, d, s, 1'b0);
    // 1 バイトの書き込み (0x101 のバイトだけ)
    w0       = '0;
    w0[15:8] = 8'h5A;
    d        = {w0};
    s        = {SB'(2)};
    tb_write(AW'('h101), 8'd0, 3'd0, 2'b01, d, s, 1'b0);
    // INCR 4 ビートの読み出しで確かめる
    w0       = dat(0);
    w0[15:8] = 8'h5A;
    e        = {w0, dat(11), dat(2), dat(3)};
    tb_read(AW'('h100), 8'd3, 3'(OFSW), 2'b01, e);
    $display("part 2 : OK (INCR / WRAP / FIXED / narrow write)");

    if( bad ) begin
      fail("+BAD : the protocol violation was not detected");
    end
    repeat( 5 ) begin
      @(posedge aclk);
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
