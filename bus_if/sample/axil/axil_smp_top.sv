//=============================================================================
// axil_smp_top.sv
//-----------------------------------------------------------------------------
//  axil_if のサンプル : マネージャとサブオーディネートを axil_if 1 本でつなぐ (合成可能)。
//
//      axil_smp_mgr (m_axi) ==[ axil_if u_axi ]==> (s_axi) axil_smp_regs
//
//  個別の信号で書くと 19 本の wire 宣言とポート接続 x 2 が要るところが、interface の宣言 1 つで済む。
//=============================================================================
`timescale 1ns / 1ps

module axil_smp_top #(
  parameter int unsigned ADDR_WIDTH = 32
 ,parameter int unsigned DATA_WIDTH = 32
 ,parameter int unsigned NREG       = 4
 ,parameter int unsigned READY_DLY  = 1
) (
  input  logic aclk
 ,input  logic aresetn
 ,input  logic start
 ,output logic busy
 ,output logic done
 ,output logic err
);

  axil_if #(
    .ADDR_WIDTH ( ADDR_WIDTH )
   ,.DATA_WIDTH ( DATA_WIDTH )
  ) u_axi (
    .aclk    ( aclk    )
   ,.aresetn ( aresetn )
  );

  axil_smp_mgr #(
    .ADDR_WIDTH ( ADDR_WIDTH )
   ,.DATA_WIDTH ( DATA_WIDTH )
   ,.NREG       ( NREG       )
  ) u_mgr (
    .aclk    ( aclk    )
   ,.aresetn ( aresetn )
   ,.start   ( start   )
   ,.busy    ( busy    )
   ,.done    ( done    )
   ,.err     ( err     )
   ,.m_axi   ( u_axi   )
  );

  axil_smp_regs #(
    .ADDR_WIDTH ( ADDR_WIDTH )
   ,.DATA_WIDTH ( DATA_WIDTH )
   ,.NREG       ( NREG       )
   ,.READY_DLY  ( READY_DLY  )
  ) u_regs (
    .aclk    ( aclk    )
   ,.aresetn ( aresetn )
   ,.s_axi   ( u_axi   )
  );

endmodule
