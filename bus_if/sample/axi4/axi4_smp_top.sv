//=============================================================================
// axi4_smp_top.sv
//-----------------------------------------------------------------------------
//  axi4_if のサンプル : マネージャとサブオーディネートを axi4_if 1 本でつなぐ (合成可能)。
//
//      axi4_smp_mgr (m_axi) ==[ axi4_if u_axi ]==> (s_axi) axi4_smp_mem
//
//  個別の信号で書くと、AW / W / B / AR / R の 39 本について wire 宣言とポート接続 x 2 が要るが、
//  interface なら interface の宣言 1 つと、ポート接続 1 行ずつで済む。
//=============================================================================
`timescale 1ns / 1ps

module axi4_smp_top #(
  parameter int unsigned ADDR_WIDTH = 32
 ,parameter int unsigned DATA_WIDTH = 64
 ,parameter int unsigned ID_WIDTH   = 4
 ,parameter int unsigned NBEAT      = 8
 ,parameter int unsigned READY_DLY  = 1
) (
  input  logic aclk
 ,input  logic aresetn
 ,input  logic start
 ,output logic busy
 ,output logic done
 ,output logic err
);

  axi4_if #(
    .ADDR_WIDTH ( ADDR_WIDTH )
   ,.DATA_WIDTH ( DATA_WIDTH )
   ,.ID_WIDTH   ( ID_WIDTH   )
  ) u_axi (
    .aclk    ( aclk    )
   ,.aresetn ( aresetn )
  );

  axi4_smp_mgr #(
    .ADDR_WIDTH ( ADDR_WIDTH )
   ,.DATA_WIDTH ( DATA_WIDTH )
   ,.ID_WIDTH   ( ID_WIDTH   )
   ,.NBEAT      ( NBEAT      )
  ) u_mgr (
    .aclk    ( aclk    )
   ,.aresetn ( aresetn )
   ,.start   ( start   )
   ,.busy    ( busy    )
   ,.done    ( done    )
   ,.err     ( err     )
   ,.m_axi   ( u_axi   )
  );

  axi4_smp_mem #(
    .ADDR_WIDTH ( ADDR_WIDTH )
   ,.DATA_WIDTH ( DATA_WIDTH )
   ,.ID_WIDTH   ( ID_WIDTH   )
   ,.READY_DLY  ( READY_DLY  )
  ) u_mem (
    .aclk    ( aclk    )
   ,.aresetn ( aresetn )
   ,.s_axi   ( u_axi   )
  );

endmodule
