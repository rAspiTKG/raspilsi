//=============================================================================
// strm_smp_top.sv
//-----------------------------------------------------------------------------
//  strm_if のサンプル : 送信側 -> レジスタスライス -> 受信側 (合成可能)。
//
//      strm_smp_src (m_strm) ==[ strm_if u_a ]==> (s_strm) strm_smp_rs (m_strm) ==[ strm_if u_b ]==> (s_strm) strm_smp_sink
//=============================================================================
`timescale 1ns / 1ps

module strm_smp_top #(
  parameter int unsigned DATA_WIDTH = 64
 ,parameter int unsigned ID_WIDTH   = 4
 ,parameter int unsigned ADDR_WIDTH = 32
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

  strm_if #(
    .DATA_WIDTH ( DATA_WIDTH )
   ,.ID_WIDTH   ( ID_WIDTH   )
   ,.ADDR_WIDTH ( ADDR_WIDTH )
  ) u_a (
    .clk   ( clk   )
   ,.rst_n ( rst_n )
  );

  strm_if #(
    .DATA_WIDTH ( DATA_WIDTH )
   ,.ID_WIDTH   ( ID_WIDTH   )
   ,.ADDR_WIDTH ( ADDR_WIDTH )
  ) u_b (
    .clk   ( clk   )
   ,.rst_n ( rst_n )
  );

  strm_smp_src #(
    .DATA_WIDTH ( DATA_WIDTH )
   ,.ID_WIDTH   ( ID_WIDTH   )
   ,.ADDR_WIDTH ( ADDR_WIDTH )
   ,.NWORD      ( NWORD      )
  ) u_src (
    .clk    ( clk      )
   ,.rst_n  ( rst_n    )
   ,.start  ( start    )
   ,.busy   ( busy     )
   ,.done   ( src_done )
   ,.m_strm ( u_a      )
  );

  strm_smp_rs #(
    .DATA_WIDTH ( DATA_WIDTH )
   ,.ID_WIDTH   ( ID_WIDTH   )
   ,.ADDR_WIDTH ( ADDR_WIDTH )
  ) u_rs (
    .clk    ( clk   )
   ,.rst_n  ( rst_n )
   ,.s_strm ( u_a   )
   ,.m_strm ( u_b   )
  );

  strm_smp_sink #(
    .DATA_WIDTH ( DATA_WIDTH )
   ,.ID_WIDTH   ( ID_WIDTH   )
   ,.ADDR_WIDTH ( ADDR_WIDTH )
   ,.NWORD      ( NWORD      )
  ) u_sink (
    .clk    ( clk   )
   ,.rst_n  ( rst_n )
   ,.done   ( done  )
   ,.err    ( err   )
   ,.s_strm ( u_b   )
  );

  // 送信側の done は使わない (受信側の done で終わりを知る)
  wire unused_ok = &{1'b0, src_done};

endmodule
