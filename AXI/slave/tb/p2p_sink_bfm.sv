//=============================================================================
// p2p_sink_bfm.sv
//-----------------------------------------------------------------------------
//  valid/busy 方式 p2p チャネルの受信側モデル。
//    転送成立 (vld && !busy) したビートを rx_buf[] に順に格納する。
//    busy_pct   : busy をアサートする確率 [%] (ランダムバックプレッシャ)
//    force_busy : 1 の間 busy を固定でアサートする
//    clear()    : rx_cnt を 0 に戻す
//=============================================================================
`timescale 1ns / 1ps

module p2p_sink_bfm #(
  parameter int unsigned WIDTH = 64
) (
  input  logic             clk
 ,input  logic             rst_n
 ,input  logic [WIDTH-1:0] p2p_dat
 ,input  logic             p2p_vld
 ,output logic             p2p_busy
);

  logic [WIDTH-1:0] rx_buf [0:511];
  int unsigned      rx_cnt;
  int unsigned      busy_pct;
  logic             force_busy;
  logic             clr;

  // 転送成立を posedge で観測して取り込む
  always_ff @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      rx_cnt <= 0;
    end else begin
      if( clr ) begin
        rx_cnt <= 0;
      end else if( p2p_vld&&!p2p_busy ) begin
        rx_buf[rx_cnt] <= p2p_dat;
        rx_cnt         <= rx_cnt + 1;
      end
    end
  end

  // busy 生成 (negedge で更新)
  initial begin
    p2p_busy   = 1'b0;
    busy_pct   = 0;
    force_busy = 1'b0;
    clr        = 1'b0;
    forever begin
      @(negedge clk);
      if( force_busy ) begin
        p2p_busy = 1'b1;
      end else begin
        p2p_busy = ($urandom_range(0,99)<busy_pct);
      end
    end
  end

  task automatic clear();
    begin
      @(negedge clk);
      clr = 1'b1;
      @(negedge clk);
      clr = 1'b0;
    end
  endtask

endmodule
