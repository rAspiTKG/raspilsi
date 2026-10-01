//=============================================================================
// copy_coverage.svh
//-----------------------------------------------------------------------------
//  機能カバレッジ。
//    cg_cmd   : コマンドの長さ / src・dst の 4KB 跨ぎ / スレーブの振る舞い /
//               エラー応答 (受付時に cfg を記録し、完了時にサンプル)
//    cg_burst : DUT が出したバーストの方向と長さ、4KB 境界で終わるバースト
//=============================================================================

`uvm_analysis_imp_decl(_cstart)
`uvm_analysis_imp_decl(_cdone)
`uvm_analysis_imp_decl(_cburst)

class copy_coverage extends uvm_component;

  `uvm_component_utils(copy_coverage)

  uvm_analysis_imp_cstart #(cmd_item, copy_coverage)       start_imp;
  uvm_analysis_imp_cdone  #(cmd_item, copy_coverage)       done_imp;
  uvm_analysis_imp_cburst #(axi_burst_item, copy_coverage) burst_imp;

  axi_slv_cfg cfg;

  // サンプル値
  protected int unsigned m_len;
  protected bit          m_src_x4k;
  protected bit          m_dst_x4k;
  protected int unsigned m_stall;
  protected bit          m_rwv;
  protected bit          m_err;
  protected axi_dir_e    m_dir;
  protected int unsigned m_blen;
  protected bit          m_end4k;

  covergroup cg_cmd;
    option.per_instance = 1;
    cp_len : coverpoint m_len {
      bins one     = {1};
      bins short_b = {[2:MAX_BURST-1]};
      bins max_b   = {MAX_BURST};
      bins mid_b   = {[MAX_BURST+1:64]};
      bins long_b  = {[65:300]};
    }
    cp_src_x4k : coverpoint m_src_x4k;
    cp_dst_x4k : coverpoint m_dst_x4k;
    cp_stall : coverpoint m_stall {
      bins none  = {0};
      bins some  = {[1:49]};
      bins heavy = {[50:100]};
    }
    cp_rwv : coverpoint m_rwv;
    cp_err : coverpoint m_err;
    x_x4k : cross cp_src_x4k, cp_dst_x4k;
  endgroup

  covergroup cg_burst;
    option.per_instance = 1;
    cp_dir : coverpoint m_dir;
    cp_blen : coverpoint m_blen {
      bins one     = {1};
      bins short_b = {[2:7]};
      bins mid_b   = {[8:MAX_BURST-1]};
      bins max_b   = {MAX_BURST};
    }
    cp_end4k : coverpoint m_end4k;
    x_dir_blen : cross cp_dir, cp_blen;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    start_imp = new("start_imp", this);
    done_imp  = new("done_imp", this);
    burst_imp = new("burst_imp", this);
    cg_cmd    = new();
    cg_burst  = new();
  endfunction

  protected function bit crosses_4k(bit [ADDR_W-1:0] a, int unsigned beats);
    return (32'(a[11:0])+(beats*STRB_W))>4096;
  endfunction

  // 受付時: スレーブの設定を記録 (完了時には次の設定に変わっている可能性がある)
  function void write_cstart(cmd_item c);
    m_len     = c.len;
    m_src_x4k = crosses_4k(c.src, c.len);
    m_dst_x4k = crosses_4k(c.dst, c.len);
    m_stall   = cfg.stall_pct;
    m_rwv     = cfg.ready_wait_valid;
  endfunction

  function void write_cdone(cmd_item c);
    m_err = c.done_err;
    cg_cmd.sample();
  endfunction

  function void write_cburst(axi_burst_item t);
    m_dir   = t.dir;
    m_blen  = 32'(t.len) + 1;
    m_end4k = ((32'(t.addr[11:0])+(m_blen*STRB_W))%4096)==0;
    cg_burst.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("COV", $sformatf("cg_cmd = %0.1f %%  cg_burst = %0.1f %%"
                              , cg_cmd.get_inst_coverage(), cg_burst.get_inst_coverage()), UVM_NONE)
  endfunction

endclass
