//=============================================================================
// apbm_test_lib.svh
//-----------------------------------------------------------------------------
//  apbm_base_test  : env 生成、トポロジ表示、PASS/FAIL 判定
//  apbm_smoke_test : apbm_smoke_vseq を実行
//  apbm_rand_test  : apbm_rand_vseq を実行 (+CMD_NUM=<n> で各フェーズの本数)
//=============================================================================

class apbm_base_test extends uvm_test;

  `uvm_component_utils(apbm_base_test)

  apbm_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = apbm_env::type_id::create("env", this);
    // 何かがハングしても終わるように (+UVM_TIMEOUT で上書き可)
    uvm_root::get().set_timeout(500ms, 1);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_root::get().print_topology();
    `uvm_info("TEST", $sformatf("ADDR_WIDTH=%0d DATA_WIDTH=%0d NUM_SLAVES=%0d MEM_DEPTH=%0d TIMEOUT_CYCLES=%0d STOP_ON_ERROR=%0d", ADDR_W, DATA_W, NUM_SLAVES, MEM_DEPTH, TIMEOUT_CYCLES, STOP_ON_ERROR), UVM_NONE)
  endfunction

  // UVM_ERROR / UVM_FATAL が 0 件なら PASS
  function void report_phase(uvm_phase phase);
    uvm_report_server svr;
    int unsigned      n_err;
    super.report_phase(phase);
    svr   = uvm_report_server::get_server();
    n_err = svr.get_severity_count(UVM_ERROR) + svr.get_severity_count(UVM_FATAL);
    if( n_err==0 ) begin
      `uvm_info("TEST", "** TEST PASSED **", UVM_NONE)
    end else begin
      `uvm_info("TEST", $sformatf("** TEST FAILED ** (%0d errors)", n_err), UVM_NONE)
    end
  endfunction

  // 仮想シーケンスを 1 本流す共通処理
  protected task run_vseq(uvm_phase phase, apbm_base_vseq vseq);
    phase.raise_objection(this);
    vseq.start(env.vsqr);
    phase.get_objection().set_drain_time(this, 100ns);
    phase.drop_objection(this);
  endtask

endclass

class apbm_smoke_test extends apbm_base_test;

  `uvm_component_utils(apbm_smoke_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    apbm_smoke_vseq vseq;
    vseq = apbm_smoke_vseq::type_id::create("vseq");
    run_vseq(phase, vseq);
  endtask

endclass

class apbm_rand_test extends apbm_base_test;

  `uvm_component_utils(apbm_rand_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    apbm_rand_vseq vseq;
    int unsigned   num;
    vseq = apbm_rand_vseq::type_id::create("vseq");
    if( $value$plusargs("CMD_NUM=%d",num) ) begin
      vseq.m_num = num;
    end
    run_vseq(phase, vseq);
  endtask

endclass
