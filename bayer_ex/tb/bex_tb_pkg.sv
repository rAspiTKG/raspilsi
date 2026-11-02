// ============================================================================
// bex_tb_pkg : BAYER_EX の UVM 検証環境
// ============================================================================
package bex_tb_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import BAYER_EX_PKG::*;

  `include "uvm/bex_cfg.svh"
  `include "uvm/bex_image.svh"
  `include "uvm/bex_item.svh"
  `include "uvm/bex_ref_model.svh"
  `include "uvm/bex_coverage.svh"
  `include "uvm/bex_agent.svh"
  `include "uvm/bex_scoreboard.svh"
  `include "uvm/bex_env.svh"
  `include "uvm/bex_base_test.svh"
  `include "uvm/bex_tests.svh"
endpackage
