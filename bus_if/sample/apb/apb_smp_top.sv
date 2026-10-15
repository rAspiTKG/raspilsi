//=============================================================================
// apb_smp_top.sv
//-----------------------------------------------------------------------------
//  apb_if のサンプル : リクエスタとコンプリータ 2 つを apb_if の配列でつなぐ (合成可能)。
//
//      apb_smp_req (m_apb[0]) ==[ apb_if u_apb[0] ]==> (s_apb) apb_smp_regs (待ち無し)
//                  (m_apb[1]) ==[ apb_if u_apb[1] ]==> (s_apb) apb_smp_regs (待ち 2)
//
//  これまでの apb_master_mem の PSEL[n] / PREADY[n] / PRDATA / PSLVERR[n] を、コンプリータごとの
//  interface にしたもの。コンプリータを増やすときは配列の大きさと NSEL を変える。
//=============================================================================
`timescale 1ns / 1ps

module apb_smp_top #(
  parameter int unsigned ADDR_WIDTH = 32
 ,parameter int unsigned DATA_WIDTH = 32
) (
  input  logic pclk
 ,input  logic presetn
 ,input  logic start
 ,output logic busy
 ,output logic done
 ,output logic err
);

  apb_if #(
    .ADDR_WIDTH ( ADDR_WIDTH )
   ,.DATA_WIDTH ( DATA_WIDTH )
  ) u_apb [2] (
    .pclk    ( pclk    )
   ,.presetn ( presetn )
  );

  apb_smp_req #(
    .ADDR_WIDTH ( ADDR_WIDTH )
   ,.DATA_WIDTH ( DATA_WIDTH )
   ,.NSEL       ( 2          )
   ,.SEL_BITS   ( 12         )
  ) u_req (
    .pclk    ( pclk    )
   ,.presetn ( presetn )
   ,.start   ( start   )
   ,.busy    ( busy    )
   ,.done    ( done    )
   ,.err     ( err     )
   ,.m_apb   ( u_apb   )
  );

  apb_smp_regs #(
    .DATA_WIDTH ( DATA_WIDTH )
   ,.OFS_BITS   ( 12         )
   ,.WAIT       ( 0          )
  ) u_regs0 (
    .pclk    ( pclk     )
   ,.presetn ( presetn  )
   ,.s_apb   ( u_apb[0] )
  );

  apb_smp_regs #(
    .DATA_WIDTH ( DATA_WIDTH )
   ,.OFS_BITS   ( 12         )
   ,.WAIT       ( 2          )
  ) u_regs1 (
    .pclk    ( pclk     )
   ,.presetn ( presetn  )
   ,.s_apb   ( u_apb[1] )
  );

endmodule
