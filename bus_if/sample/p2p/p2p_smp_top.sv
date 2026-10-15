//=============================================================================
// p2p_smp_top.sv
//-----------------------------------------------------------------------------
//  p2p_if のサンプル : 送信側 -> 2 段のバッファ -> 受信側 (合成可能)。
//
//      p2p_smp_src (m_p2p) ==[ p2p_if u_a ]==> (s_p2p) p2p_smp_slice (m_p2p) ==[ p2p_if u_b ]==> (s_p2p) p2p_smp_sink
//=============================================================================
`timescale 1ns / 1ps

module p2p_smp_top #(
  parameter int unsigned DATA_WIDTH = 64
 ,parameter int unsigned NWORD      = 16
) (
  input  logic clk
 ,input  logic rst_n
 ,input  logic start
 ,output logic busy
 ,output logic done
 ,output logic err
);

  logic src_done;

  p2p_if #(
    .DATA_WIDTH ( DATA_WIDTH )
  ) u_a (
    .clk   ( clk   )
   ,.rst_n ( rst_n )
  );

  p2p_if #(
    .DATA_WIDTH ( DATA_WIDTH )
  ) u_b (
    .clk   ( clk   )
   ,.rst_n ( rst_n )
  );

  p2p_smp_src #(
    .DATA_WIDTH ( DATA_WIDTH )
   ,.NWORD      ( NWORD      )
  ) u_src (
    .clk   ( clk      )
   ,.rst_n ( rst_n    )
   ,.start ( start    )
   ,.busy  ( busy     )
   ,.done  ( src_done )
   ,.m_p2p ( u_a      )
  );

  p2p_smp_slice #(
    .DATA_WIDTH ( DATA_WIDTH )
  ) u_slice (
    .clk   ( clk   )
   ,.rst_n ( rst_n )
   ,.s_p2p ( u_a   )
   ,.m_p2p ( u_b   )
  );

  p2p_smp_sink #(
    .DATA_WIDTH ( DATA_WIDTH )
   ,.NWORD      ( NWORD      )
  ) u_sink (
    .clk   ( clk   )
   ,.rst_n ( rst_n )
   ,.done  ( done  )
   ,.err   ( err   )
   ,.s_p2p ( u_b   )
  );

  // 送信側の done は使わない (受信側の done で終わりを知る)
  wire unused_ok = &{1'b0, src_done};

endmodule
