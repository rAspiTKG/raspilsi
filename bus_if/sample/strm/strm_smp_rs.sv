//=============================================================================
// strm_smp_rs.sv
//-----------------------------------------------------------------------------
//  strm_if のサンプル : レジスタスライス (2 段。合成可能)。入力と出力の両方に strm_if を持つモジュールの例。
//    - 入力側の TREADY と出力側の TVALID / 中身はどちらもレジスタから出す
//      (入力側と出力側の間に組合せのパスが無い)
//    - 2 段あるので、出力側が止まらなければ毎サイクル 1 ビート流れる
//
//  ポート : s_strm (strm_if.snk、入力) / m_strm (strm_if.src、出力)
//=============================================================================
`timescale 1ns / 1ps

module strm_smp_rs #(
  parameter int unsigned DATA_WIDTH = 64
 ,parameter int unsigned ID_WIDTH   = 4
 ,parameter int unsigned ADDR_WIDTH = 32
) (
  input logic  clk
 ,input logic  rst_n
 ,strm_if.snk  s_strm
 ,strm_if.src  m_strm
);

  // つないだ strm_if の幅がこのモジュールの parameter と同じか (違えばエラボレーションで止める)
  if( ($bits(s_strm.tdata)!=DATA_WIDTH)||($bits(s_strm.tid)!=ID_WIDTH)||($bits(s_strm.taddr)!=ADDR_WIDTH) ) begin : g_chk_if_s
    $error("strm_smp_rs : DATA_WIDTH / ID_WIDTH / ADDR_WIDTH differ from the strm_if connected to s_strm");
  end
  if( ($bits(m_strm.tdata)!=DATA_WIDTH)||($bits(m_strm.tid)!=ID_WIDTH)||($bits(m_strm.taddr)!=ADDR_WIDTH) ) begin : g_chk_if_m
    $error("strm_smp_rs : DATA_WIDTH / ID_WIDTH / ADDR_WIDTH differ from the strm_if connected to m_strm");
  end

  localparam int unsigned SB = DATA_WIDTH/8;
  localparam int unsigned EW = DATA_WIDTH+SB+1+ID_WIDTH+ADDR_WIDTH;   // {tdata, tstrb, tlast, tid, taddr}

  logic [EW-1:0] buf_q [2];
  logic          wp_q;
  logic          rp_q;
  logic [1:0]    cnt_q;
  logic          push;
  logic          pop;
  logic [EW-1:0] head;

  assign push = s_strm.tvalid&&s_strm.tready;
  assign pop  = m_strm.tvalid&&m_strm.tready;
  assign head = buf_q[rp_q];

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
      buf_q[wp_q] <= {s_strm.tdata, s_strm.tstrb, s_strm.tlast, s_strm.tid, s_strm.taddr};
    end
  end

  assign s_strm.tready = (cnt_q!=2'd2);
  assign m_strm.tvalid = (cnt_q!=2'd0);
  assign m_strm.tdata  = head[EW-1-:DATA_WIDTH];
  assign m_strm.tstrb  = head[ID_WIDTH+ADDR_WIDTH+1+:SB];
  assign m_strm.tlast  = head[ID_WIDTH+ADDR_WIDTH];
  assign m_strm.tid    = head[ADDR_WIDTH+:ID_WIDTH];
  assign m_strm.taddr  = head[ADDR_WIDTH-1:0];

endmodule
