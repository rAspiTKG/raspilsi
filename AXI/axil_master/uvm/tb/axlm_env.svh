//=============================================================================
// axlm_env.svh
//-----------------------------------------------------------------------------
//  axlm_vsequencer : ユーザ側の 3 つの sequencer と、スレーブの共有メモリ / 設定を束ねる
//  axlm_env        : ユーザ側 agent + AXI スレーブ agent + scoreboard + coverage
//
//     usr_agt.mon.ap_wstart / ap_wdone --+--> scb / cov
//     usr_agt.mon.ap_rstart / ap_rdone --+--> scb / cov
//     usr_agt.mon.ap_mem               --+--> scb / cov
//     axi_agt.mon.ap                   --+--> scb / cov
//
//     smem / cfg : responder / scoreboard / coverage / vsqr で共有
//=============================================================================

class axlm_vsequencer extends uvm_sequencer;

  `uvm_component_utils(axlm_vsequencer)

  cmd_sequencer wsqr;
  cmd_sequencer rsqr;
  loc_sequencer lsqr;
  axi_slv_mem   smem;
  axi_slv_cfg   cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass

class axlm_env extends uvm_env;

  `uvm_component_utils(axlm_env)

  usr_agent       usr_agt;
  axi_slv_agent   axi_agt;
  axlm_scoreboard scb;
  axlm_coverage   cov;
  axlm_vsequencer vsqr;
  axi_slv_mem     smem;
  axi_slv_cfg     cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    smem    = axi_slv_mem::type_id::create("smem");
    cfg     = axi_slv_cfg::type_id::create("cfg");
    usr_agt = usr_agent::type_id::create("usr_agt", this);
    axi_agt = axi_slv_agent::type_id::create("axi_agt", this);
    scb     = axlm_scoreboard::type_id::create("scb", this);
    cov     = axlm_coverage::type_id::create("cov", this);
    vsqr    = axlm_vsequencer::type_id::create("vsqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // 共有オブジェクト
    axi_agt.rsp.mem = smem;
    axi_agt.rsp.cfg = cfg;
    scb.smem        = smem;
    scb.cfg         = cfg;
    cov.cfg         = cfg;
    vsqr.smem       = smem;
    vsqr.cfg        = cfg;
    vsqr.wsqr       = usr_agt.wsqr;
    vsqr.rsqr       = usr_agt.rsqr;
    vsqr.lsqr       = usr_agt.lsqr;
    // scoreboard
    usr_agt.mon.ap_wstart.connect(scb.wstart_imp);
    usr_agt.mon.ap_wdone.connect(scb.wdone_imp);
    usr_agt.mon.ap_rstart.connect(scb.rstart_imp);
    usr_agt.mon.ap_rdone.connect(scb.rdone_imp);
    usr_agt.mon.ap_mem.connect(scb.mem_imp);
    axi_agt.mon.ap.connect(scb.axi_imp);
    // coverage
    usr_agt.mon.ap_wstart.connect(cov.wstart_imp);
    usr_agt.mon.ap_wdone.connect(cov.wdone_imp);
    usr_agt.mon.ap_rstart.connect(cov.rstart_imp);
    usr_agt.mon.ap_rdone.connect(cov.rdone_imp);
    usr_agt.mon.ap_mem.connect(cov.mem_imp);
    axi_agt.mon.ap.connect(cov.axi_imp);
  endfunction

endclass
