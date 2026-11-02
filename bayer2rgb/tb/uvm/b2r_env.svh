// ============================================================================
// b2r_env : 検証環境
//   axil    : AXI4-Liteマスタ(レジスタアクセス)
//   mem_slv : AXI4スレーブ(メモリモデル)
//   sb      : スコアボード(リファレンスモデルとの比較)
//   cov     : 機能カバレッジ
// ============================================================================
class b2r_env extends uvm_env;
  `uvm_component_utils(b2r_env)
  b2r_axil_agent axil;
  b2r_axi_slave  mem_slv;
  b2r_scoreboard sb;
  b2r_coverage   cov;

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  function void build_phase( uvm_phase phase );
    super.build_phase(phase);
    axil    = b2r_axil_agent::type_id::create("axil", this);
    mem_slv = b2r_axi_slave::type_id::create("mem_slv", this);
    sb      = b2r_scoreboard::type_id::create("sb", this);
    cov     = b2r_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase( uvm_phase phase );
    mem_slv.ar_ap.connect(sb.ar_imp);
    mem_slv.aw_ap.connect(sb.aw_imp);
    mem_slv.w_ap.connect(sb.w_imp);
    sb.cov = cov;
  endfunction
endclass
