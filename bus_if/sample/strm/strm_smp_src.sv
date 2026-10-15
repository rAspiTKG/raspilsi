//=============================================================================
// strm_smp_src.sv
//-----------------------------------------------------------------------------
//  strm_if のサンプル : 送信側 (合成可能)。
//  start を受けると NWORD ビートを送る。TDATA は pat(i)、TSTRB は全て 1、最後のビートで TLAST=1、
//  TID は TID、TADDR は BASE_ADDR + i * (DATA_WIDTH/8)。TVALID はレジスタから出す。done は 1 サイクル。
//
//  ポートは strm_if.src 1 本だけ。
//=============================================================================
`timescale 1ns / 1ps

module strm_smp_src #(
  parameter int unsigned     DATA_WIDTH = 64
 ,parameter int unsigned     ID_WIDTH   = 4
 ,parameter int unsigned     ADDR_WIDTH = 32
 ,parameter int unsigned     NWORD      = 16    // 1〜256
 ,parameter int unsigned     TID        = 3
 ,parameter longint unsigned BASE_ADDR  = 64'h0000_1000
) (
  input  logic clk
 ,input  logic rst_n
 ,input  logic start
 ,output logic busy
 ,output logic done
 ,strm_if.src  m_strm
);

  // つないだ strm_if の幅がこのモジュールの parameter と同じか (違えばエラボレーションで止める)
  if( ($bits(m_strm.tdata)!=DATA_WIDTH)||($bits(m_strm.tid)!=ID_WIDTH)||($bits(m_strm.taddr)!=ADDR_WIDTH) ) begin : g_chk_if
    $error("strm_smp_src : DATA_WIDTH / ID_WIDTH / ADDR_WIDTH differ from the strm_if connected to m_strm");
  end

  localparam int unsigned SB = DATA_WIDTH/8;

  logic       tvalid_q;
  logic [7:0] cnt_q;     // 送ったビート数
  logic       done_q;

  // i ビート目のデータ (バイトごとに違う値)
  function automatic logic [DATA_WIDTH-1:0] pat(input logic [7:0] i);
    logic [DATA_WIDTH-1:0] d;
    for( int k=0; k<SB; k++ ) begin
      d[8*k+:8] = (i*8'(SB)+8'(k))^8'h69;
    end
    return d;
  endfunction

  always @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      tvalid_q <= 1'b0;
      cnt_q    <= '0;
      done_q   <= 1'b0;
    end else begin
      done_q <= 1'b0;
      if( start&&!tvalid_q ) begin
        tvalid_q <= 1'b1;
        cnt_q    <= '0;
      end else if( tvalid_q&&m_strm.tready ) begin
        cnt_q <= cnt_q+8'd1;
        if( cnt_q==8'(NWORD-1) ) begin
          tvalid_q <= 1'b0;
          done_q   <= 1'b1;
        end
      end
    end
  end

  assign m_strm.tdata  = pat(cnt_q);
  assign m_strm.tstrb  = {SB{1'b1}};
  assign m_strm.tlast  = (cnt_q==8'(NWORD-1));
  assign m_strm.tid    = ID_WIDTH'(TID);
  assign m_strm.taddr  = ADDR_WIDTH'(BASE_ADDR+64'(cnt_q)*SB);
  assign m_strm.tvalid = tvalid_q;

  assign busy = tvalid_q;
  assign done = done_q;

endmodule
