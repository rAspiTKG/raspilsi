//=============================================================================
// tb_axil_chk.sv
//-----------------------------------------------------------------------------
//  axil_if のプロトコルチェックの自己テスト。TB が両側 (TB_ROLE=3) を clocking block で駆動する。
//    +SCN=0      : 正しいトランザクションだけ (エラーが出ないこと)
//    +SCN=1〜12  : 違反を 1 つ入れる (最初に「EXPECT: <メッセージ>」を表示し、そのエラーが出ること)
//=============================================================================
`timescale 1ns / 1ps

module tb_axil_chk;

  localparam int unsigned AW = 32;
  localparam int unsigned DW = 32;

  localparam logic [1:0] OKAY   = 2'b00;
  localparam logic [1:0] EXOKAY = 2'b01;
  localparam logic [1:0] SLVERR = 2'b10;

  logic aclk;
  logic aresetn;
  int   scn;

  initial begin
    aclk = 1'b0;
    forever begin
      #5;
      aclk = ~aclk;
    end
  end

  axil_if #(
    .ADDR_WIDTH ( AW )
   ,.DATA_WIDTH ( DW )
   ,.TB_ROLE    ( 3  )   // TB が両側を駆動する
  ) u_axi (
    .aclk    ( aclk    )
   ,.aresetn ( aresetn )
  );

  virtual axil_if #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW), .TB_ROLE(3)).mgr_tb vm;
  virtual axil_if #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW), .TB_ROLE(3)).sub_tb vs;

  task automatic aw(input logic [AW-1:0] addr);
    vm.mgr_cb.awaddr  <= addr;
    vm.mgr_cb.awvalid <= 1'b1;
    do begin
      @(vm.mgr_cb);
    end while( !vm.mgr_cb.awready );
    vm.mgr_cb.awvalid <= 1'b0;
  endtask

  task automatic w(input logic [DW-1:0] d);
    vm.mgr_cb.wdata  <= d;
    vm.mgr_cb.wstrb  <= '1;
    vm.mgr_cb.wvalid <= 1'b1;
    do begin
      @(vm.mgr_cb);
    end while( !vm.mgr_cb.wready );
    vm.mgr_cb.wvalid <= 1'b0;
  endtask

  task automatic ar(input logic [AW-1:0] addr);
    vm.mgr_cb.araddr  <= addr;
    vm.mgr_cb.arvalid <= 1'b1;
    do begin
      @(vm.mgr_cb);
    end while( !vm.mgr_cb.arready );
    vm.mgr_cb.arvalid <= 1'b0;
  endtask

  task automatic b(input logic [1:0] resp);
    vs.sub_cb.bresp  <= resp;
    vs.sub_cb.bvalid <= 1'b1;
    do begin
      @(vs.sub_cb);
    end while( !vs.sub_cb.bready );
    vs.sub_cb.bvalid <= 1'b0;
  endtask

  task automatic r(input logic [1:0] resp);
    vs.sub_cb.rdata  <= '0;
    vs.sub_cb.rresp  <= resp;
    vs.sub_cb.rvalid <= 1'b1;
    do begin
      @(vs.sub_cb);
    end while( !vs.sub_cb.rready );
    vs.sub_cb.rvalid <= 1'b0;
  endtask

  task automatic cyc(input int unsigned n);
    repeat( n ) begin
      @(vm.mgr_cb);
    end
  endtask

  task automatic expect_err(input string msg);
    $display("EXPECT: %s", msg);
  endtask

  // 正しいトランザクション (SCN=0)
  task automatic legal();
    aw(32'h0);
    w(32'h1);
    b(OKAY);
    // W が AW より先
    w(32'h2);
    aw(32'h4);
    b(OKAY);
    // 2 つの書き込みを出してから B を 2 つ返す
    aw(32'h8);
    w(32'h3);
    aw(32'hC);
    w(32'h4);
    b(OKAY);
    b(SLVERR);
    // 読み出し 2 つ
    ar(32'h0);
    ar(32'h4);
    r(OKAY);
    r(SLVERR);
  endtask

  task automatic violation(input int n);
    case( n )
      1 : begin
        expect_err("AWVALID dropped or AW changed before AWREADY");
        vs.sub_cb.awready <= 1'b0;
        vm.mgr_cb.awaddr  <= 32'h0;
        vm.mgr_cb.awvalid <= 1'b1;
        cyc(1);
        vm.mgr_cb.awaddr <= 32'h4;
        cyc(2);
      end
      2 : begin
        expect_err("WVALID dropped or W changed before WREADY");
        vs.sub_cb.wready <= 1'b0;
        vm.mgr_cb.wvalid <= 1'b1;
        cyc(1);
        vm.mgr_cb.wvalid <= 1'b0;
        cyc(2);
      end
      3 : begin
        expect_err("BVALID dropped or BRESP changed before BREADY");
        aw(32'h0);
        w(32'h1);
        vm.mgr_cb.bready <= 1'b0;
        vs.sub_cb.bresp  <= OKAY;
        vs.sub_cb.bvalid <= 1'b1;
        cyc(1);
        vs.sub_cb.bresp <= SLVERR;
        cyc(2);
      end
      4 : begin
        expect_err("ARVALID dropped or AR changed before ARREADY");
        vs.sub_cb.arready <= 1'b0;
        vm.mgr_cb.arvalid <= 1'b1;
        cyc(1);
        vm.mgr_cb.arvalid <= 1'b0;
        cyc(2);
      end
      5 : begin
        expect_err("RVALID dropped or R changed before RREADY");
        ar(32'h0);
        vm.mgr_cb.rready <= 1'b0;
        vs.sub_cb.rdata  <= 32'h1;
        vs.sub_cb.rvalid <= 1'b1;
        cyc(1);
        vs.sub_cb.rdata <= 32'h2;
        cyc(2);
      end
      6 : begin
        expect_err("AWVALID / WVALID / ARVALID must be LOW during reset");
        vs.sub_cb.wready <= 1'b0;
        vm.mgr_cb.wvalid <= 1'b1;
        cyc(1);
        aresetn = 1'b0;
        cyc(2);
      end
      7 : begin
        expect_err("BVALID / RVALID must be LOW during reset");
        ar(32'h0);
        vm.mgr_cb.rready <= 1'b0;
        vs.sub_cb.rvalid <= 1'b1;
        cyc(1);
        aresetn = 1'b0;
        cyc(2);
      end
      8 : begin
        expect_err("VALID HIGH at the first edge after reset");
        aresetn = 1'b0;
        cyc(2);
        vm.mgr_cb.awvalid <= 1'b1;
        #1;
        aresetn = 1'b1;
        cyc(2);
      end
      9 : begin
        expect_err("EXOKAY on BRESP");
        aw(32'h0);
        w(32'h1);
        b(EXOKAY);
      end
      10 : begin
        expect_err("EXOKAY on RRESP");
        ar(32'h0);
        r(EXOKAY);
      end
      11 : begin
        expect_err("BVALID without a completed write (AW and W)");
        aw(32'h0);
        b(OKAY);
      end
      12 : begin
        expect_err("RVALID without an outstanding read");
        r(OKAY);
      end
      default : begin
        $display("unknown SCN");
      end
    endcase
    cyc(3);
  endtask

  initial begin
    if( !$value$plusargs("SCN=%d",scn) ) begin
      scn = 0;
    end
    vm      = u_axi;
    vs      = u_axi;
    aresetn = 1'b0;
    repeat( 3 ) begin
      @(posedge aclk);
    end
    #1;
    aresetn = 1'b1;
    @(vm.mgr_cb);
    vm.mgr_cb.bready  <= 1'b1;
    vm.mgr_cb.rready  <= 1'b1;
    vs.sub_cb.awready <= 1'b1;
    vs.sub_cb.wready  <= 1'b1;
    vs.sub_cb.arready <= 1'b1;
    @(vm.mgr_cb);
    if( scn==0 ) begin
      legal();
      cyc(3);
      $display("CHK PASS : no error on legal traffic");
    end else begin
      violation(scn);
      $display("CHK FAIL : the violation was not detected");
    end
    $finish;
  end

endmodule
