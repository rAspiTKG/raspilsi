//=============================================================================
// tb_ahb_smp.sv
//-----------------------------------------------------------------------------
//  ahb_if のサンプルの自己チェック TB。
//    1. ahb_smp_top (マネージャ -> インターコネクト -> サブオーディネート 2 つ) を動かし、
//       マネージャ側の ahb_if を mon_cb で観測して、転送の数と ERROR 応答の数を確かめる
//    2. TB が mgr_cb (clocking block) でマネージャになり、ahb_smp_mem (待ち 2) を直接動かす
//       (BUSY を挟んだ INCR4 の書き込み、INCR4 / WRAP4 の読み出し、バイトの書き込み)
//  +BAD を付けると 2. で待ちの間に NONSEQ / SEQ の HADDR を変える。
//  ahb_if のプロトコルチェック (a_wait_hold) がエラーにすることを確かめる。
//=============================================================================
`timescale 1ns / 1ps

module tb_ahb_smp;

  localparam int unsigned AW = 32;
  localparam int unsigned DW = 32;

  localparam logic [1:0] IDLE   = 2'b00;
  localparam logic [1:0] BUSY   = 2'b01;
  localparam logic [1:0] NONSEQ = 2'b10;
  localparam logic [1:0] SEQ    = 2'b11;
  localparam logic [2:0] SINGLE = 3'b000;
  localparam logic [2:0] WRAP4  = 3'b010;
  localparam logic [2:0] INCR4  = 3'b011;

  logic hclk;
  logic hresetn;
  logic start;
  logic busy;
  logic done;
  logic err;
  bit   bad;

  initial begin
    hclk = 1'b0;
    forever begin
      #5;
      hclk = ~hclk;
    end
  end

  //---------------------------------------------------------------------------
  // 1. マネージャ -> インターコネクト -> サブオーディネート 2 つ
  //---------------------------------------------------------------------------
  ahb_smp_top #(
    .ADDR_WIDTH ( AW )
   ,.DATA_WIDTH ( DW )
  ) u_top (
    .hclk    ( hclk    )
   ,.hresetn ( hresetn )
   ,.start   ( start   )
   ,.busy    ( busy    )
   ,.done    ( done    )
   ,.err     ( err     )
  );

  //---------------------------------------------------------------------------
  // 2. TB (clocking block) -> RTL のサブオーディネート (直接つなぐ)
  //---------------------------------------------------------------------------
  ahb_if #(
    .ADDR_WIDTH ( AW   )
   ,.DATA_WIDTH ( DW   )
   ,.DIRECT     ( 1'b1 )
   ,.TB_ROLE    ( 1    )   // TB がマネージャの信号を mgr_cb で駆動する
  ) u_tb_ahb (
    .hclk    ( hclk    )
   ,.hresetn ( hresetn )
  );

  ahb_smp_mem #(
    .DATA_WIDTH ( DW )
   ,.WAIT       ( 2  )
  ) u_mem2 (
    .hclk    ( hclk     )
   ,.hresetn ( hresetn  )
   ,.s_ahb   ( u_tb_ahb )
  );

  virtual ahb_if #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW)).mon_tb vmon;
  virtual ahb_if #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW), .TB_ROLE(1)).mgr_tb vmgr;

  int unsigned n_xfer;
  int unsigned n_err;

  // TB のマネージャが流す転送
  typedef struct packed {
    logic [1:0]    trans;
    logic [2:0]    burst;
    logic          write;
    logic [2:0]    size;
    logic [AW-1:0] addr;
    logic [DW-1:0] data;    // 書き込みデータ / 読み出しの期待値 (バイトレーンに置いた値)
  } xfer_t;

  function automatic xfer_t xf(input logic [1:0] trans, input logic [2:0] burst, input logic write, input logic [2:0] size, input logic [AW-1:0] addr, input logic [DW-1:0] data);
    xfer_t x;
    x.trans = trans;
    x.burst = burst;
    x.write = write;
    x.size  = size;
    x.addr  = addr;
    x.data  = data;
    return x;
  endfunction

  task automatic fail(input string msg);
    $display("TB FAIL : %s", msg);
    $fatal(1, "tb_ahb_smp failed");
  endtask

  // 1. のマネージャ側のリンクを mon_cb で観測する
  task automatic monitor();
    forever begin
      @(vmon.mon_cb);
      if( vmon.mon_cb.hready&&vmon.mon_cb.htrans[1] ) begin
        n_xfer++;
      end
      if( vmon.mon_cb.hready&&vmon.mon_cb.hresp ) begin
        n_err++;
      end
    end
  endtask

  function automatic logic [DW/8-1:0] lanes(input logic [2:0] size, input logic [1:0] a);
    case( size )
      3'd0 : begin
        return 4'b0001<<a;
      end
      3'd1 : begin
        return a[1] ? 4'b1100 : 4'b0011;
      end
      default : begin
        return 4'b1111;
      end
    endcase
  endfunction

  task automatic tb_drive_ap(input xfer_t x);
    vmgr.mgr_cb.htrans <= x.trans;
    vmgr.mgr_cb.haddr  <= x.addr;
    vmgr.mgr_cb.hwrite <= x.write;
    vmgr.mgr_cb.hsize  <= x.size;
    vmgr.mgr_cb.hburst <= x.burst;
    vmgr.mgr_cb.hprot  <= 4'b0011;
  endtask

  // 転送の列をパイプラインで流す (アドレスフェーズは HREADY=1 のエッジで次へ進む)。
  // 読み出しはデータフェーズの終わりに HRDATA を照合する。
  // inject=1 なら、待ちの間に出している NONSEQ / SEQ の HADDR を 1 回変える (プロトコル違反)
  task automatic tb_run(input xfer_t q [$], input bit inject);
    int ai;
    int di;
    bit injected;
    ai       = 0;
    di       = -1;
    injected = 1'b0;
    tb_drive_ap(q[0]);
    while( (ai<q.size())||(di>=0) ) begin
      @(vmgr.mgr_cb);
      if( vmgr.mgr_cb.hready ) begin
        // データフェーズの転送が終わった
        if( (di>=0)&&q[di].trans[1] ) begin
          if( vmgr.mgr_cb.hresp ) begin
            fail($sformatf("ERROR response at %0h", q[di].addr));
          end
          if( !q[di].write&&(vmgr.mgr_cb.hrdata!=q[di].data) ) begin
            fail($sformatf("read %0h : HRDATA %0h, expected %0h", q[di].addr, vmgr.mgr_cb.hrdata, q[di].data));
          end
        end
        // アドレスフェーズの転送を受け付けた
        if( ai<q.size() ) begin
          di = ai;
          ai++;
        end else begin
          di = -1;
        end
        if( ai<q.size() ) begin
          tb_drive_ap(q[ai]);
        end else begin
          vmgr.mgr_cb.htrans <= IDLE;
        end
        if( (di>=0)&&q[di].write&&q[di].trans[1] ) begin
          vmgr.mgr_cb.hwdata <= q[di].data;
          vmgr.mgr_cb.hwstrb <= lanes(q[di].size, q[di].addr[1:0]);
        end else begin
          vmgr.mgr_cb.hwstrb <= '0;
        end
      end else if( inject&&!injected&&(ai<q.size())&&q[ai].trans[1] ) begin
        vmgr.mgr_cb.haddr <= q[ai].addr^AW'('h100);
        injected = 1'b1;
      end
    end
  endtask

  xfer_t q [$];

  initial begin
    bad     = $test$plusargs("BAD");
    vmon    = u_top.u_m;
    vmgr    = u_tb_ahb;
    hresetn = 1'b0;
    start   = 1'b0;
    repeat( 5 ) begin
      @(posedge hclk);
    end
    #1;
    hresetn = 1'b1;
    fork
      monitor();
    join_none

    //-------------------------------------------------------------------------
    // 1. RTL 同士
    //-------------------------------------------------------------------------
    @(posedge hclk);
    #1;
    start = 1'b1;
    @(posedge hclk);
    #1;
    start = 1'b0;
    for( int n=0; !done; n++ ) begin
      if( n>2000 ) begin
        fail("part 1 : timeout");
      end
      @(posedge hclk);
    end
    @(posedge hclk);
    if( err ) begin
      fail("part 1 : ahb_smp_mgr reported an error");
    end
    if( (n_xfer!=17)||(n_err!=1) ) begin
      fail($sformatf("part 1 : %0d transfers, %0d ERROR responses", n_xfer, n_err));
    end
    $display("part 1 : OK (%0d transfers, %0d ERROR response from the default subordinate)", n_xfer, n_err);

    //-------------------------------------------------------------------------
    // 2. TB マネージャ
    //-------------------------------------------------------------------------
    @(vmgr.mgr_cb);
    q.delete();
    q.push_back(xf(NONSEQ, INCR4, 1'b1, 3'd2, 32'h40, 32'hA000_0000));
    q.push_back(xf(SEQ, INCR4, 1'b1, 3'd2, 32'h44, 32'hA111_1111));
    q.push_back(xf(BUSY, INCR4, 1'b1, 3'd2, 32'h48, 32'h0));
    q.push_back(xf(SEQ, INCR4, 1'b1, 3'd2, 32'h48, 32'hA222_2222));
    q.push_back(xf(SEQ, INCR4, 1'b1, 3'd2, 32'h4C, 32'hA333_3333));
    q.push_back(xf(NONSEQ, INCR4, 1'b0, 3'd2, 32'h40, 32'hA000_0000));
    q.push_back(xf(SEQ, INCR4, 1'b0, 3'd2, 32'h44, 32'hA111_1111));
    q.push_back(xf(SEQ, INCR4, 1'b0, 3'd2, 32'h48, 32'hA222_2222));
    q.push_back(xf(SEQ, INCR4, 1'b0, 3'd2, 32'h4C, 32'hA333_3333));
    q.push_back(xf(NONSEQ, SINGLE, 1'b1, 3'd0, 32'h41, 32'h0000_A500));
    q.push_back(xf(NONSEQ, WRAP4, 1'b0, 3'd2, 32'h48, 32'hA222_2222));
    q.push_back(xf(SEQ, WRAP4, 1'b0, 3'd2, 32'h4C, 32'hA333_3333));
    q.push_back(xf(SEQ, WRAP4, 1'b0, 3'd2, 32'h40, 32'hA000_A500));
    q.push_back(xf(SEQ, WRAP4, 1'b0, 3'd2, 32'h44, 32'hA111_1111));
    tb_run(q, bad);
    $display("part 2 : OK (INCR4 with BUSY / INCR4 / WRAP4 / byte write, wait states)");

    if( bad ) begin
      fail("+BAD : the protocol violation was not detected");
    end
    repeat( 5 ) begin
      @(posedge hclk);
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
