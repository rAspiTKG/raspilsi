// ============================================================================
// bex_vbd_if : 検証環境の vld/busy/data(入力側と出力側で1つずつ使う)
//   DUT の vld / busy のポートと、BAYER_EX_DATA_IF の data をまとめて扱う。
//   転送の規則をアサーションで確かめる
//   (入力側は検証環境の送り方、出力側は DUT の出し方を確かめることになる)。
//   違反は UVM のエラーとして数える(テストの結果に反映する)。
// ============================================================================
interface bex_vbd_if (
  input logic clk
 ,input logic rst_n
);
  import uvm_pkg::*;
  import BAYER_EX_PKG::*;

  logic      vld;
  logic      busy;
  bayer4x2_t data;

  // 規則1: busy=1 の間、送り側は vld と data を保持する
  property p_hold;
    @(posedge clk) disable iff( !rst_n )
      (vld&&busy) |=> (vld&&(data==$past(data)));
  endproperty
  a_hold : assert property( p_hold ) else begin
    uvm_report_error("SVA", $sformatf("%m: busy=1 の間に vld か data が変わった"));
  end

  // 規則2: vld は不定にならない。vld=1 のとき data は不定にならない(4値のシミュレータで働く)
  a_vld_known : assert property( @(posedge clk) disable iff( !rst_n ) !$isunknown(vld) ) else begin
    uvm_report_error("SVA", $sformatf("%m: vld が不定"));
  end
  a_data_known : assert property( @(posedge clk) disable iff( !rst_n ) vld|->!$isunknown(data) ) else begin
    uvm_report_error("SVA", $sformatf("%m: vld=1 のとき data が不定"));
  end
endinterface
