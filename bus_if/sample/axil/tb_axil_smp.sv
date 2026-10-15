//=============================================================================
// tb_axil_smp.sv
//-----------------------------------------------------------------------------
//  axil_if のサンプルの自己チェック TB。
//    1. axil_smp_top (RTL のマネージャ -> RTL のサブオーディネート) を動かし、
//       同じ axil_if を mon_cb で観測してハンドシェイクの数を確かめる
//    2. TB が mgr_cb (clocking block) でマネージャになり、axil_smp_regs を直接動かす
//       (W を AW より先に出す書き込み、WSTRB の一部だけの書き込み、存在しないレジスタへの SLVERR)
//  +BAD を付けると 2. の最初の書き込みで AWREADY を待たずに AWADDR を変える。
//  axil_if のプロトコルチェック (a_aw_hold) がエラーにすることを確かめる。
//=============================================================================
`timescale 1ns / 1ps

module tb_axil_smp;

  localparam int unsigned AW   = 32;
  localparam int unsigned DW   = 32;
  localparam int unsigned SB   = DW/8;
  localparam int unsigned NREG = 4;

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
  axil_smp_top #(
    .ADDR_WIDTH ( AW   )
   ,.DATA_WIDTH ( DW   )
   ,.NREG       ( NREG )
   ,.READY_DLY  ( 1    )
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
  axil_if #(
    .ADDR_WIDTH ( AW )
   ,.DATA_WIDTH ( DW )
   ,.TB_ROLE    ( 1  )   // TB がマネージャの信号を mgr_cb で駆動する
  ) u_tb_axi (
    .aclk    ( aclk    )
   ,.aresetn ( aresetn )
  );

  axil_smp_regs #(
    .ADDR_WIDTH ( AW   )
   ,.DATA_WIDTH ( DW   )
   ,.NREG       ( NREG )
   ,.READY_DLY  ( 2    )
  ) u_regs2 (
    .aclk    ( aclk     )
   ,.aresetn ( aresetn  )
   ,.s_axi   ( u_tb_axi )
  );

  virtual axil_if #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW)).mon_tb vmon;
  virtual axil_if #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW), .TB_ROLE(1)).mgr_tb vmgr;

  int unsigned n_aw;
  int unsigned n_w;
  int unsigned n_b;
  int unsigned n_ar;
  int unsigned n_r;

  task automatic fail(input string msg);
    $display("TB FAIL : %s", msg);
    $fatal(1, "tb_axil_smp failed");
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

  // 2. の TB マネージャ : 書き込み。w_first=1 なら W を先に出し、AW を 2 サイクル遅らせる。
  //   inject=1 なら AWREADY を待たずに AWADDR を変える (プロトコル違反)
  task automatic tb_write(input logic [AW-1:0] addr, input logic [DW-1:0] data, input logic [SB-1:0] strb, input logic [1:0] exp_resp, input bit w_first, input bit inject);
    fork
      begin
        if( w_first ) begin
          repeat( 2 ) begin
            @(vmgr.mgr_cb);
          end
        end
        vmgr.mgr_cb.awaddr  <= addr;
        vmgr.mgr_cb.awvalid <= 1'b1;
        if( inject ) begin
          @(vmgr.mgr_cb);
          vmgr.mgr_cb.awaddr <= addr+AW'(4);
        end
        do begin
          @(vmgr.mgr_cb);
        end while( !vmgr.mgr_cb.awready );
        vmgr.mgr_cb.awvalid <= 1'b0;
      end
      begin
        vmgr.mgr_cb.wdata  <= data;
        vmgr.mgr_cb.wstrb  <= strb;
        vmgr.mgr_cb.wvalid <= 1'b1;
        do begin
          @(vmgr.mgr_cb);
        end while( !vmgr.mgr_cb.wready );
        vmgr.mgr_cb.wvalid <= 1'b0;
      end
    join
    vmgr.mgr_cb.bready <= 1'b1;
    do begin
      @(vmgr.mgr_cb);
    end while( !vmgr.mgr_cb.bvalid );
    vmgr.mgr_cb.bready <= 1'b0;
    if( vmgr.mgr_cb.bresp!=exp_resp ) begin
      fail($sformatf("write %0h : BRESP=%0d, expected %0d", addr, vmgr.mgr_cb.bresp, exp_resp));
    end
  endtask

  // 2. の TB マネージャ : 読み出し
  task automatic tb_read(input logic [AW-1:0] addr, input logic [DW-1:0] exp_data, input logic [1:0] exp_resp);
    vmgr.mgr_cb.araddr  <= addr;
    vmgr.mgr_cb.arvalid <= 1'b1;
    do begin
      @(vmgr.mgr_cb);
    end while( !vmgr.mgr_cb.arready );
    vmgr.mgr_cb.arvalid <= 1'b0;
    vmgr.mgr_cb.rready  <= 1'b1;
    do begin
      @(vmgr.mgr_cb);
    end while( !vmgr.mgr_cb.rvalid );
    vmgr.mgr_cb.rready <= 1'b0;
    if( (vmgr.mgr_cb.rresp!=exp_resp)||(vmgr.mgr_cb.rdata!=exp_data) ) begin
      fail($sformatf("read %0h : RDATA=%0h RRESP=%0d, expected %0h / %0d", addr, vmgr.mgr_cb.rdata, vmgr.mgr_cb.rresp, exp_data, exp_resp));
    end
  endtask

  initial begin
    bad     = $test$plusargs("BAD");
    vmon    = u_top.u_axi;
    vmgr    = u_tb_axi;
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
      fail("part 1 : axil_smp_mgr reported an error");
    end
    if( (n_aw!=NREG)||(n_w!=NREG)||(n_b!=NREG)||(n_ar!=NREG+1)||(n_r!=NREG+1) ) begin
      fail($sformatf("part 1 : handshakes AW=%0d W=%0d B=%0d AR=%0d R=%0d", n_aw, n_w, n_b, n_ar, n_r));
    end
    $display("part 1 : OK (AW=%0d W=%0d B=%0d AR=%0d R=%0d)", n_aw, n_w, n_b, n_ar, n_r);

    //-------------------------------------------------------------------------
    // 2. TB マネージャ
    //-------------------------------------------------------------------------
    @(vmgr.mgr_cb);
    tb_write(32'h0, 32'hAABB_CCDD, 4'hF, 2'b00, 1'b0, bad);
    tb_write(32'h4, 32'h1122_3344, 4'hF, 2'b00, 1'b1, 1'b0);
    tb_write(32'h4, 32'h0000_EE00, 4'h2, 2'b00, 1'b0, 1'b0);
    tb_write(32'h40, 32'h5555_5555, 4'hF, 2'b10, 1'b0, 1'b0);
    tb_read(32'h0, 32'hAABB_CCDD, 2'b00);
    tb_read(32'h4, 32'h1122_EE44, 2'b00);
    tb_read(32'h40, 32'h0, 2'b10);
    $display("part 2 : OK (W before AW / partial WSTRB / SLVERR)");

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
