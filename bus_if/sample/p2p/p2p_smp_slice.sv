//=============================================================================
// p2p_smp_slice.sv
//-----------------------------------------------------------------------------
//  p2p_if のサンプル : 2 段のバッファ (合成可能)。入力と出力の両方に p2p_if を持つモジュールの例。
//    - 入力側の busy と出力側の vld / dat / strb / last はどちらもレジスタから出す
//      (入力側と出力側の間に組合せのパスが無い)
//    - 2 段あるので、出力側が止まらなければ毎サイクル 1 ワード流れる
//
//  ポート : s_p2p (p2p_if.snk、入力) / m_p2p (p2p_if.src、出力)
//=============================================================================
`timescale 1ns / 1ps

module p2p_smp_slice #(
  parameter int unsigned DATA_WIDTH = 64
) (
  input logic clk
 ,input logic rst_n
 ,p2p_if.snk  s_p2p
 ,p2p_if.src  m_p2p
);

  // つないだ p2p_if の幅がこのモジュールの parameter と同じか (違えばエラボレーションで止める)
  if( $bits(s_p2p.dat)!=DATA_WIDTH ) begin : g_chk_if_s
    $error("p2p_smp_slice : DATA_WIDTH differs from the p2p_if connected to s_p2p");
  end
  if( $bits(m_p2p.dat)!=DATA_WIDTH ) begin : g_chk_if_m
    $error("p2p_smp_slice : DATA_WIDTH differs from the p2p_if connected to m_p2p");
  end

  localparam int unsigned SB = DATA_WIDTH/8;
  localparam int unsigned EW = DATA_WIDTH+SB+1;   // {dat, strb, last}

  logic [EW-1:0] buf_q [2];
  logic          wp_q;      // 書く位置
  logic          rp_q;      // 読む位置
  logic [1:0]    cnt_q;     // 入っているワード数
  logic          push;
  logic          pop;

  assign push = s_p2p.vld&&!s_p2p.busy;
  assign pop  = m_p2p.vld&&!m_p2p.busy;

  always @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      wp_q  <= 1'b0;
      rp_q  <= 1'b0;
      cnt_q <= 2'd0;
    end else begin
      if( push ) begin
        wp_q <= ~wp_q;
      end
      if( pop ) begin
        rp_q <= ~rp_q;
      end
      if( push&&!pop ) begin
        cnt_q <= cnt_q+2'd1;
      end else if( pop&&!push ) begin
        cnt_q <= cnt_q-2'd1;
      end
    end
  end

  always @(posedge clk) begin
    if( push ) begin
      buf_q[wp_q] <= {s_p2p.dat, s_p2p.strb, s_p2p.last};
    end
  end

  assign s_p2p.busy = (cnt_q==2'd2);
  assign m_p2p.vld  = (cnt_q!=2'd0);
  assign m_p2p.dat  = buf_q[rp_q][EW-1-:DATA_WIDTH];
  assign m_p2p.strb = buf_q[rp_q][SB:1];
  assign m_p2p.last = buf_q[rp_q][0];

endmodule
