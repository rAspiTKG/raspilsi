//=============================================================================
// tb_strm_smp.sv
//-----------------------------------------------------------------------------
//  strm_if のサンプルの自己チェック TB。
//    1. strm_smp_top (送信側 -> レジスタスライス -> 受信側) を動かし、2 本の strm_if を mon_cb で観測して
//       転送の数と TLAST の数を確かめる。受信側はデータ / TID / TADDR を照合する
//    2. TB が src_cb (clocking block) で送信側になり、strm_smp_sink を直接動かす
//  +BAD を付けると 2. で TREADY=0 の間に TDATA を変える。
//  strm_if のプロトコルチェック (a_hold) がエラーにすることを確かめる。
//=============================================================================
`timescale 1ns / 1ps

module tb_strm_smp #(
  parameter int unsigned DW = 64
 ,parameter int unsigned IW = 4
 ,parameter int unsigned AW = 32
);

  localparam int unsigned     SB    = DW/8;
  localparam int unsigned     NWORD = 16;
  localparam int unsigned     NTB   = 32;
  localparam int unsigned     TID   = 3;
  localparam longint unsigned BASE  = 64'h0000_1000;

  logic clk;
  logic rst_n;
  logic start;
  logic busy;
  logic done;
  logic err;
  logic done2;
  logic err2;
  bit   bad;

  initial begin
    clk = 1'b0;
    forever begin
      #5;
      clk = ~clk;
    end
  end

  //---------------------------------------------------------------------------
  // 1. 送信側 -> レジスタスライス -> 受信側
  //---------------------------------------------------------------------------
  strm_smp_top #(
    .DATA_WIDTH ( DW    )
   ,.ID_WIDTH   ( IW    )
   ,.ADDR_WIDTH ( AW    )
   ,.NWORD      ( NWORD )
  ) u_top (
    .clk   ( clk   )
   ,.rst_n ( rst_n )
   ,.start ( start )
   ,.busy  ( busy  )
   ,.done  ( done  )
   ,.err   ( err   )
  );

  //---------------------------------------------------------------------------
  // 2. TB (clocking block) -> RTL の受信側
  //---------------------------------------------------------------------------
  strm_if #(
    .DATA_WIDTH ( DW )
   ,.ID_WIDTH   ( IW )
   ,.ADDR_WIDTH ( AW )
   ,.TB_ROLE    ( 1  )   // TB が送信側の信号を src_cb で駆動する
  ) u_tb_strm (
    .clk   ( clk   )
   ,.rst_n ( rst_n )
  );

  strm_smp_sink #(
    .DATA_WIDTH ( DW    )
   ,.ID_WIDTH   ( IW    )
   ,.ADDR_WIDTH ( AW    )
   ,.NWORD      ( NTB   )
   ,.SEED       ( 8'h5B )
  ) u_sink2 (
    .clk    ( clk       )
   ,.rst_n  ( rst_n     )
   ,.done   ( done2     )
   ,.err    ( err2      )
   ,.s_strm ( u_tb_strm )
  );

  virtual strm_if #(.DATA_WIDTH(DW), .ID_WIDTH(IW), .ADDR_WIDTH(AW)).mon_tb vmon_a;
  virtual strm_if #(.DATA_WIDTH(DW), .ID_WIDTH(IW), .ADDR_WIDTH(AW)).mon_tb vmon_b;
  virtual strm_if #(.DATA_WIDTH(DW), .ID_WIDTH(IW), .ADDR_WIDTH(AW), .TB_ROLE(1)).src_tb vsrc;

  int unsigned n_a;
  int unsigned n_b;
  int unsigned n_last;
  int unsigned n_done2;
  int unsigned n_wait2;

  task automatic fail(input string msg);
    $display("TB FAIL : %s", msg);
    $fatal(1, "tb_strm_smp failed");
  endtask

  // 1. の 2 本のリンクを mon_cb で観測する
  task automatic monitor_a();
    forever begin
      @(vmon_a.mon_cb);
      if( vmon_a.mon_cb.tvalid&&vmon_a.mon_cb.tready ) begin
        n_a++;
      end
    end
  endtask

  task automatic monitor_b();
    forever begin
      @(vmon_b.mon_cb);
      if( vmon_b.mon_cb.tvalid&&vmon_b.mon_cb.tready ) begin
        n_b++;
        if( vmon_b.mon_cb.tlast ) begin
          n_last++;
        end
      end
    end
  endtask

  always @(posedge clk) begin
    if( done2 ) begin
      n_done2++;
    end
  end

  function automatic logic [DW-1:0] pat(input logic [7:0] i);
    logic [DW-1:0] d;
    for( int k=0; k<SB; k++ ) begin
      d[8*k+:8] = (i*8'(SB)+8'(k))^8'h69;
    end
    return d;
  endfunction

  // 2. の TB 送信側 : n ビート送る。inject=1 なら、最初に TREADY=0 を見たときに TDATA を変える (プロトコル違反)
  task automatic tb_send(input int unsigned n, input bit inject);
    bit injected;
    injected = 1'b0;
    for( int i=0; i<n; i++ ) begin
      vsrc.src_cb.tdata  <= pat(8'(i));
      vsrc.src_cb.tstrb  <= '1;
      vsrc.src_cb.tlast  <= (i==n-1);
      vsrc.src_cb.tid    <= IW'(TID);
      vsrc.src_cb.taddr  <= AW'(BASE+64'(i)*SB);
      vsrc.src_cb.tvalid <= 1'b1;
      @(vsrc.src_cb);
      while( !vsrc.src_cb.tready ) begin
        n_wait2++;
        if( inject&&!injected ) begin
          vsrc.src_cb.tdata <= ~pat(8'(i));
          injected = 1'b1;
        end
        @(vsrc.src_cb);
      end
    end
    vsrc.src_cb.tvalid <= 1'b0;
  endtask

  initial begin
    bad    = $test$plusargs("BAD");
    vmon_a = u_top.u_a;
    vmon_b = u_top.u_b;
    vsrc   = u_tb_strm;
    rst_n  = 1'b0;
    start  = 1'b0;
    repeat( 5 ) begin
      @(posedge clk);
    end
    #1;
    rst_n = 1'b1;
    fork
      monitor_a();
      monitor_b();
    join_none

    //-------------------------------------------------------------------------
    // 1. RTL 同士
    //-------------------------------------------------------------------------
    @(posedge clk);
    #1;
    start = 1'b1;
    @(posedge clk);
    #1;
    start = 1'b0;
    for( int n=0; !done; n++ ) begin
      if( n>2000 ) begin
        fail("part 1 : timeout");
      end
      @(posedge clk);
    end
    @(posedge clk);
    if( err ) begin
      fail("part 1 : strm_smp_sink reported an error");
    end
    if( (n_a!=NWORD)||(n_b!=NWORD)||(n_last!=1) ) begin
      fail($sformatf("part 1 : transfers %0d / %0d, TLAST %0d", n_a, n_b, n_last));
    end
    $display("part 1 : OK (%0d beats through the register slice, TLAST once)", n_b);

    //-------------------------------------------------------------------------
    // 2. TB 送信側
    //-------------------------------------------------------------------------
    @(vsrc.src_cb);
    tb_send(NTB, bad);
    repeat( 3 ) begin
      @(vsrc.src_cb);
    end
    if( err2||(n_done2!=1)||(n_wait2==0) ) begin
      fail($sformatf("part 2 : err=%0d done=%0d wait=%0d", err2, n_done2, n_wait2));
    end
    $display("part 2 : OK (%0d beats from the TB source, TREADY=0 %0d times)", NTB, n_wait2);

    if( bad ) begin
      fail("+BAD : the protocol violation was not detected");
    end
    repeat( 5 ) begin
      @(posedge clk);
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
