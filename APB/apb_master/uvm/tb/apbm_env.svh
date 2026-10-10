//=============================================================================
// apbm_env.svh
//-----------------------------------------------------------------------------
//  apbm_vsequencer : ユーザ側 sequencer と、スレーブの共有メモリ / 設定を束ねる
//  apbm_env        : ユーザ側 agent + APB スレーブ agent + scoreboard + coverage
//
//     usr_agt.mon.ap_start --+--> scb.start_imp / cov.start_imp
//     usr_agt.mon.ap_done  --+--> scb.done_imp  / cov.done_imp
//     usr_agt.mon.ap_mem   --+--> scb.mem_imp   / cov.mem_imp
//     apb_agt.mon.ap       --+--> scb.apb_imp   / cov.apb_imp
//
//     smem / cfg[] : responder / scoreboard / coverage / vsqr で共有
//=============================================================================

class apbm_vsequencer extends uvm_sequencer;

  `uvm_component_utils(apbm_vsequencer)

  usr_sequencer usr_sqr;
  apb_slv_mem   smem;
  apb_slv_cfg   cfg[NUM_SLAVES];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass

class apbm_env extends uvm_env;

  `uvm_component_utils(apbm_env)

  usr_agent       usr_agt;
  apb_slv_agent   apb_agt;
  apbm_scoreboard scb;
  apbm_coverage   cov;
  apbm_vsequencer vsqr;
  apb_slv_mem     smem;
  apb_slv_cfg     cfg[NUM_SLAVES];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    smem = apb_slv_mem::type_id::create("smem");
    for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
      cfg[s] = apb_slv_cfg::type_id::create($sformatf("cfg%0d", s));
    end
    usr_agt = usr_agent::type_id::create("usr_agt", this);
    apb_agt = apb_slv_agent::type_id::create("apb_agt", this);
    scb     = apbm_scoreboard::type_id::create("scb", this);
    cov     = apbm_coverage::type_id::create("cov", this);
    vsqr    = apbm_vsequencer::type_id::create("vsqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // 共有オブジェクト
    apb_agt.rsp.mem = smem;
    scb.smem        = smem;
    vsqr.smem       = smem;
    for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
      apb_agt.rsp.cfg[s] = cfg[s];
      scb.cfg[s]         = cfg[s];
      cov.cfg[s]         = cfg[s];
      vsqr.cfg[s]        = cfg[s];
    end
    vsqr.usr_sqr = usr_agt.sqr;
    // scoreboard
    usr_agt.mon.ap_start.connect(scb.start_imp);
    usr_agt.mon.ap_done.connect(scb.done_imp);
    usr_agt.mon.ap_mem.connect(scb.mem_imp);
    apb_agt.mon.ap.connect(scb.apb_imp);
    // coverage
    usr_agt.mon.ap_start.connect(cov.start_imp);
    usr_agt.mon.ap_done.connect(cov.done_imp);
    usr_agt.mon.ap_mem.connect(cov.mem_imp);
    apb_agt.mon.ap.connect(cov.apb_imp);
  endfunction

endclass
