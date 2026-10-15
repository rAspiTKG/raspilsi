//=============================================================================
// ahb_smp_top.sv
//-----------------------------------------------------------------------------
//  ahb_if のサンプル : マネージャ -> インターコネクト -> サブオーディネート 2 つ (合成可能)。
//
//      ahb_smp_mgr (m_ahb) ==[ ahb_if u_m  (DIRECT=1) ]==> (s_ahb) ahb_smp_ic
//      ahb_smp_ic  (m_ahb) ==[ ahb_if u_s[0] (DIRECT=0) ]==> (s_ahb) ahb_smp_mem (待ち無し)
//                          ==[ ahb_if u_s[1] (DIRECT=0) ]==> (s_ahb) ahb_smp_mem (待ち 2)
//
//  サブオーディネート側のリンクは interface の配列にして、generate を使わずにまとめてつなぐ。
//=============================================================================
`timescale 1ns / 1ps

module ahb_smp_top #(
  parameter int unsigned ADDR_WIDTH   = 32
 ,parameter int unsigned DATA_WIDTH   = 32
 ,parameter int unsigned HPROT_WIDTH  = 4
 ,parameter int unsigned MASTER_WIDTH = 4
) (
  input  logic hclk
 ,input  logic hresetn
 ,input  logic start
 ,output logic busy
 ,output logic done
 ,output logic err
);

  // マネージャ <-> インターコネクト
  ahb_if #(
    .ADDR_WIDTH   ( ADDR_WIDTH   )
   ,.DATA_WIDTH   ( DATA_WIDTH   )
   ,.HPROT_WIDTH  ( HPROT_WIDTH  )
   ,.MASTER_WIDTH ( MASTER_WIDTH )
   ,.DIRECT       ( 1'b1         )
  ) u_m (
    .hclk    ( hclk    )
   ,.hresetn ( hresetn )
  );

  // インターコネクト <-> サブオーディネート (2 本)
  ahb_if #(
    .ADDR_WIDTH   ( ADDR_WIDTH   )
   ,.DATA_WIDTH   ( DATA_WIDTH   )
   ,.HPROT_WIDTH  ( HPROT_WIDTH  )
   ,.MASTER_WIDTH ( MASTER_WIDTH )
   ,.DIRECT       ( 1'b0         )
  ) u_s [2] (
    .hclk    ( hclk    )
   ,.hresetn ( hresetn )
  );

  ahb_smp_mgr #(
    .ADDR_WIDTH  ( ADDR_WIDTH  )
   ,.DATA_WIDTH  ( DATA_WIDTH  )
   ,.HPROT_WIDTH ( HPROT_WIDTH )
  ) u_mgr (
    .hclk    ( hclk    )
   ,.hresetn ( hresetn )
   ,.start   ( start   )
   ,.busy    ( busy    )
   ,.done    ( done    )
   ,.err     ( err     )
   ,.m_ahb   ( u_m     )
  );

  ahb_smp_ic #(
    .ADDR_WIDTH  ( ADDR_WIDTH )
   ,.DATA_WIDTH  ( DATA_WIDTH )
   ,.NSUB        ( 2          )
   ,.REGION_BITS ( 12         )
  ) u_ic (
    .hclk    ( hclk    )
   ,.hresetn ( hresetn )
   ,.s_ahb   ( u_m     )
   ,.m_ahb   ( u_s     )
  );

  ahb_smp_mem #(
    .DATA_WIDTH ( DATA_WIDTH )
   ,.WAIT       ( 0          )
  ) u_mem0 (
    .hclk    ( hclk    )
   ,.hresetn ( hresetn )
   ,.s_ahb   ( u_s[0]  )
  );

  ahb_smp_mem #(
    .DATA_WIDTH ( DATA_WIDTH )
   ,.WAIT       ( 2          )
  ) u_mem1 (
    .hclk    ( hclk    )
   ,.hresetn ( hresetn )
   ,.s_ahb   ( u_s[1]  )
  );

endmodule
