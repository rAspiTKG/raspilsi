//=============================================================================
// axlm_test_lib.svh
//-----------------------------------------------------------------------------
//  axlm_base_test  : env 生成、トポロジ表示、PASS/FAIL 判定
//  axlm_smoke_test : axlm_smoke_vseq を実行
//  axlm_rand_test  : axlm_rand_vseq を実行 (+CMD_NUM=<n> で 1 ラウンドあたりのコマンド数)
//=============================================================================

class axlm_base_test extends uvm_test;

  `uvm_component_utils(axlm_base_test)

  axlm_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = axlm_env::type_id::create("env", this);
    // 何かがハングしても終わるように (+UVM_TIMEOUT で上書き可)
    uvm_root::get().set_timeout(500ms, 1);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_root::get().print_topology();
    `uvm_info("TEST", $sformatf("ADDR_WIDTH=%0d DATA_WIDTH=%0d MEM_DEPTH=%0d MAX_WR_OUTSTANDING=%0d MAX_RD_OUTSTANDING=%0d STOP_ON_ERROR=%0d (write window %0h.., read window %0h.., %0d words)", ADDR_W, DATA_W, MEM_DEPTH, MAX_WR, MAX_RD, STOP_ON_ERROR, WB, RB, LWIN), UVM_NONE)
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
  protected task run_vseq(uvm_phase phase, axlm_base_vseq vseq);
    phase.raise_objection(this);
    vseq.start(env.vsqr);
    phase.get_objection().set_drain_time(this, 100ns);
    phase.drop_objection(this);
  endtask

endclass

class axlm_smoke_test extends axlm_base_test;

  `uvm_component_utils(axlm_smoke_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    axlm_smoke_vseq vseq;
    vseq = axlm_smoke_vseq::type_id::create("vseq");
    run_vseq(phase, vseq);
  endtask

endclass

class axlm_rand_test extends axlm_base_test;

  `uvm_component_utils(axlm_rand_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    axlm_rand_vseq vseq;
    int unsigned   num;
    vseq = axlm_rand_vseq::type_id::create("vseq");
    if( $value$plusargs("CMD_NUM=%d",num) ) begin
      vseq.m_num = num;
    end
    run_vseq(phase, vseq);
  endtask

endclass
