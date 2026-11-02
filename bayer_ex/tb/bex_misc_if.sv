// ============================================================================
// bex_misc_if : 設定(DUT の i_cfg)とリセットの要求(検証環境用)
//   cfg     : テストが clk の立ち上がりで書き換える
//   rst_req : テストが 0 → 1 にすると、tb_top がリセットをかける
// ============================================================================
interface bex_misc_if (
  input logic clk
 ,input logic rst_n
);
  import BAYER_EX_PKG::*;

  cfg_t cfg;
  logic rst_req;
endinterface
