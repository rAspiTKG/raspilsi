//=============================================================================
// tb_apb_chk.sv
//-----------------------------------------------------------------------------
//  apb_if のプロトコルチェックの自己テスト。TB が両側 (TB_ROLE=3) を clocking block で駆動する。
//  cy() 1 回 = 1 サイクルで、リクエスタとコンプリータの信号をサイクル単位で決める。
//    +SCN=0     : 正しい転送だけ (エラーが出ないこと)
//    +SCN=1〜6  : 違反を 1 つ入れる (最初に「EXPECT: <メッセージ>」を表示し、そのエラーが出ること)
//=============================================================================
`timescale 1ns / 1ps

module tb_apb_chk;

  localparam int unsigned AW = 32;
  localparam int unsigned DW = 32;

  logic pclk;
  logic presetn;
  int   scn;

  initial begin
    pclk = 1'b0;
    forever begin
      #5;
      pclk = ~pclk;
    end
  end

  apb_if #(
    .ADDR_WIDTH ( AW )
   ,.DATA_WIDTH ( DW )
   ,.TB_ROLE    ( 3  )   // TB が両側を駆動する
  ) u_apb (
    .pclk    ( pclk    )
   ,.presetn ( presetn )
  );

  virtual apb_if #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW), .TB_ROLE(3)).req_tb vr;
  virtual apb_if #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW), .TB_ROLE(3)).cmp_tb vc;

  // 1 サイクル分の値を出して、次のエッジまで進む
  task automatic cy(input logic sel, input logic en, input logic [31:0] a, input logic wr, input logic [31:0] wd, input logic [3:0] st, input logic rdy, input logic err);
    vr.req_cb.psel    <= sel;
    vr.req_cb.penable <= en;
    vr.req_cb.paddr   <= a;
    vr.req_cb.pwrite  <= wr;
    vr.req_cb.pwdata  <= wd;
    vr.req_cb.pstrb   <= st;
    vc.cmp_cb.pready  <= rdy;
    vc.cmp_cb.pslverr <= err;
    vc.cmp_cb.prdata  <= '0;
    @(vr.req_cb);
  endtask

  task automatic idle(input int unsigned n);
    repeat( n ) begin
      cy(1'b0, 1'b0, 32'h0, 1'b0, 32'h0, 4'h0, 1'b1, 1'b0);
    end
  endtask

  task automatic expect_err(input string msg);
    $display("EXPECT: %s", msg);
  endtask

  // 正しい転送 (SCN=0)
  task automatic legal();
    idle(1);
    // 書き込み (待ち無し) の直後に読み出し (待ち 2)
    cy(1'b1, 1'b0, 32'h0, 1'b1, 32'h11, 4'hF, 1'b0, 1'b0);
    cy(1'b1, 1'b1, 32'h0, 1'b1, 32'h11, 4'hF, 1'b1, 1'b0);
    cy(1'b1, 1'b0, 32'h4, 1'b0, 32'h0, 4'h0, 1'b0, 1'b0);
    cy(1'b1, 1'b1, 32'h4, 1'b0, 32'h0, 4'h0, 1'b0, 1'b0);
    cy(1'b1, 1'b1, 32'h4, 1'b0, 32'h0, 4'h0, 1'b0, 1'b0);
    cy(1'b1, 1'b1, 32'h4, 1'b0, 32'h0, 4'h0, 1'b1, 1'b0);
    // PSLVERR で終わる書き込み
    cy(1'b1, 1'b0, 32'h40, 1'b1, 32'h22, 4'h3, 1'b0, 1'b0);
    cy(1'b1, 1'b1, 32'h40, 1'b1, 32'h22, 4'h3, 1'b1, 1'b1);
    idle(2);
    // 別のコンプリータの ACCESS (このリンクは PSEL=0 で PENABLE=1)
    cy(1'b0, 1'b0, 32'h1000, 1'b0, 32'h0, 4'h0, 1'b1, 1'b0);
    cy(1'b0, 1'b1, 32'h1000, 1'b0, 32'h0, 4'h0, 1'b1, 1'b0);
    // 読み出し
    cy(1'b1, 1'b0, 32'h8, 1'b0, 32'h0, 4'h0, 1'b1, 1'b0);
    cy(1'b1, 1'b1, 32'h8, 1'b0, 32'h0, 4'h0, 1'b1, 1'b0);
    idle(2);
  endtask

  task automatic violation(input int n);
    case( n )
      1 : begin
        expect_err("SETUP phase was not followed by the ACCESS phase");
        cy(1'b1, 1'b0, 32'h0, 1'b1, 32'h11, 4'hF, 1'b0, 1'b0);
        cy(1'b1, 1'b0, 32'h0, 1'b1, 32'h11, 4'hF, 1'b0, 1'b0);
      end
      2 : begin
        expect_err("changed from SETUP to ACCESS");
        cy(1'b1, 1'b0, 32'h0, 1'b1, 32'h11, 4'hF, 1'b0, 1'b0);
        cy(1'b1, 1'b1, 32'h4, 1'b1, 32'h11, 4'hF, 1'b1, 1'b0);
      end
      3 : begin
        expect_err("signals changed during a wait state of the ACCESS phase");
        cy(1'b1, 1'b0, 32'h0, 1'b1, 32'h11, 4'hF, 1'b0, 1'b0);
        cy(1'b1, 1'b1, 32'h0, 1'b1, 32'h11, 4'hF, 1'b0, 1'b0);
        cy(1'b1, 1'b1, 32'h0, 1'b1, 32'h12, 4'hF, 1'b1, 1'b0);
      end
      4 : begin
        expect_err("PENABLE was not deasserted after the transfer");
        cy(1'b1, 1'b0, 32'h0, 1'b1, 32'h11, 4'hF, 1'b0, 1'b0);
        cy(1'b1, 1'b1, 32'h0, 1'b1, 32'h11, 4'hF, 1'b1, 1'b0);
        cy(1'b1, 1'b1, 32'h4, 1'b1, 32'h11, 4'hF, 1'b1, 1'b0);
      end
      5 : begin
        expect_err("PSTRB must be LOW for read transfers");
        cy(1'b1, 1'b0, 32'h0, 1'b0, 32'h0, 4'h1, 1'b0, 1'b0);
      end
      6 : begin
        expect_err("PSEL HIGH during reset");
        cy(1'b1, 1'b0, 32'h0, 1'b0, 32'h0, 4'h0, 1'b0, 1'b0);
        presetn = 1'b0;
        @(vr.req_cb);
        @(vr.req_cb);
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
    vr      = u_apb;
    vc      = u_apb;
    presetn = 1'b0;
    repeat( 3 ) begin
      @(posedge pclk);
    end
    #1;
    presetn = 1'b1;
    @(vr.req_cb);
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
