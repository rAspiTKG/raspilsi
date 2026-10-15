//=============================================================================
// tb_p2p_chk.sv
//-----------------------------------------------------------------------------
//  p2p_if のプロトコルチェックの自己テスト。TB が両側 (TB_ROLE=3) を clocking block で駆動する。
//    +SCN=0     : 正しい転送だけ (エラーが出ないこと)
//    +SCN=1〜3  : 違反を 1 つ入れる (最初に「EXPECT: <メッセージ>」を表示し、そのエラーが出ること)
//=============================================================================
`timescale 1ns / 1ps

module tb_p2p_chk;

  localparam int unsigned DW = 32;

  logic clk;
  logic rst_n;
  int   scn;

  initial begin
    clk = 1'b0;
    forever begin
      #5;
      clk = ~clk;
    end
  end

  p2p_if #(
    .DATA_WIDTH ( DW )
   ,.TB_ROLE    ( 3  )   // TB が両側を駆動する
  ) u_p2p (
    .clk   ( clk   )
   ,.rst_n ( rst_n )
  );

  virtual p2p_if #(.DATA_WIDTH(DW), .TB_ROLE(3)).src_tb vs;
  virtual p2p_if #(.DATA_WIDTH(DW), .TB_ROLE(3)).snk_tb vk;

  // 1 サイクル分の値を出して、次のエッジまで進む
  task automatic cy(input logic vld, input logic [DW-1:0] dat, input logic last, input logic busy);
    vs.src_cb.vld  <= vld;
    vs.src_cb.dat  <= dat;
    vs.src_cb.strb <= '1;
    vs.src_cb.last <= last;
    vk.snk_cb.busy <= busy;
    @(vs.src_cb);
  endtask

  task automatic expect_err(input string msg);
    $display("EXPECT: %s", msg);
  endtask

  // 正しい転送 (SCN=0) : busy の間は vld と中身を保持する
  task automatic legal();
    cy(1'b0, 32'h0, 1'b0, 1'b1);
    cy(1'b1, 32'h1, 1'b0, 1'b1);
    cy(1'b1, 32'h1, 1'b0, 1'b0);
    cy(1'b1, 32'h2, 1'b0, 1'b0);
    cy(1'b1, 32'h3, 1'b1, 1'b1);
    cy(1'b1, 32'h3, 1'b1, 1'b1);
    cy(1'b1, 32'h3, 1'b1, 1'b0);
    cy(1'b0, 32'h0, 1'b0, 1'b0);
    cy(1'b0, 32'h0, 1'b0, 1'b1);
  endtask

  task automatic violation(input int n);
    case( n )
      1 : begin
        expect_err("p2p_if: vld dropped or dat / strb / last changed while busy");
        cy(1'b1, 32'h1, 1'b0, 1'b1);
        cy(1'b0, 32'h1, 1'b0, 1'b1);
      end
      2 : begin
        expect_err("p2p_if: vld dropped or dat / strb / last changed while busy");
        cy(1'b1, 32'h1, 1'b0, 1'b1);
        cy(1'b1, 32'h2, 1'b0, 1'b0);
      end
      3 : begin
        expect_err("vld HIGH during reset");
        vs.src_cb.vld <= 1'b1;
        rst_n = 1'b0;
        @(vs.src_cb);
        @(vs.src_cb);
      end
      default : begin
        $display("unknown SCN");
      end
    endcase
    cy(1'b0, 32'h0, 1'b0, 1'b0);
    cy(1'b0, 32'h0, 1'b0, 1'b0);
  endtask

  initial begin
    if( !$value$plusargs("SCN=%d",scn) ) begin
      scn = 0;
    end
    vs    = u_p2p;
    vk    = u_p2p;
    rst_n = 1'b0;
    repeat( 3 ) begin
      @(posedge clk);
    end
    #1;
    rst_n = 1'b1;
    @(vs.src_cb);
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
