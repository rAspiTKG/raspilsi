//=============================================================================
// tb_ahb_chk.sv
//-----------------------------------------------------------------------------
//  ahb_if のプロトコルチェックの自己テスト。TB が両側 (TB_ROLE=3、DIRECT=1) を clocking block で駆動する。
//  cy() 1 回 = 1 サイクルで、マネージャのアドレスフェーズ / HWDATA と、サブオーディネートの
//  HREADYOUT / HRESP をサイクル単位で決める (DIRECT=1 なので HREADY=HREADYOUT)。
//    +SCN=0      : 正しい転送だけ (エラーが出ないこと)
//    +SCN=1〜18  : 違反を 1 つ入れる (最初に「EXPECT: <メッセージ>」を表示し、そのエラーが出ること)
//=============================================================================
`timescale 1ns / 1ps

module tb_ahb_chk;

  localparam int unsigned AW = 32;
  localparam int unsigned DW = 32;

  localparam logic [1:0] IDLE   = 2'b00;
  localparam logic [1:0] BUSY   = 2'b01;
  localparam logic [1:0] NONSEQ = 2'b10;
  localparam logic [1:0] SEQ    = 2'b11;
  localparam logic [2:0] SINGLE = 3'b000;
  localparam logic [2:0] INCR   = 3'b001;
  localparam logic [2:0] INCR4  = 3'b011;
  localparam logic [2:0] WRAP8  = 3'b100;

  logic hclk;
  logic hresetn;
  int   scn;

  initial begin
    hclk = 1'b0;
    forever begin
      #5;
      hclk = ~hclk;
    end
  end

  ahb_if #(
    .ADDR_WIDTH ( AW   )
   ,.DATA_WIDTH ( DW   )
   ,.DIRECT     ( 1'b1 )
   ,.TB_ROLE    ( 3    )   // TB が両側を駆動する
  ) u_ahb (
    .hclk    ( hclk    )
   ,.hresetn ( hresetn )
  );

  virtual ahb_if #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW), .TB_ROLE(3)).mgr_tb vm;
  virtual ahb_if #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW), .TB_ROLE(3)).sub_tb vs;

  // 1 サイクル分の値を出して、次のエッジまで進む
  //   tr / a / bu / sz / wr : アドレスフェーズ、wd : HWDATA、rdy / rsp : サブオーディネートの応答
  task automatic cy(input logic [1:0] tr, input logic [31:0] a, input logic [2:0] bu, input logic [2:0] sz, input logic wr, input logic [31:0] wd, input logic rdy, input logic rsp);
    vm.mgr_cb.htrans    <= tr;
    vm.mgr_cb.haddr     <= a;
    vm.mgr_cb.hburst    <= bu;
    vm.mgr_cb.hsize     <= sz;
    vm.mgr_cb.hwrite    <= wr;
    vm.mgr_cb.hwdata    <= wd;
    vs.sub_cb.hreadyout <= rdy;
    vs.sub_cb.hresp     <= rsp;
    @(vm.mgr_cb);
  endtask

  task automatic idle(input int unsigned n);
    repeat( n ) begin
      cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    end
  endtask

  task automatic expect_err(input string msg);
    $display("EXPECT: %s", msg);
  endtask

  //---------------------------------------------------------------------------
  // 正しい転送 (SCN=0)
  //---------------------------------------------------------------------------
  task automatic legal();
    // INCR4 の書き込み。途中の BUSY が待ちの間に SEQ に変わる
    cy(NONSEQ, 32'h40, INCR4, 3'd2, 1'b1, 32'h0, 1'b1, 1'b0);
    cy(SEQ, 32'h44, INCR4, 3'd2, 1'b1, 32'hD0, 1'b1, 1'b0);
    cy(BUSY, 32'h48, INCR4, 3'd2, 1'b1, 32'hD1, 1'b0, 1'b0);
    cy(SEQ, 32'h48, INCR4, 3'd2, 1'b1, 32'hD1, 1'b1, 1'b0);
    cy(SEQ, 32'h4C, INCR4, 3'd2, 1'b1, 32'hD2, 1'b1, 1'b0);
    cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'hD3, 1'b1, 1'b0);
    // WRAP8 の読み出し (0x58 から : 0x40〜0x5F で折り返す)
    cy(NONSEQ, 32'h58, WRAP8, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    cy(SEQ, 32'h5C, WRAP8, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    cy(SEQ, 32'h40, WRAP8, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    cy(SEQ, 32'h44, WRAP8, 3'd2, 1'b0, 32'h0, 1'b0, 1'b0);
    cy(SEQ, 32'h44, WRAP8, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    cy(SEQ, 32'h48, WRAP8, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    cy(SEQ, 32'h4C, WRAP8, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    cy(SEQ, 32'h50, WRAP8, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    cy(SEQ, 32'h54, WRAP8, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    // 長さ未定義の INCR。最後を BUSY にして IDLE で終える
    cy(NONSEQ, 32'h80, INCR, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    cy(SEQ, 32'h84, INCR, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    cy(BUSY, 32'h88, INCR, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    // 待ちの間に IDLE から NONSEQ に変える
    cy(NONSEQ, 32'h100, SINGLE, 3'd2, 1'b1, 32'h0, 1'b1, 1'b0);
    cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'hAA, 1'b0, 1'b0);
    cy(NONSEQ, 32'h104, SINGLE, 3'd2, 1'b0, 32'hAA, 1'b0, 1'b0);
    cy(NONSEQ, 32'h104, SINGLE, 3'd2, 1'b0, 32'hAA, 1'b1, 1'b0);
    cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    // INCR4 の 1 ビート目に ERROR。マネージャは残りを取り消す (ERROR の間に IDLE にする)
    cy(NONSEQ, 32'h200, INCR4, 3'd2, 1'b1, 32'h0, 1'b1, 1'b0);
    cy(SEQ, 32'h204, INCR4, 3'd2, 1'b1, 32'hE0, 1'b0, 1'b1);
    cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'hE0, 1'b1, 1'b1);
    cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    // INCR4 の 1 ビート目に ERROR。マネージャはそのまま続ける
    cy(NONSEQ, 32'h300, INCR4, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    cy(SEQ, 32'h304, INCR4, 3'd2, 1'b0, 32'h0, 1'b0, 1'b1);
    cy(SEQ, 32'h304, INCR4, 3'd2, 1'b0, 32'h0, 1'b1, 1'b1);
    cy(SEQ, 32'h308, INCR4, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    cy(SEQ, 32'h30C, INCR4, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
    // バイト / ハーフワード
    cy(NONSEQ, 32'h401, SINGLE, 3'd0, 1'b1, 32'h0, 1'b1, 1'b0);
    cy(NONSEQ, 32'h402, SINGLE, 3'd1, 1'b1, 32'h0000_5A00, 1'b1, 1'b0);
    cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'hBEEF_0000, 1'b1, 1'b0);
    idle(2);
  endtask

  //---------------------------------------------------------------------------
  // 違反 (SCN=1〜)
  //---------------------------------------------------------------------------
  task automatic violation(input int n);
    case( n )
      1 : begin
        expect_err("address phase changed during a wait state");
        cy(NONSEQ, 32'h40, SINGLE, 3'd2, 1'b1, 32'h0, 1'b1, 1'b0);
        cy(NONSEQ, 32'h44, SINGLE, 3'd2, 1'b0, 32'h1, 1'b0, 1'b0);
        cy(NONSEQ, 32'h48, SINGLE, 3'd2, 1'b0, 32'h1, 1'b1, 1'b0);
      end
      2 : begin
        expect_err("BUSY in a fixed-length burst changed to other than SEQ during a wait state");
        cy(NONSEQ, 32'h40, INCR4, 3'd2, 1'b1, 32'h0, 1'b1, 1'b0);
        cy(BUSY, 32'h44, INCR4, 3'd2, 1'b1, 32'h1, 1'b0, 1'b0);
        cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'h1, 1'b0, 1'b0);
      end
      3 : begin
        expect_err("HWDATA / HWSTRB changed during a wait state");
        cy(NONSEQ, 32'h40, SINGLE, 3'd2, 1'b1, 32'h0, 1'b1, 1'b0);
        cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'h1, 1'b0, 1'b0);
        cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'h2, 1'b1, 1'b0);
      end
      4 : begin
        expect_err("HSIZE exceeds the data bus width");
        cy(NONSEQ, 32'h40, SINGLE, 3'd3, 1'b0, 32'h0, 1'b1, 1'b0);
      end
      5 : begin
        expect_err("HADDR is not aligned to HSIZE");
        cy(NONSEQ, 32'h42, SINGLE, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
      end
      6 : begin
        expect_err("HTRANS must be IDLE during reset");
        // NONSEQ を出したままリセットに入る
        cy(NONSEQ, 32'h40, SINGLE, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
        hresetn = 1'b0;
        @(vm.mgr_cb);
        @(vm.mgr_cb);
      end
      7 : begin
        expect_err("HREADYOUT must be HIGH during reset");
        // リセットに入ると同時に HREADYOUT を 0 にする
        cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
        hresetn = 1'b0;
        vs.sub_cb.hreadyout <= 1'b0;
        @(vm.mgr_cb);
        @(vm.mgr_cb);
      end
      8 : begin
        expect_err("IDLE / BUSY transfer did not get a zero wait state OKAY response");
        cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
        cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'h0, 1'b0, 1'b0);
      end
      9 : begin
        expect_err("second cycle of the ERROR response is missing");
        cy(NONSEQ, 32'h40, SINGLE, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
        cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'h0, 1'b0, 1'b1);
        cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
      end
      10 : begin
        expect_err("ERROR response with HREADYOUT HIGH but without the first cycle");
        cy(NONSEQ, 32'h40, SINGLE, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
        cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'h0, 1'b1, 1'b1);
      end
      11 : begin
        expect_err("fixed-length burst ended with 2 beats left");
        cy(NONSEQ, 32'h40, INCR4, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
        cy(SEQ, 32'h44, INCR4, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
        cy(IDLE, 32'h0, SINGLE, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
      end
      12 : begin
        expect_err("BUSY outside a burst");
        cy(BUSY, 32'h40, SINGLE, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
      end
      13 : begin
        expect_err("SEQ outside a burst");
        cy(SEQ, 32'h40, INCR4, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
      end
      14 : begin
        expect_err("control signals changed within a burst");
        cy(NONSEQ, 32'h40, INCR4, 3'd2, 1'b1, 32'h0, 1'b1, 1'b0);
        cy(SEQ, 32'h44, INCR4, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
      end
      15 : begin
        expect_err("is not the next address of the burst");
        cy(NONSEQ, 32'h40, INCR4, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
        cy(SEQ, 32'h48, INCR4, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
      end
      16 : begin
        expect_err("INCR burst crosses a 1KB boundary");
        cy(NONSEQ, 32'h3FC, INCR, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
        cy(SEQ, 32'h400, INCR, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
      end
      17 : begin
        expect_err("INCR4 burst crosses a 1KB boundary");
        cy(NONSEQ, 32'h3F8, INCR4, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
      end
      18 : begin
        expect_err("too many beats in a fixed-length burst");
        cy(NONSEQ, 32'h40, INCR4, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
        cy(SEQ, 32'h44, INCR4, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
        cy(SEQ, 32'h48, INCR4, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
        cy(SEQ, 32'h4C, INCR4, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
        cy(SEQ, 32'h50, INCR4, 3'd2, 1'b0, 32'h0, 1'b1, 1'b0);
      end
      default : begin
        $display("unknown SCN");
      end
    endcase
    idle(3);
  endtask

  initial begin
    if( !$value$plusargs("SCN=%d",scn) ) begin
      scn = 0;
    end
    vm      = u_ahb;
    vs      = u_ahb;
    hresetn = 1'b0;
    repeat( 3 ) begin
      @(posedge hclk);
    end
    #1;
    hresetn = 1'b1;
    @(vm.mgr_cb);
    if( scn==0 ) begin
      legal();
      $display("CHK PASS : no error on legal traffic");
    end else begin
      violation(scn);
      $display("CHK FAIL : the violation was not detected");
    end
    $finish;
  end

endmodule
