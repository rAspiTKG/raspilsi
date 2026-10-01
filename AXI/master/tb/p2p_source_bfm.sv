//=============================================================================
// p2p_source_bfm.sv
//-----------------------------------------------------------------------------
//  valid/busy 方式 p2p チャネルの送信側モデル。
//    tx_buf[0..n-1] を send(n) で n ビート送出する。
//    gap_pct : 各ビートの前にアイドルを挟む確率 [%]
//
//  タイミング規約 (シミュレータ非依存):
//    駆動 = negedge、転送成立 (vld && !busy) は posedge の always_ff でサンプル。
//=============================================================================
`timescale 1ns / 1ps

module p2p_source_bfm #(
  parameter int unsigned WIDTH = 64
) (
  input  logic             clk
 ,input  logic             rst_n
 ,output logic [WIDTH-1:0] p2p_dat
 ,output logic             p2p_vld
 ,input  logic             p2p_busy
);

  logic [WIDTH-1:0] tx_buf [0:255];
  int unsigned      gap_pct;
  logic             hs;

  // 転送成立を posedge で観測する
  always_ff @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      hs <= 1'b0;
    end else begin
      hs <= p2p_vld&&!p2p_busy;
    end
  end

  task automatic init();
    begin
      p2p_dat = {WIDTH{1'b0}};
      p2p_vld = 1'b0;
      gap_pct = 0;
      for( int unsigned i=0; i<256; i++ ) begin
        tx_buf[i] = {WIDTH{1'b0}};
      end
    end
  endtask

  initial begin
    init();
  end

  // tx_buf[0..n-1] を送出する
  task automatic send( input int unsigned n );
    begin
      @(negedge clk);
      for( int unsigned i=0; i<n; i++ ) begin
        while( $urandom_range(0,99)<gap_pct ) begin
          p2p_vld = 1'b0;
          @(negedge clk);
        end
        p2p_dat = tx_buf[i];
        p2p_vld = 1'b1;
        @(negedge clk);
        while( !hs ) begin
          @(negedge clk);
        end
      end
      p2p_vld = 1'b0;
    end
  endtask

endmodule
