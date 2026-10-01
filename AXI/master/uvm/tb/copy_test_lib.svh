//=============================================================================
// copy_test_lib.svh
//-----------------------------------------------------------------------------
//  copy_base_test  : env 生成、トポロジ表示、PASS/FAIL 判定
//  copy_smoke_test : copy_smoke_vseq を実行
//  copy_rand_test  : copy_rand_vseq を実行 (+CMD_NUM=<n> で各フェーズの本数)
//=============================================================================

class copy_base_test extends uvm_test;

  `uvm_component_utils(copy_base_test)

  copy_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = copy_env::type_id::create("env", this);
    // 何かがハングしても終わるように (+UVM_TIMEOUT で上書き可)
    uvm_root::get().set_timeout(10ms, 1);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_root::get().print_topology();
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
  protected task run_vseq(uvm_phase phase, copy_base_vseq vseq);
    phase.raise_objection(this);
    vseq.start(env.vsqr);
    phase.get_objection().set_drain_time(this, 100ns);
    phase.drop_objection(this);
  endtask

endclass

class copy_smoke_test extends copy_base_test;

  `uvm_component_utils(copy_smoke_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    copy_smoke_vseq vseq;
    vseq = copy_smoke_vseq::type_id::create("vseq");
    run_vseq(phase, vseq);
  endtask

endclass

class copy_rand_test extends copy_base_test;

  `uvm_component_utils(copy_rand_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    copy_rand_vseq vseq;
    int unsigned   num;
    vseq = copy_rand_vseq::type_id::create("vseq");
    if( $value$plusargs("CMD_NUM=%d",num) ) begin
      vseq.m_num = num;
    end
    run_vseq(phase, vseq);
  endtask

endclass
