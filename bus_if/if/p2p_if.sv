//=============================================================================
// p2p_if.sv
//-----------------------------------------------------------------------------
//  p2p (vld / busy) の interface。
//  これまでの axi4_full_to_p2p_bridge / axi4_full_master_p2p_bridge の p2p_out_* / p2p_in_* と同じ信号。
//    - 送信側が dat / strb / last / vld を、受信側が busy (= ready の反転) を駆動する
//    - vld=1 かつ busy=0 のクロックの立ち上がりで 1 ビート転送する
//    - vld は busy を待たずに上げてよく、転送するまで下げない。その間 dat / strb / last も変えない
//    - p2p_in_* のように strb / last を使わない向きでは、送信側が固定値を出す
//
//  parameter
//    DATA_WIDTH : データ幅 (strb は DATA_WIDTH/8 ビット)
//    CHECK   : 1 = プロトコルチェックを有効にする (シミュレーションだけ)
//    TB_ROLE : TB が clocking block で駆動する側 (シミュレーションだけ)
//              0 = なし (RTL 同士をつなぐ) / 1 = 送信側 (src_cb) / 2 = 受信側 (snk_cb) / 3 = 両方
//
//  modport (合成用)
//    src : 送信側 / snk : 受信側 / mon : 全て入力 (観測用)
//
//  SYNTHESIS が定義されていないとき (シミュレーション) だけ、次も入る
//    clocking block : src_cb / snk_cb / mon_cb (入力は #1step、出力は 100ps 後)
//    modport        : src_tb / snk_tb / mon_tb (clocking block + rst_n)
//    TB_ROLE の確認 : TB_ROLE がつながない側の clocking block の出力を書くと $warning を出す
//                     (その出力は信号につながっていないので、書いても信号は変わらない)
//    プロトコルチェック (違反は $error)
//      - vld は転送するまで下げず、dat / strb / last も変えない
//      - リセット中は vld=0
//      - vld / busy と、vld の間の strb / last が X / Z でない
//
//  合成では SYNTHESIS を定義して読む (Genus : read_hdl -define SYNTHESIS ...)。
//=============================================================================
`timescale 1ns / 1ps

interface p2p_if #(
  parameter int unsigned DATA_WIDTH = 64
 ,parameter bit          CHECK      = 1'b1
 ,parameter int unsigned TB_ROLE    = 0
) (
  input logic clk
 ,input logic rst_n
);

  //---------------------------------------------------------------------------
  // 信号
  //---------------------------------------------------------------------------
  // 送信側
  logic [DATA_WIDTH-1:0]   dat;
  logic [DATA_WIDTH/8-1:0] strb;
  logic                    last;
  logic                    vld;
  // 受信側
  logic                    busy;

  //---------------------------------------------------------------------------
  // modport (合成用)
  //---------------------------------------------------------------------------
  modport src (
    output dat
   ,output strb
   ,output last
   ,output vld
   ,input  busy
  );

  modport snk (
    input  dat
   ,input  strb
   ,input  last
   ,input  vld
   ,output busy
  );

  modport mon (
    input dat
   ,input strb
   ,input last
   ,input vld
   ,input busy
  );

`ifndef SYNTHESIS
  //---------------------------------------------------------------------------
  // TB 用 : clocking block と modport
  //   clocking block の出力は tb_* に書き、TB_ROLE で選んだ側だけ、tb_* を本物の信号につなぐ。
  //   (RTL がつながる信号を clocking block の出力にすると、同じ変数を 2 か所から駆動することになり、
  //    IEEE 1800 の規則に反する。RTL 同士をつなぐ interface (TB_ROLE=0) では tb_* は使われない)
  //---------------------------------------------------------------------------
  // verilator lint_off UNUSEDSIGNAL
  logic [DATA_WIDTH-1:0]   tb_dat = '0;
  logic [DATA_WIDTH/8-1:0] tb_strb = '0;
  logic                    tb_last = '0;
  logic                    tb_vld = '0;
  logic                    tb_busy = '0;

  clocking src_cb @(posedge clk);
    default input #1step output #100ps;
    output dat  = tb_dat;
    output strb = tb_strb;
    output last = tb_last;
    output vld  = tb_vld;
    input  busy;
  endclocking

  clocking snk_cb @(posedge clk);
    default input #1step output #100ps;
    input  dat;
    input  strb;
    input  last;
    input  vld;
    output busy = tb_busy;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input dat;
    input strb;
    input last;
    input vld;
    input busy;
  endclocking

  // verilator lint_on UNUSEDSIGNAL

  modport src_tb (
    clocking src_cb
   ,input    rst_n
  );

  modport snk_tb (
    clocking snk_cb
   ,input    rst_n
  );

  modport mon_tb (
    clocking mon_cb
   ,input    rst_n
  );

  // TB_ROLE=1 (または 3) : TB が送信側の信号を駆動する (src_cb)
  if( (TB_ROLE==1)||(TB_ROLE==3) ) begin : g_tb_src
    assign dat  = tb_dat;
    assign strb = tb_strb;
    assign last = tb_last;
    assign vld  = tb_vld;
  end else begin : g_chk_src
    // TB_ROLE が送信側をつながないとき、src_cb の出力を書いても信号は変わらない。書いたら警告する
    initial begin
      @({
        tb_dat
       ,tb_strb
       ,tb_last
       ,tb_vld
      });
      $warning("p2p_if: src_cb was written, but TB_ROLE=%0d does not connect src_cb to the bus (use TB_ROLE=1 or 3)", TB_ROLE);
    end
  end

  // TB_ROLE=2 (または 3) : TB が受信側の信号を駆動する (snk_cb)
  if( (TB_ROLE==2)||(TB_ROLE==3) ) begin : g_tb_snk
    assign busy = tb_busy;
  end else begin : g_chk_snk
    // TB_ROLE が受信側をつながないとき、snk_cb の出力を書いても信号は変わらない。書いたら警告する
    initial begin
      @(tb_busy);
      $warning("p2p_if: snk_cb was written, but TB_ROLE=%0d does not connect snk_cb to the bus (use TB_ROLE=2 or 3)", TB_ROLE);
    end
  end

  //---------------------------------------------------------------------------
  // プロトコルチェック (CHECK=1 のとき)
  //---------------------------------------------------------------------------
  // vld は転送成立 (vld=1、busy=0) まで下げず、dat / strb / last も変えない
  a_hold : assert property (@(posedge clk) disable iff (!rst_n||!CHECK) vld&&busy |=> vld&&$stable({dat, strb, last}))
  else begin
    $error("p2p_if: vld dropped or dat / strb / last changed while busy");
  end
  // リセット中は vld=0
  a_rst : assert property (@(posedge clk) disable iff (!CHECK) !rst_n |-> !vld)
  else begin
    $error("p2p_if: vld HIGH during reset");
  end

  // X / Z
  a_x_ctrl : assert property (@(posedge clk) disable iff (!rst_n||!CHECK) !$isunknown({vld, busy}))
  else begin
    $error("p2p_if: vld / busy is X or Z");
  end
  a_x_pl : assert property (@(posedge clk) disable iff (!rst_n||!CHECK) vld |-> !$isunknown({strb, last}))
  else begin
    $error("p2p_if: strb / last is X or Z while vld is HIGH");
  end
`else
  // 合成では clk / rst_n / CHECK / TB_ROLE を使わない (未使用の警告を避けるだけで、論理は残らない)
  wire unused_ok = &{1'b0, clk, rst_n, CHECK, (TB_ROLE!=0)};
`endif

endinterface
