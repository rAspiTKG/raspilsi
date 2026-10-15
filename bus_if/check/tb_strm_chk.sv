//=============================================================================
// tb_strm_chk.sv
//-----------------------------------------------------------------------------
//  strm_if のプロトコルチェックの自己テスト。TB が両側 (TB_ROLE=3) を clocking block で駆動する。
//    +SCN=0     : 正しい転送だけ (エラーが出ないこと)
//    +SCN=1〜4  : 違反を 1 つ入れる (最初に「EXPECT: <メッセージ>」を表示し、そのエラーが出ること)
//=============================================================================
`timescale 1ns / 1ps

module tb_strm_chk;

  localparam int unsigned DW = 32;
  localparam int unsigned IW = 4;
  localparam int unsigned AW = 32;

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

  strm_if #(
    .DATA_WIDTH ( DW )
   ,.ID_WIDTH   ( IW )
   ,.ADDR_WIDTH ( AW )
   ,.TB_ROLE    ( 3  )   // TB が両側を駆動する
  ) u_strm (
    .clk   ( clk   )
   ,.rst_n ( rst_n )
  );

  virtual strm_if #(.DATA_WIDTH(DW), .ID_WIDTH(IW), .ADDR_WIDTH(AW), .TB_ROLE(3)).src_tb vs;
  virtual strm_if #(.DATA_WIDTH(DW), .ID_WIDTH(IW), .ADDR_WIDTH(AW), .TB_ROLE(3)).snk_tb vk;

  // 1 サイクル分の値を出して、次のエッジまで進む
  task automatic cy(input logic tvalid, input logic [DW-1:0] tdata, input logic [IW-1:0] tid, input logic tlast, input logic tready);
    vs.src_cb.tvalid <= tvalid;
    vs.src_cb.tdata  <= tdata;
    vs.src_cb.tstrb  <= '1;
    vs.src_cb.tid    <= tid;
    vs.src_cb.taddr  <= AW'(tdata)<<2;
    vs.src_cb.tlast  <= tlast;
    vk.snk_cb.tready <= tready;
    @(vs.src_cb);
  endtask

  task automatic expect_err(input string msg);
    $display("EXPECT: %s", msg);
  endtask

  // 正しい転送 (SCN=0) : TREADY=0 の間は TVALID と中身を保持する
  task automatic legal();
    cy(1'b0, 32'h0, 4'd0, 1'b0, 1'b1);
    cy(1'b1, 32'h1, 4'd1, 1'b0, 1'b0);
    cy(1'b1, 32'h1, 4'd1, 1'b0, 1'b1);
    cy(1'b1, 32'h2, 4'd1, 1'b0, 1'b1);
    cy(1'b1, 32'h3, 4'd2, 1'b1, 1'b0);
    cy(1'b1, 32'h3, 4'd2, 1'b1, 1'b0);
    cy(1'b1, 32'h3, 4'd2, 1'b1, 1'b1);
    cy(1'b0, 32'h0, 4'd0, 1'b0, 1'b0);
  endtask

  task automatic violation(input int n);
    case( n )
      1 : begin
        expect_err("TVALID dropped or payload changed before TREADY");
        cy(1'b1, 32'h1, 4'd1, 1'b0, 1'b0);
        cy(1'b0, 32'h1, 4'd1, 1'b0, 1'b0);
      end
      2 : begin
        expect_err("TVALID dropped or payload changed before TREADY");
        cy(1'b1, 32'h1, 4'd1, 1'b0, 1'b0);
        cy(1'b1, 32'h1, 4'd2, 1'b0, 1'b1);
      end
      3 : begin
        expect_err("TVALID must be LOW during reset");
        vs.src_cb.tvalid <= 1'b1;
        rst_n = 1'b0;
        @(vs.src_cb);
        @(vs.src_cb);
      end
      4 : begin
        expect_err("TVALID HIGH at the first edge after reset");
        rst_n = 1'b0;
        @(vs.src_cb);
        @(vs.src_cb);
        // リセット中のエッジの直後に TVALID を上げ、その 1ns 後にリセットを解除する
        vs.src_cb.tvalid <= 1'b1;
        #1;
        rst_n = 1'b1;
        @(vs.src_cb);
        @(vs.src_cb);
      end
      default : begin
        $display("unknown SCN");
      end
    endcase
    cy(1'b0, 32'h0, 4'd0, 1'b0, 1'b1);
    cy(1'b0, 32'h0, 4'd0, 1'b0, 1'b1);
  endtask

  initial begin
    if( !$value$plusargs("SCN=%d",scn) ) begin
      scn = 0;
    end
    vs    = u_strm;
    vk    = u_strm;
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
