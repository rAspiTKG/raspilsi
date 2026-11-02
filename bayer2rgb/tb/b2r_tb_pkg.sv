// ============================================================================
// b2r_tb_pkg : BAYER2RGB のUVM検証環境
// ============================================================================
package b2r_tb_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import BAYER2RGB_PKG::*;

  `include "uvm/b2r_frame_cfg.svh"
  `include "uvm/b2r_image.svh"
  `include "uvm/b2r_ref_model.svh"
  `include "uvm/b2r_mem.svh"
  `include "uvm/b2r_axil_agent.svh"
  `include "uvm/b2r_axi_slave.svh"
  `include "uvm/b2r_coverage.svh"
  `include "uvm/b2r_scoreboard.svh"
  `include "uvm/b2r_env.svh"
  `include "uvm/b2r_base_test.svh"
  `include "uvm/b2r_tests.svh"
endpackage
