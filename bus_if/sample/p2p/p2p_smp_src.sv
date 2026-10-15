//=============================================================================
// p2p_smp_src.sv
//-----------------------------------------------------------------------------
//  p2p_if のサンプル : 送信側 (合成可能)。
//  start を受けると NWORD ワード (データは pat(i)、strb は全て 1、最後のワードで last=1) を送る。
//  vld はレジスタから出し、busy=0 のエッジで次のワードに進む。done は 1 サイクル。
//
//  ポートは p2p_if.src 1 本だけ。
//=============================================================================
`timescale 1ns / 1ps

module p2p_smp_src #(
  parameter int unsigned DATA_WIDTH = 64
 ,parameter int unsigned NWORD      = 16     // 1〜256
) (
  input  logic clk
 ,input  logic rst_n
 ,input  logic start
 ,output logic busy
 ,output logic done
 ,p2p_if.src   m_p2p
);

  // つないだ p2p_if の幅がこのモジュールの parameter と同じか (違えばエラボレーションで止める)
  if( $bits(m_p2p.dat)!=DATA_WIDTH ) begin : g_chk_if
    $error("p2p_smp_src : DATA_WIDTH differs from the p2p_if connected to m_p2p");
  end

  localparam int unsigned SB = DATA_WIDTH/8;

  logic       vld_q;
  logic [7:0] cnt_q;    // 送ったワード数
  logic       done_q;

  // i ワード目のデータ (バイトごとに違う値)
  function automatic logic [DATA_WIDTH-1:0] pat(input logic [7:0] i);
    logic [DATA_WIDTH-1:0] d;
    for( int k=0; k<SB; k++ ) begin
      d[8*k+:8] = (i*8'(SB)+8'(k))^8'h3C;
    end
    return d;
  endfunction

  always @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      vld_q  <= 1'b0;
      cnt_q  <= '0;
      done_q <= 1'b0;
    end else begin
      done_q <= 1'b0;
      if( start&&!vld_q ) begin
        vld_q <= 1'b1;
        cnt_q <= '0;
      end else if( vld_q&&!m_p2p.busy ) begin
        cnt_q <= cnt_q+8'd1;
        if( cnt_q==8'(NWORD-1) ) begin
          vld_q  <= 1'b0;
          done_q <= 1'b1;
        end
      end
    end
  end

  assign m_p2p.dat  = pat(cnt_q);
  assign m_p2p.strb = {SB{1'b1}};
  assign m_p2p.last = (cnt_q==8'(NWORD-1));
  assign m_p2p.vld  = vld_q;

  assign busy = vld_q;
  assign done = done_q;

endmodule
