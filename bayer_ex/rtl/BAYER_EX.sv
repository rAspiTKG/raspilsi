// ============================================================================
// BAYER_EX : 論理合成・配置配線のトップ(ポートを平らにしたラッパ)
//   BAYER_EX_CORE のインタフェースのポート(i_pix / o_pix)を、bayer4x2_t の
//   ポート(i_data / o_data)にする。論理は持たない。
//   合成の流れで使う sv2v は、インタフェースのポートを持つモジュールをトップにできない
//   (インスタンスにして、それを含むモジュールをトップにする)ため。
// ============================================================================
module BAYER_EX
  import BAYER_EX_PKG::*;
(
  input  logic      clk
 ,input  logic      rst_n
 ,input  cfg_t      i_cfg
 // 入力側
 ,input  logic      i_vld
 ,output logic      o_busy
 ,input  bayer4x2_t i_data
 // 出力側
 ,output logic      o_vld
 ,input  logic      i_busy
 ,output bayer4x2_t o_data
);

  BAYER_EX_DATA_IF s_i_pix ();  // 入力の data
  BAYER_EX_DATA_IF s_o_pix ();  // 出力の data

  assign s_i_pix.data = i_data;
  assign o_data       = s_o_pix.data;

  BAYER_EX_CORE u_core (
    .clk    (clk)
   ,.rst_n  (rst_n)
   ,.i_cfg  (i_cfg)
   ,.i_vld  (i_vld)
   ,.o_busy (o_busy)
   ,.i_pix  (s_i_pix)
   ,.o_vld  (o_vld)
   ,.i_busy (i_busy)
   ,.o_pix  (s_o_pix)
  );

endmodule
