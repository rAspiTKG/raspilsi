//=============================================================================
// p2p_smp_sink.sv
//-----------------------------------------------------------------------------
//  p2p_if のサンプル : 受信側 (合成可能)。
//    - busy を LFSR で決めた不規則なパターンで出す (レジスタ出力)
//    - 受け取ったワードが p2p_smp_src の pat(i) と同じ順で、strb が全て 1、last が NWORD ワード目だけに
//      立つことを確かめる。last を受け取ると done (1 サイクル)。err は合わないと 1
//
//  ポートは p2p_if.snk 1 本だけ。
//=============================================================================
`timescale 1ns / 1ps

module p2p_smp_sink #(
  parameter int unsigned DATA_WIDTH = 64
 ,parameter int unsigned NWORD      = 16
 ,parameter logic [7:0]  SEED       = 8'hA5
) (
  input  logic clk
 ,input  logic rst_n
 ,output logic done
 ,output logic err
 ,p2p_if.snk   s_p2p
);

  // つないだ p2p_if の幅がこのモジュールの parameter と同じか (違えばエラボレーションで止める)
  if( $bits(s_p2p.dat)!=DATA_WIDTH ) begin : g_chk_if
    $error("p2p_smp_sink : DATA_WIDTH differs from the p2p_if connected to s_p2p");
  end

  localparam int unsigned SB = DATA_WIDTH/8;

  logic [7:0] lfsr_q;
  logic [7:0] cnt_q;    // 受け取ったワード数
  logic       done_q;
  logic       err_q;
  logic       take;

  function automatic logic [DATA_WIDTH-1:0] pat(input logic [7:0] i);
    logic [DATA_WIDTH-1:0] d;
    for( int k=0; k<SB; k++ ) begin
      d[8*k+:8] = (i*8'(SB)+8'(k))^8'h3C;
    end
    return d;
  endfunction

  assign take = s_p2p.vld&&!s_p2p.busy;

  always @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      lfsr_q <= SEED;
      cnt_q  <= '0;
      done_q <= 1'b0;
      err_q  <= 1'b0;
    end else begin
      done_q <= 1'b0;
      lfsr_q <= {lfsr_q[6:0], lfsr_q[7]^lfsr_q[5]^lfsr_q[4]^lfsr_q[3]};
      if( take ) begin
        if( (s_p2p.dat!=pat(cnt_q))||(s_p2p.strb!={SB{1'b1}})||(s_p2p.last!=(cnt_q==8'(NWORD-1))) ) begin
          err_q <= 1'b1;
        end
        if( s_p2p.last ) begin
          cnt_q  <= '0;
          done_q <= 1'b1;
        end else begin
          cnt_q <= cnt_q+8'd1;
        end
      end
    end
  end

  // 4 サイクルに 1 回くらい busy にする
  assign s_p2p.busy = (lfsr_q[1:0]==2'b00);

  assign done = done_q;
  assign err  = err_q;

endmodule
