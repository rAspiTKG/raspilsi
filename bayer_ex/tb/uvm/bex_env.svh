// ============================================================================
// bex_env : 検証環境
//   in_agt  : 入力側(シーケンサ + ドライバ + モニタ)
//   out_agt : 出力側(busy のドライバ + モニタ)
//   sb      : スコアボード(リファレンスモデルとの比較)
//   cov     : 機能カバレッジ
// ============================================================================
class bex_env extends uvm_env;
  `uvm_component_utils(bex_env)
  bex_in_agent   in_agt;
  bex_out_agent  out_agt;
  bex_scoreboard sb;
  bex_coverage   cov;

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  function void build_phase( uvm_phase phase );
    super.build_phase(phase);
    in_agt  = bex_in_agent::type_id::create("in_agt", this);
    out_agt = bex_out_agent::type_id::create("out_agt", this);
    sb      = bex_scoreboard::type_id::create("sb", this);
    cov     = bex_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase( uvm_phase phase );
    in_agt.mon.ap.connect(sb.in_imp);
    out_agt.mon.ap.connect(sb.out_imp);
    in_agt.mon.cov  = cov;
    out_agt.mon.cov = cov;
    sb.cov          = cov;
  endfunction
endclass
