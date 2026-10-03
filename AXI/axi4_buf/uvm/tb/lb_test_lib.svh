//=============================================================================
// lb_test_lib.svh
//-----------------------------------------------------------------------------
//  lb_base_test  : env 生成、トポロジ表示、PASS/FAIL 判定
//  lb_smoke_test : lb_smoke_vseq を実行
//  lb_rand_test  : lb_rand_vseq を実行 (+CMD_NUM=<n> で各フェーズの本数)
//=============================================================================

class lb_base_test extends uvm_test;

  `uvm_component_utils(lb_base_test)

  lb_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = lb_env::type_id::create("env", this);
    // 何かがハングしても終わるように (+UVM_TIMEOUT で上書き可)
    uvm_root::get().set_timeout(500ms, 1);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_root::get().print_topology();
    `uvm_info("TEST", $sformatf("IN: addr=%0d data=%0d burst=%0d / OUT: addr=%0d data=%0d burst=%0d / pixel=%0d (mem %0d, msb=%0d) x%0d per word / max width=%0d / lines=%0d"
                               , IN_ADDR_W, IN_DATA_W, IN_MAX_BURST, OUT_ADDR_W, OUT_DATA_W, OUT_MAX_BURST
                               , PIXEL_BITS, PIX_MEM_BITS, PIX_ALIGN_MSB, PIX_PER_WORD, MAX_LINE_PIXELS, NUM_LINES), UVM_NONE)
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
  protected task run_vseq(uvm_phase phase, lb_base_vseq vseq);
    phase.raise_objection(this);
    vseq.start(env.vsqr);
    phase.get_objection().set_drain_time(this, 100ns);
    phase.drop_objection(this);
  endtask

endclass

class lb_smoke_test extends lb_base_test;

  `uvm_component_utils(lb_smoke_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    lb_smoke_vseq vseq;
    vseq = lb_smoke_vseq::type_id::create("vseq");
    run_vseq(phase, vseq);
  endtask

endclass

class lb_rand_test extends lb_base_test;

  `uvm_component_utils(lb_rand_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    lb_rand_vseq vseq;
    int unsigned num;
    vseq = lb_rand_vseq::type_id::create("vseq");
    if( $value$plusargs("CMD_NUM=%d",num) ) begin
      vseq.m_num = num;
    end
    run_vseq(phase, vseq);
  endtask

endclass
