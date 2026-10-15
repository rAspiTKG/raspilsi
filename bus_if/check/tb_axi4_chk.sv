//=============================================================================
// tb_axi4_chk.sv
//-----------------------------------------------------------------------------
//  axi4_if のプロトコルチェックの自己テスト。TB が両側 (TB_ROLE=3) を clocking block で駆動する。
//    +SCN=0      : 正しいトランザクションだけ (エラーが出ないこと)
//    +SCN=1〜31  : 違反を 1 つ入れる (最初に「EXPECT: <メッセージ>」を表示し、そのエラーが出ること)
//  Makefile の chk ターゲットが全ての SCN を流して確かめる。
//=============================================================================
`timescale 1ns / 1ps

module tb_axi4_chk;

  localparam int unsigned AW = 32;
  localparam int unsigned DW = 64;
  localparam int unsigned IW = 4;

  localparam logic [1:0] FIXED  = 2'b00;
  localparam logic [1:0] INCR   = 2'b01;
  localparam logic [1:0] WRAP   = 2'b10;
  localparam logic [1:0] OKAY   = 2'b00;
  localparam logic [1:0] EXOKAY = 2'b01;

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

  axi4_if #(
    .ADDR_WIDTH ( AW )
   ,.DATA_WIDTH ( DW )
   ,.ID_WIDTH   ( IW )
   ,.TB_ROLE    ( 3  )   // TB が両側を駆動する
  ) u_axi (
    .aclk    ( aclk    )
   ,.aresetn ( aresetn )
  );

  virtual axi4_if #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW), .ID_WIDTH(IW), .TB_ROLE(3)).mgr_tb vm;
  virtual axi4_if #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW), .ID_WIDTH(IW), .TB_ROLE(3)).sub_tb vs;

  //---------------------------------------------------------------------------
  // マネージャ側
  //---------------------------------------------------------------------------
  task automatic aw(input logic [IW-1:0] id, input logic [AW-1:0] addr, input logic [7:0] len, input logic [2:0] size, input logic [1:0] burst, input logic lock);
    vm.mgr_cb.awid    <= id;
    vm.mgr_cb.awaddr  <= addr;
    vm.mgr_cb.awlen   <= len;
    vm.mgr_cb.awsize  <= size;
    vm.mgr_cb.awburst <= burst;
    vm.mgr_cb.awlock  <= lock;
    vm.mgr_cb.awvalid <= 1'b1;
    do begin
      @(vm.mgr_cb);
    end while( !vm.mgr_cb.awready );
    vm.mgr_cb.awvalid <= 1'b0;
  endtask

  task automatic w(input logic [DW-1:0] d, input logic last);
    vm.mgr_cb.wdata  <= d;
    vm.mgr_cb.wstrb  <= '1;
    vm.mgr_cb.wlast  <= last;
    vm.mgr_cb.wvalid <= 1'b1;
    do begin
      @(vm.mgr_cb);
    end while( !vm.mgr_cb.wready );
    vm.mgr_cb.wvalid <= 1'b0;
  endtask

  // n ビートの W (最後のビートで WLAST)
  task automatic wn(input int unsigned n);
    for( int i=0; i<n; i++ ) begin
      w(DW'(i), (i==n-1));
    end
  endtask

  task automatic ar(input logic [IW-1:0] id, input logic [AW-1:0] addr, input logic [7:0] len, input logic [2:0] size, input logic [1:0] burst, input logic lock);
    vm.mgr_cb.arid    <= id;
    vm.mgr_cb.araddr  <= addr;
    vm.mgr_cb.arlen   <= len;
    vm.mgr_cb.arsize  <= size;
    vm.mgr_cb.arburst <= burst;
    vm.mgr_cb.arlock  <= lock;
    vm.mgr_cb.arvalid <= 1'b1;
    do begin
      @(vm.mgr_cb);
    end while( !vm.mgr_cb.arready );
    vm.mgr_cb.arvalid <= 1'b0;
  endtask

  //---------------------------------------------------------------------------
  // サブオーディネート側
  //---------------------------------------------------------------------------
  task automatic b(input logic [IW-1:0] id, input logic [1:0] resp);
    vs.sub_cb.bid    <= id;
    vs.sub_cb.bresp  <= resp;
    vs.sub_cb.bvalid <= 1'b1;
    do begin
      @(vs.sub_cb);
    end while( !vs.sub_cb.bready );
    vs.sub_cb.bvalid <= 1'b0;
  endtask

  task automatic r(input logic [IW-1:0] id, input logic [1:0] resp, input logic last);
    vs.sub_cb.rid    <= id;
    vs.sub_cb.rdata  <= '0;
    vs.sub_cb.rresp  <= resp;
    vs.sub_cb.rlast  <= last;
    vs.sub_cb.rvalid <= 1'b1;
    do begin
      @(vs.sub_cb);
    end while( !vs.sub_cb.rready );
    vs.sub_cb.rvalid <= 1'b0;
  endtask

  // n ビートの R (最後のビートで RLAST)
  task automatic rn(input logic [IW-1:0] id, input int unsigned n);
    for( int i=0; i<n; i++ ) begin
      r(id, OKAY, (i==n-1));
    end
  endtask

  task automatic cyc(input int unsigned n);
    repeat( n ) begin
      @(vm.mgr_cb);
    end
  endtask

  task automatic expect_err(input string msg);
    $display("EXPECT: %s", msg);
  endtask

  //---------------------------------------------------------------------------
  // 正しいトランザクション (SCN=0)
  //---------------------------------------------------------------------------
  task automatic legal();
    // INCR 4 ビート
    aw(4'd1, 32'h100, 8'd3, 3'd3, INCR, 1'b0);
    wn(4);
    b(4'd1, OKAY);
    // W が AW より先
    wn(2);
    aw(4'd2, 32'h200, 8'd1, 3'd3, INCR, 1'b0);
    b(4'd2, OKAY);
    // 2 つの書き込みの B を逆の順に返す (ID が違えばよい)
    aw(4'd3, 32'h300, 8'd0, 3'd3, INCR, 1'b0);
    wn(1);
    aw(4'd4, 32'h308, 8'd0, 3'd3, INCR, 1'b0);
    wn(1);
    b(4'd4, OKAY);
    b(4'd3, OKAY);
    // 2 つの読み出しの R を混ぜて返す (ID が違えばよい)
    ar(4'd5, 32'h100, 8'd3, 3'd3, INCR, 1'b0);
    ar(4'd6, 32'h200, 8'd1, 3'd3, INCR, 1'b0);
    r(4'd6, OKAY, 1'b0);
    r(4'd5, OKAY, 1'b0);
    r(4'd6, OKAY, 1'b1);
    rn(4'd5, 3);
    // WRAP / FIXED / 狭い転送 / 4KB 境界の直前で終わる INCR 256 ビート
    aw(4'd1, 32'h130, 8'd3, 3'd3, WRAP, 1'b0);
    wn(4);
    b(4'd1, OKAY);
    ar(4'd1, 32'h400, 8'd15, 3'd2, FIXED, 1'b0);
    rn(4'd1, 16);
    ar(4'd1, 32'hF00, 8'd255, 3'd0, INCR, 1'b0);
    rn(4'd1, 256);
    // 排他アクセス (EXOKAY)
    ar(4'd7, 32'h180, 8'd1, 3'd3, INCR, 1'b1);
    r(4'd7, EXOKAY, 1'b0);
    r(4'd7, EXOKAY, 1'b1);
    aw(4'd7, 32'h180, 8'd1, 3'd3, INCR, 1'b1);
    wn(2);
    b(4'd7, EXOKAY);
    // 書き込みの途中でリセット (チェックの状態も消える)
    aw(4'd8, 32'h500, 8'd3, 3'd3, INCR, 1'b0);
    w(DW'(0), 1'b0);
    aresetn = 1'b0;
    cyc(2);
    #1;
    aresetn = 1'b1;
    cyc(1);
    aw(4'd8, 32'h500, 8'd0, 3'd3, INCR, 1'b0);
    wn(1);
    b(4'd8, OKAY);
  endtask

  //---------------------------------------------------------------------------
  // 違反 (SCN=1〜)
  //---------------------------------------------------------------------------
  task automatic violation(input int n);
    case( n )
      1 : begin
        expect_err("AWVALID dropped or AW changed before AWREADY");
        vs.sub_cb.awready <= 1'b0;
        vm.mgr_cb.awvalid <= 1'b1;
        cyc(1);
        vm.mgr_cb.awvalid <= 1'b0;
        cyc(2);
      end
      2 : begin
        expect_err("WVALID dropped or W changed before WREADY");
        vs.sub_cb.wready <= 1'b0;
        vm.mgr_cb.wdata  <= DW'(1);
        vm.mgr_cb.wvalid <= 1'b1;
        cyc(1);
        vm.mgr_cb.wdata <= DW'(2);
        cyc(2);
      end
      3 : begin
        expect_err("BVALID dropped or B changed before BREADY");
        aw(4'd1, 32'h100, 8'd0, 3'd3, INCR, 1'b0);
        wn(1);
        vm.mgr_cb.bready <= 1'b0;
        vs.sub_cb.bid    <= 4'd1;
        vs.sub_cb.bvalid <= 1'b1;
        cyc(1);
        vs.sub_cb.bvalid <= 1'b0;
        cyc(2);
      end
      4 : begin
        expect_err("ARVALID dropped or AR changed before ARREADY");
        vs.sub_cb.arready <= 1'b0;
        vm.mgr_cb.araddr  <= 32'h100;
        vm.mgr_cb.arvalid <= 1'b1;
        cyc(1);
        vm.mgr_cb.araddr <= 32'h108;
        cyc(2);
      end
      5 : begin
        expect_err("RVALID dropped or R changed before RREADY");
        ar(4'd1, 32'h100, 8'd1, 3'd3, INCR, 1'b0);
        vm.mgr_cb.rready <= 1'b0;
        vs.sub_cb.rid    <= 4'd1;
        vs.sub_cb.rvalid <= 1'b1;
        cyc(1);
        vs.sub_cb.rvalid <= 1'b0;
        cyc(2);
      end
      6 : begin
        expect_err("AWVALID / WVALID / ARVALID must be LOW during reset");
        vs.sub_cb.awready <= 1'b0;
        vm.mgr_cb.awvalid <= 1'b1;
        cyc(1);
        aresetn = 1'b0;
        cyc(2);
      end
      7 : begin
        expect_err("BVALID / RVALID must be LOW during reset");
        aw(4'd1, 32'h100, 8'd0, 3'd3, INCR, 1'b0);
        wn(1);
        vm.mgr_cb.bready <= 1'b0;
        vs.sub_cb.bid    <= 4'd1;
        vs.sub_cb.bvalid <= 1'b1;
        cyc(1);
        aresetn = 1'b0;
        cyc(2);
      end
      8 : begin
        expect_err("VALID HIGH at the first edge after reset");
        aresetn = 1'b0;
        cyc(2);
        // リセット中のエッジの直後に ARVALID を上げ、その 1ns 後にリセットを解除する
        vm.mgr_cb.arvalid <= 1'b1;
        #1;
        aresetn = 1'b1;
        cyc(2);
      end
      9 : begin
        expect_err("AWBURST is reserved");
        aw(4'd1, 32'h100, 8'd0, 3'd3, 2'b11, 1'b0);
      end
      10 : begin
        expect_err("AWSIZE exceeds the data bus width");
        aw(4'd1, 32'h100, 8'd0, 3'd4, INCR, 1'b0);
      end
      11 : begin
        expect_err("WRAP write burst must be 2/4/8/16 beats");
        aw(4'd1, 32'h100, 8'd2, 3'd3, WRAP, 1'b0);
      end
      12 : begin
        expect_err("FIXED write burst longer than 16 beats");
        aw(4'd1, 32'h100, 8'd16, 3'd3, FIXED, 1'b0);
      end
      13 : begin
        expect_err("INCR write burst crosses a 4KB boundary");
        aw(4'd1, 32'hFF8, 8'd1, 3'd3, INCR, 1'b0);
      end
      14 : begin
        expect_err("exclusive write violates the exclusive access restrictions");
        aw(4'd1, 32'h100, 8'd2, 3'd3, INCR, 1'b1);
      end
      15 : begin
        expect_err("ARBURST is reserved");
        ar(4'd1, 32'h100, 8'd0, 3'd3, 2'b11, 1'b0);
      end
      16 : begin
        expect_err("ARSIZE exceeds the data bus width");
        ar(4'd1, 32'h100, 8'd0, 3'd7, INCR, 1'b0);
      end
      17 : begin
        expect_err("WRAP read burst must be 2/4/8/16 beats");
        ar(4'd1, 32'h104, 8'd3, 3'd3, WRAP, 1'b0);
      end
      18 : begin
        expect_err("FIXED read burst longer than 16 beats");
        ar(4'd1, 32'h100, 8'd31, 3'd3, FIXED, 1'b0);
      end
      19 : begin
        expect_err("INCR read burst crosses a 4KB boundary");
        ar(4'd1, 32'h1F01, 8'd255, 3'd0, INCR, 1'b0);
      end
      20 : begin
        expect_err("exclusive read violates the exclusive access restrictions");
        ar(4'd1, 32'h108, 8'd1, 3'd3, INCR, 1'b1);
      end
      21 : begin
        expect_err("WLAST=1 at beat 2 of AWLEN+1=4");
        aw(4'd1, 32'h100, 8'd3, 3'd3, INCR, 1'b0);
        wn(2);
      end
      22 : begin
        expect_err("WLAST=0 at beat 4 of AWLEN+1=4");
        aw(4'd1, 32'h100, 8'd3, 3'd3, INCR, 1'b0);
        for( int i=0; i<4; i++ ) begin
          w(DW'(i), 1'b0);
        end
      end
      23 : begin
        expect_err("WLAST at beat 2 but AWLEN+1=4");
        wn(2);
        aw(4'd1, 32'h100, 8'd3, 3'd3, INCR, 1'b0);
      end
      24 : begin
        expect_err("W beats without WLAST but AWLEN+1=2");
        for( int i=0; i<3; i++ ) begin
          w(DW'(i), 1'b0);
        end
        aw(4'd1, 32'h100, 8'd1, 3'd3, INCR, 1'b0);
      end
      25 : begin
        expect_err("BVALID without a completed write");
        aw(4'd1, 32'h100, 8'd1, 3'd3, INCR, 1'b0);
        w(DW'(0), 1'b0);
        b(4'd1, OKAY);
      end
      26 : begin
        expect_err("BVALID without a completed write (AW and the last W) for BID=2");
        aw(4'd1, 32'h100, 8'd0, 3'd3, INCR, 1'b0);
        wn(1);
        b(4'd2, OKAY);
      end
      27 : begin
        expect_err("RVALID without an outstanding read for RID=3");
        ar(4'd1, 32'h100, 8'd0, 3'd3, INCR, 1'b0);
        r(4'd3, OKAY, 1'b1);
      end
      28 : begin
        expect_err("RLAST=1 at beat 1 of ARLEN+1=2");
        ar(4'd1, 32'h100, 8'd1, 3'd3, INCR, 1'b0);
        r(4'd1, OKAY, 1'b1);
      end
      29 : begin
        expect_err("RLAST=0 at beat 2 of ARLEN+1=2");
        ar(4'd1, 32'h100, 8'd1, 3'd3, INCR, 1'b0);
        r(4'd1, OKAY, 1'b0);
        r(4'd1, OKAY, 1'b0);
      end
      30 : begin
        expect_err("EXOKAY for a write that is not exclusive");
        aw(4'd1, 32'h100, 8'd0, 3'd3, INCR, 1'b0);
        wn(1);
        b(4'd1, EXOKAY);
      end
      31 : begin
        expect_err("EXOKAY for a read that is not exclusive");
        ar(4'd1, 32'h100, 8'd0, 3'd3, INCR, 1'b0);
        r(4'd1, EXOKAY, 1'b1);
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
