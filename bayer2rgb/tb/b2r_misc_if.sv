// ============================================================================
// b2r_misc_if : クロック・リセット・割り込みの観測用(検証環境用)
// ============================================================================
interface b2r_misc_if (
  input logic clk
 ,input logic rst_n
 ,input logic ctrl_clk
 ,input logic ctrl_rst_n
);
  logic irq;
endinterface
