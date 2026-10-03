//=============================================================================
// axi4_lb_fifo.sv
//-----------------------------------------------------------------------------
//  同期 FIFO (first-word fall-through)。両側とも valid/ready ハンドシェイク。
//    - rd_valid は格納数 (登録値) から生成し、rd_ready には組合せ依存しない
//    - wr_ready も格納数だけから生成する (rd 側 / wr_valid に組合せ依存しない)
//      → 前後段に組合せパスを作らない
//    - DEPTH は 2 以上。2 のべき乗である必要はない
//    - level は現在の格納数。空き数は DEPTH - level
//=============================================================================
`timescale 1ns / 1ps

module axi4_lb_fifo #(
  parameter int unsigned WIDTH = 8
 ,parameter int unsigned DEPTH = 16
) (
  input  logic                       clk
 ,input  logic                       rst_n
  // 書き込み側
 ,input  logic [WIDTH-1:0]           wr_data
 ,input  logic                       wr_valid
 ,output logic                       wr_ready
  // 読み出し側
 ,output logic [WIDTH-1:0]           rd_data
 ,output logic                       rd_valid
 ,input  logic                       rd_ready
  // ステータス (現在の格納数)
 ,output logic [$clog2(DEPTH+1)-1:0] level
);

  localparam int unsigned PTR_W = (DEPTH<2) ? 1 : $clog2(DEPTH);
  localparam int unsigned CNT_W = $clog2(DEPTH+1);

  logic [WIDTH-1:0] mem [0:DEPTH-1];
  logic [PTR_W-1:0] wr_ptr;
  logic [PTR_W-1:0] rd_ptr;
  logic [CNT_W-1:0] cnt;
  logic             push;
  logic             pop;

  assign wr_ready = (cnt!=CNT_W'(DEPTH));
  assign rd_valid = (cnt!=CNT_W'(0));
  assign rd_data  = mem[rd_ptr];
  assign level    = cnt;
  assign push     = wr_valid&&wr_ready;
  assign pop      = rd_valid&&rd_ready;

  always @(posedge clk) begin
    if( push ) begin
      mem[wr_ptr] <= wr_data;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      wr_ptr <= {PTR_W{1'b0}};
      rd_ptr <= {PTR_W{1'b0}};
      cnt    <= {CNT_W{1'b0}};
    end else begin
      if( push ) begin
        if( wr_ptr==PTR_W'(DEPTH-1) ) begin
          wr_ptr <= {PTR_W{1'b0}};
        end else begin
          wr_ptr <= wr_ptr + PTR_W'(1);
        end
      end
      if( pop ) begin
        if( rd_ptr==PTR_W'(DEPTH-1) ) begin
          rd_ptr <= {PTR_W{1'b0}};
        end else begin
          rd_ptr <= rd_ptr + PTR_W'(1);
        end
      end
      case( {push,pop} )
        2'b10 : begin
          cnt <= cnt + CNT_W'(1);
        end
        2'b01 : begin
          cnt <= cnt - CNT_W'(1);
        end
        default : begin
          cnt <= cnt;
        end
      endcase
    end
  end

  //---------------------------------------------------------------------------
  // パラメータチェック (エラボレーション時。IEEE 1800 20.11)
  //---------------------------------------------------------------------------
`ifndef AXI4_LB_NO_ELAB_CHECK
  generate
    if( DEPTH<2 ) begin : g_chk_depth
      $error("axi4_lb_fifo : DEPTH must be >= 2 (DEPTH=%0d)", DEPTH);
    end
    if( WIDTH<1 ) begin : g_chk_width
      $error("axi4_lb_fifo : WIDTH must be >= 1 (WIDTH=%0d)", WIDTH);
    end
  endgenerate
`endif

endmodule
