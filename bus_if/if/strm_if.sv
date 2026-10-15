//=============================================================================
// strm_if.sv
//-----------------------------------------------------------------------------
//  簡易ストリーム (valid / ready) の interface。
//  これまでの axi4_full_slave_stream / axi4_full_master_stream の m_t* / s_t* と同じ信号
//  (AXI4-Stream の TDATA / TSTRB / TLAST / TID と同じ扱い。TADDR はこのストリーム独自のアドレス)。
//
//  parameter
//    DATA_WIDTH / ID_WIDTH / ADDR_WIDTH : 幅 (tstrb は DATA_WIDTH/8 ビット)
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
//      - TVALID は TREADY まで下げず、中身も変えない (IHI 0051A 2.2.1)
//      - リセット中とリセット解除の直後のエッジは TVALID=0 (2.7.2)
//      - TVALID / TREADY と、TVALID の間の TSTRB / TLAST / TID / TADDR が X / Z でない
//
//  合成では SYNTHESIS を定義して読む (Genus : read_hdl -define SYNTHESIS ...)。
//
//  参考: AMBA 4 AXI4-Stream Protocol Specification (Arm IHI 0051A)
//=============================================================================
`timescale 1ns / 1ps

interface strm_if #(
  parameter int unsigned DATA_WIDTH = 64
 ,parameter int unsigned ID_WIDTH   = 4
 ,parameter int unsigned ADDR_WIDTH = 32
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
  logic [DATA_WIDTH-1:0]   tdata;
  logic [DATA_WIDTH/8-1:0] tstrb;
  logic                    tlast;
  logic [ID_WIDTH-1:0]     tid;
  logic [ADDR_WIDTH-1:0]   taddr;
  logic                    tvalid;
  // 受信側
  logic                    tready;

  //---------------------------------------------------------------------------
  // modport (合成用)
  //---------------------------------------------------------------------------
  modport src (
    output tdata
   ,output tstrb
   ,output tlast
   ,output tid
   ,output taddr
   ,output tvalid
   ,input  tready
  );

  modport snk (
    input  tdata
   ,input  tstrb
   ,input  tlast
   ,input  tid
   ,input  taddr
   ,input  tvalid
   ,output tready
  );

  modport mon (
    input tdata
   ,input tstrb
   ,input tlast
   ,input tid
   ,input taddr
   ,input tvalid
   ,input tready
  );

`ifndef SYNTHESIS
  //---------------------------------------------------------------------------
  // TB 用 : clocking block と modport
  //   clocking block の出力は tb_* に書き、TB_ROLE で選んだ側だけ、tb_* を本物の信号につなぐ。
  //   (RTL がつながる信号を clocking block の出力にすると、同じ変数を 2 か所から駆動することになり、
  //    IEEE 1800 の規則に反する。RTL 同士をつなぐ interface (TB_ROLE=0) では tb_* は使われない)
  //---------------------------------------------------------------------------
  // verilator lint_off UNUSEDSIGNAL
  logic [DATA_WIDTH-1:0]   tb_tdata = '0;
  logic [DATA_WIDTH/8-1:0] tb_tstrb = '0;
  logic                    tb_tlast = '0;
  logic [ID_WIDTH-1:0]     tb_tid = '0;
  logic [ADDR_WIDTH-1:0]   tb_taddr = '0;
  logic                    tb_tvalid = '0;
  logic                    tb_tready = '0;

  clocking src_cb @(posedge clk);
    default input #1step output #100ps;
    output tdata  = tb_tdata;
    output tstrb  = tb_tstrb;
    output tlast  = tb_tlast;
    output tid    = tb_tid;
    output taddr  = tb_taddr;
    output tvalid = tb_tvalid;
    input  tready;
  endclocking

  clocking snk_cb @(posedge clk);
    default input #1step output #100ps;
    input  tdata;
    input  tstrb;
    input  tlast;
    input  tid;
    input  taddr;
    input  tvalid;
    output tready = tb_tready;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input tdata;
    input tstrb;
    input tlast;
    input tid;
    input taddr;
    input tvalid;
    input tready;
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
    assign tdata  = tb_tdata;
    assign tstrb  = tb_tstrb;
    assign tlast  = tb_tlast;
    assign tid    = tb_tid;
    assign taddr  = tb_taddr;
    assign tvalid = tb_tvalid;
  end else begin : g_chk_src
    // TB_ROLE が送信側をつながないとき、src_cb の出力を書いても信号は変わらない。書いたら警告する
    initial begin
      @({
        tb_tdata
       ,tb_tstrb
       ,tb_tlast
       ,tb_tid
       ,tb_taddr
       ,tb_tvalid
      });
      $warning("strm_if: src_cb was written, but TB_ROLE=%0d does not connect src_cb to the bus (use TB_ROLE=1 or 3)", TB_ROLE);
    end
  end

  // TB_ROLE=2 (または 3) : TB が受信側の信号を駆動する (snk_cb)
  if( (TB_ROLE==2)||(TB_ROLE==3) ) begin : g_tb_snk
    assign tready = tb_tready;
  end else begin : g_chk_snk
    // TB_ROLE が受信側をつながないとき、snk_cb の出力を書いても信号は変わらない。書いたら警告する
    initial begin
      @(tb_tready);
      $warning("strm_if: snk_cb was written, but TB_ROLE=%0d does not connect snk_cb to the bus (use TB_ROLE=2 or 3)", TB_ROLE);
    end
  end

  //---------------------------------------------------------------------------
  // プロトコルチェック (CHECK=1 のとき)
  //---------------------------------------------------------------------------
  // TVALID は TREADY まで下げず、中身も変えない (IHI 0051A 2.2.1)
  a_hold : assert property (@(posedge clk) disable iff (!rst_n||!CHECK) tvalid&&!tready |=> tvalid&&$stable({tdata, tstrb, tlast, tid, taddr}))
  else begin
    $error("strm_if: TVALID dropped or payload changed before TREADY (IHI 0051A 2.2.1)");
  end
  // リセット中とリセット解除の直後のエッジは TVALID=0 (2.7.2)
  a_rst : assert property (@(posedge clk) disable iff (!CHECK) !rst_n |-> !tvalid)
  else begin
    $error("strm_if: TVALID must be LOW during reset (IHI 0051A 2.7.2)");
  end
  a_rst_first : assert property (@(posedge clk) disable iff (!CHECK) $rose(rst_n) |-> !tvalid)
  else begin
    $error("strm_if: TVALID HIGH at the first edge after reset (IHI 0051A 2.7.2)");
  end

  // X / Z
  a_x_ctrl : assert property (@(posedge clk) disable iff (!rst_n||!CHECK) !$isunknown({tvalid, tready}))
  else begin
    $error("strm_if: TVALID / TREADY is X or Z");
  end
  a_x_pl : assert property (@(posedge clk) disable iff (!rst_n||!CHECK) tvalid |-> !$isunknown({tstrb, tlast, tid, taddr}))
  else begin
    $error("strm_if: TSTRB / TLAST / TID / TADDR is X or Z while TVALID is HIGH");
  end
`else
  // 合成では clk / rst_n / CHECK / TB_ROLE を使わない (未使用の警告を避けるだけで、論理は残らない)
  wire unused_ok = &{1'b0, clk, rst_n, CHECK, (TB_ROLE!=0)};
`endif

endinterface
