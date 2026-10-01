//=============================================================================
// copy_env.svh
//-----------------------------------------------------------------------------
//  copy_vsequencer : コマンド sequencer と、スレーブの共有メモリ / 設定を束ねる
//  copy_env        : コマンド agent + AXI スレーブ agent + scoreboard + coverage
//
//     cmd_agt.mon.ap_start --+--> scb.start_imp / cov.start_imp
//     cmd_agt.mon.ap_done  --+--> scb.done_imp  / cov.done_imp
//     axi_agt.wr_mon.ap    --+--> scb.wr_imp    / cov.burst_imp
//     axi_agt.rd_mon.ap    --+--> scb.rd_imp    / cov.burst_imp
//
//     mem / cfg は responder / scoreboard / coverage / vsqr で共有する
//=============================================================================

class copy_vsequencer extends uvm_sequencer;

  `uvm_component_utils(copy_vsequencer)

  cmd_sequencer cmd_sqr;
  axi_mem       mem;
  axi_slv_cfg   cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass

class copy_env extends uvm_env;

  `uvm_component_utils(copy_env)

  cmd_agent       cmd_agt;
  axi_slv_agent   axi_agt;
  copy_scoreboard scb;
  copy_coverage   cov;
  copy_vsequencer vsqr;
  axi_mem         mem;
  axi_slv_cfg     cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mem     = axi_mem::type_id::create("mem");
    cfg     = axi_slv_cfg::type_id::create("cfg");
    cmd_agt = cmd_agent::type_id::create("cmd_agt", this);
    axi_agt = axi_slv_agent::type_id::create("axi_agt", this);
    scb     = copy_scoreboard::type_id::create("scb", this);
    cov     = copy_coverage::type_id::create("cov", this);
    vsqr    = copy_vsequencer::type_id::create("vsqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // 共有オブジェクト
    axi_agt.rsp.mem = mem;
    axi_agt.rsp.cfg = cfg;
    scb.mem         = mem;
    scb.cfg         = cfg;
    cov.cfg         = cfg;
    vsqr.mem        = mem;
    vsqr.cfg        = cfg;
    vsqr.cmd_sqr    = cmd_agt.sqr;
    // scoreboard
    cmd_agt.mon.ap_start.connect(scb.start_imp);
    cmd_agt.mon.ap_done.connect(scb.done_imp);
    axi_agt.wr_mon.ap.connect(scb.wr_imp);
    axi_agt.rd_mon.ap.connect(scb.rd_imp);
    // coverage
    cmd_agt.mon.ap_start.connect(cov.start_imp);
    cmd_agt.mon.ap_done.connect(cov.done_imp);
    axi_agt.wr_mon.ap.connect(cov.burst_imp);
    axi_agt.rd_mon.ap.connect(cov.burst_imp);
  endfunction

endclass
