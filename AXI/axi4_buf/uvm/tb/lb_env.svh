//=============================================================================
// lb_env.svh
//-----------------------------------------------------------------------------
//  lb_vsequencer : コマンド sequencer と、両側スレーブの共有メモリ / 設定を束ねる
//  lb_env        : コマンド agent + 入力側 / 出力側 AXI スレーブ agent
//                  + scoreboard + coverage
//
//     cmd_agt.mon.ap_start --+--> scb.start_imp / cov.start_imp
//     cmd_agt.mon.ap_done  --+--> scb.done_imp  / cov.done_imp
//     rd_agt.mon.ap        --+--> scb.rd_imp    / cov.burst_imp
//     wr_agt.mon.ap        --+--> scb.wr_imp    / cov.burst_imp
//
//     src_mem / rd_cfg : 入力側 responder / scoreboard / coverage / vsqr で共有
//     dst_mem / wr_cfg : 出力側 responder / scoreboard / coverage / vsqr で共有
//=============================================================================

class lb_vsequencer extends uvm_sequencer;

  `uvm_component_utils(lb_vsequencer)

  cmd_sequencer cmd_sqr;
  axi_mem       src_mem;
  axi_mem       dst_mem;
  axi_slv_cfg   rd_cfg;
  axi_slv_cfg   wr_cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass

class lb_env extends uvm_env;

  `uvm_component_utils(lb_env)

  cmd_agent        cmd_agt;
  axi_rd_slv_agent rd_agt;
  axi_wr_slv_agent wr_agt;
  lb_scoreboard    scb;
  lb_coverage      cov;
  lb_vsequencer    vsqr;
  axi_mem          src_mem;
  axi_mem          dst_mem;
  axi_slv_cfg      rd_cfg;
  axi_slv_cfg      wr_cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    src_mem = axi_mem::type_id::create("src_mem");
    dst_mem = axi_mem::type_id::create("dst_mem");
    rd_cfg  = axi_slv_cfg::type_id::create("rd_cfg");
    wr_cfg  = axi_slv_cfg::type_id::create("wr_cfg");
    cmd_agt = cmd_agent::type_id::create("cmd_agt", this);
    rd_agt  = axi_rd_slv_agent::type_id::create("rd_agt", this);
    wr_agt  = axi_wr_slv_agent::type_id::create("wr_agt", this);
    scb     = lb_scoreboard::type_id::create("scb", this);
    cov     = lb_coverage::type_id::create("cov", this);
    vsqr    = lb_vsequencer::type_id::create("vsqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // 共有オブジェクト
    rd_agt.rsp.mem = src_mem;
    rd_agt.rsp.cfg = rd_cfg;
    wr_agt.rsp.mem = dst_mem;
    wr_agt.rsp.cfg = wr_cfg;
    scb.src_mem    = src_mem;
    scb.dst_mem    = dst_mem;
    scb.rd_cfg     = rd_cfg;
    scb.wr_cfg     = wr_cfg;
    cov.rd_cfg     = rd_cfg;
    cov.wr_cfg     = wr_cfg;
    vsqr.src_mem   = src_mem;
    vsqr.dst_mem   = dst_mem;
    vsqr.rd_cfg    = rd_cfg;
    vsqr.wr_cfg    = wr_cfg;
    vsqr.cmd_sqr   = cmd_agt.sqr;
    // scoreboard
    cmd_agt.mon.ap_start.connect(scb.start_imp);
    cmd_agt.mon.ap_done.connect(scb.done_imp);
    rd_agt.mon.ap.connect(scb.rd_imp);
    wr_agt.mon.ap.connect(scb.wr_imp);
    // coverage
    cmd_agt.mon.ap_start.connect(cov.start_imp);
    cmd_agt.mon.ap_done.connect(cov.done_imp);
    rd_agt.mon.ap.connect(cov.burst_imp);
    wr_agt.mon.ap.connect(cov.burst_imp);
  endfunction

endclass
