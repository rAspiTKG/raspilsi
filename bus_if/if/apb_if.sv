//=============================================================================
// apb_if.sv
//-----------------------------------------------------------------------------
//  AMBA APB4 (APB3 とも互換) の interface (1 つのコンプリータ分)。
//  これまでの apb_master_mem の PSEL[n] / PREADY[n] / PRDATA / PSLVERR[n] は、この interface の配列
//  (コンプリータごとに 1 本) で表す。
//
//  parameter
//    ADDR_WIDTH / DATA_WIDTH : 幅 (DATA_WIDTH は 8 / 16 / 32)
//    CHECK   : 1 = プロトコルチェックを有効にする (シミュレーションだけ)
//    TB_ROLE : TB が clocking block で駆動する側 (シミュレーションだけ)
//              0 = なし (RTL 同士をつなぐ) / 1 = リクエスタ (req_cb) / 2 = コンプリータ (cmp_cb) / 3 = 両方
//
//  modport (合成用)
//    req : リクエスタ (マスタ / ブリッジ) 側。PSEL / PENABLE / PADDR などを出し、PREADY / PRDATA / PSLVERR を受ける
//    cmp : コンプリータ (スレーブ) 側
//    mon : 全て入力 (観測用)
//
//  SYNTHESIS が定義されていないとき (シミュレーション) だけ、次も入る
//    clocking block : req_cb / cmp_cb / mon_cb (入力は #1step、出力は 100ps 後)
//    modport        : req_tb / cmp_tb / mon_tb (clocking block + presetn)
//    TB_ROLE の確認 : TB_ROLE がつながない側の clocking block の出力を書くと $warning を出す
//                     (その出力は信号につながっていないので、書いても信号は変わらない)
//    プロトコルチェック (違反は $error)
//      - SETUP は 1 サイクルで、次は ACCESS。SETUP から ACCESS に移るときと、ACCESS の待ちの間は、
//        PSEL / PENABLE と PADDR / PWRITE / PPROT / PSTRB / PWDATA を保持する (IHI 0024E 4.1 / 3.1.2)
//      - 転送の終わりの次のサイクルは PENABLE=0 (3.1.1)
//      - 読み出しでは PSTRB を全て 0 (3.2)
//      - リセット中は PSEL=0 (この interface の決まり。仕様は IDLE を既定の状態としている (4.1))
//      - PSEL と、転送中の制御 / PREADY / PSLVERR / 読み出しデータが X / Z でない
//    PENABLE は全てのコンプリータに同じものを配ってよい (PSEL=0 のリンクの PENABLE は見ない)。
//
//  合成では SYNTHESIS を定義して読む (Genus : read_hdl -define SYNTHESIS ...)。
//  interface とモジュールの ADDR_WIDTH / DATA_WIDTH は同じ値にすること。
//
//  参考: AMBA APB Protocol Specification (Arm IHI 0024E)
//=============================================================================
`timescale 1ns / 1ps

interface apb_if #(
  parameter int unsigned ADDR_WIDTH = 32
 ,parameter int unsigned DATA_WIDTH = 32
 ,parameter bit          CHECK      = 1'b1
 ,parameter int unsigned TB_ROLE    = 0
) (
  input logic pclk
 ,input logic presetn
);

  //---------------------------------------------------------------------------
  // 信号
  //---------------------------------------------------------------------------
  // リクエスタ
  logic                    psel;
  logic                    penable;
  logic [ADDR_WIDTH-1:0]   paddr;
  logic                    pwrite;
  logic [DATA_WIDTH-1:0]   pwdata;
  logic [DATA_WIDTH/8-1:0] pstrb;
  logic [2:0]              pprot;
  // コンプリータ
  logic                    pready;
  logic [DATA_WIDTH-1:0]   prdata;
  logic                    pslverr;

  //---------------------------------------------------------------------------
  // modport (合成用)
  //---------------------------------------------------------------------------
  modport req (
    output psel
   ,output penable
   ,output paddr
   ,output pwrite
   ,output pwdata
   ,output pstrb
   ,output pprot
   ,input  pready
   ,input  prdata
   ,input  pslverr
  );

  modport cmp (
    input  psel
   ,input  penable
   ,input  paddr
   ,input  pwrite
   ,input  pwdata
   ,input  pstrb
   ,input  pprot
   ,output pready
   ,output prdata
   ,output pslverr
  );

  modport mon (
    input psel
   ,input penable
   ,input paddr
   ,input pwrite
   ,input pwdata
   ,input pstrb
   ,input pprot
   ,input pready
   ,input prdata
   ,input pslverr
  );

`ifndef SYNTHESIS
  //---------------------------------------------------------------------------
  // TB 用 : clocking block と modport
  //   clocking block の出力は tb_* に書き、TB_ROLE で選んだ側だけ、tb_* を本物の信号につなぐ。
  //   (RTL がつながる信号を clocking block の出力にすると、同じ変数を 2 か所から駆動することになり、
  //    IEEE 1800 の規則に反する。RTL 同士をつなぐ interface (TB_ROLE=0) では tb_* は使われない)
  //---------------------------------------------------------------------------
  // verilator lint_off UNUSEDSIGNAL
  logic                    tb_psel = '0;
  logic                    tb_penable = '0;
  logic [ADDR_WIDTH-1:0]   tb_paddr = '0;
  logic                    tb_pwrite = '0;
  logic [DATA_WIDTH-1:0]   tb_pwdata = '0;
  logic [DATA_WIDTH/8-1:0] tb_pstrb = '0;
  logic [2:0]              tb_pprot = '0;
  logic                    tb_pready = '0;
  logic [DATA_WIDTH-1:0]   tb_prdata = '0;
  logic                    tb_pslverr = '0;

  clocking req_cb @(posedge pclk);
    default input #1step output #100ps;
    output psel    = tb_psel;
    output penable = tb_penable;
    output paddr   = tb_paddr;
    output pwrite  = tb_pwrite;
    output pwdata  = tb_pwdata;
    output pstrb   = tb_pstrb;
    output pprot   = tb_pprot;
    input  pready;
    input  prdata;
    input  pslverr;
  endclocking

  clocking cmp_cb @(posedge pclk);
    default input #1step output #100ps;
    input  psel;
    input  penable;
    input  paddr;
    input  pwrite;
    input  pwdata;
    input  pstrb;
    input  pprot;
    output pready  = tb_pready;
    output prdata  = tb_prdata;
    output pslverr = tb_pslverr;
  endclocking

  clocking mon_cb @(posedge pclk);
    default input #1step;
    input psel;
    input penable;
    input paddr;
    input pwrite;
    input pwdata;
    input pstrb;
    input pprot;
    input pready;
    input prdata;
    input pslverr;
  endclocking

  // verilator lint_on UNUSEDSIGNAL

  modport req_tb (
    clocking req_cb
   ,input    presetn
  );

  modport cmp_tb (
    clocking cmp_cb
   ,input    presetn
  );

  modport mon_tb (
    clocking mon_cb
   ,input    presetn
  );

  // TB_ROLE=1 (または 3) : TB がリクエスタの信号を駆動する (req_cb)
  if( (TB_ROLE==1)||(TB_ROLE==3) ) begin : g_tb_req
    assign psel    = tb_psel;
    assign penable = tb_penable;
    assign paddr   = tb_paddr;
    assign pwrite  = tb_pwrite;
    assign pwdata  = tb_pwdata;
    assign pstrb   = tb_pstrb;
    assign pprot   = tb_pprot;
  end else begin : g_chk_req
    // TB_ROLE がリクエスタをつながないとき、req_cb の出力を書いても信号は変わらない。書いたら警告する
    initial begin
      @({
        tb_psel
       ,tb_penable
       ,tb_paddr
       ,tb_pwrite
       ,tb_pwdata
       ,tb_pstrb
       ,tb_pprot
      });
      $warning("apb_if: req_cb was written, but TB_ROLE=%0d does not connect req_cb to the bus (use TB_ROLE=1 or 3)", TB_ROLE);
    end
  end

  // TB_ROLE=2 (または 3) : TB がコンプリータの信号を駆動する (cmp_cb)
  if( (TB_ROLE==2)||(TB_ROLE==3) ) begin : g_tb_cmp
    assign pready  = tb_pready;
    assign prdata  = tb_prdata;
    assign pslverr = tb_pslverr;
  end else begin : g_chk_cmp
    // TB_ROLE がコンプリータをつながないとき、cmp_cb の出力を書いても信号は変わらない。書いたら警告する
    initial begin
      @({
        tb_pready
       ,tb_prdata
       ,tb_pslverr
      });
      $warning("apb_if: cmp_cb was written, but TB_ROLE=%0d does not connect cmp_cb to the bus (use TB_ROLE=2 or 3)", TB_ROLE);
    end
  end

  //---------------------------------------------------------------------------
  // プロトコルチェック (CHECK=1 のとき)
  //---------------------------------------------------------------------------
  // SETUP (PSEL=1、PENABLE=0) は 1 サイクルだけで、次は ACCESS (IHI 0024E 4.1)
  a_setup : assert property (@(posedge pclk) disable iff (!presetn||!CHECK) psel&&!penable |=> psel&&penable)
  else begin
    $error("apb_if: SETUP phase was not followed by the ACCESS phase (IHI 0024E 4.1)");
  end
  // SETUP から ACCESS に移るとき、アドレス / 制御 / 書き込みデータを変えない (4.1)
  a_setup_stable : assert property (@(posedge pclk) disable iff (!presetn||!CHECK) psel&&!penable |=> $stable({paddr, pwrite, pprot, pstrb})&&(!pwrite||$stable(pwdata)))
  else begin
    $error("apb_if: PADDR / PWRITE / PPROT / PSTRB / PWDATA changed from SETUP to ACCESS (IHI 0024E 4.1)");
  end
  // ACCESS の待ち (PREADY=0) の間は、PSEL / PENABLE と中身を保持する (3.1.2)
  a_access_hold : assert property (@(posedge pclk) disable iff (!presetn||!CHECK) psel&&penable&&!pready |=> psel&&penable&&$stable({paddr, pwrite, pprot, pstrb})&&(!pwrite||$stable(pwdata)))
  else begin
    $error("apb_if: signals changed during a wait state of the ACCESS phase (IHI 0024E 3.1.2)");
  end
  // 転送の終わり (PREADY=1) の次のサイクルは PENABLE=0 (3.1.1 / 4.1)
  a_access_end : assert property (@(posedge pclk) disable iff (!presetn||!CHECK) psel&&penable&&pready |=> !penable)
  else begin
    $error("apb_if: PENABLE was not deasserted after the transfer (IHI 0024E 3.1.1)");
  end
  // 読み出しでは PSTRB を全て 0 にする (3.2)
  a_rd_strb : assert property (@(posedge pclk) disable iff (!presetn||!CHECK) psel&&!pwrite |-> pstrb=='0)
  else begin
    $error("apb_if: PSTRB must be LOW for read transfers (IHI 0024E 3.2)");
  end
  // リセット中は IDLE (PSEL=0)。仕様は IDLE を既定の状態としている (4.1)。この interface の決まり
  a_rst : assert property (@(posedge pclk) disable iff (!CHECK) !presetn |-> !psel)
  else begin
    $error("apb_if: PSEL HIGH during reset");
  end

  // X / Z
  a_x_sel : assert property (@(posedge pclk) disable iff (!presetn||!CHECK) !$isunknown(psel))
  else begin
    $error("apb_if: PSEL is X or Z");
  end
  a_x_ctrl : assert property (@(posedge pclk) disable iff (!presetn||!CHECK) psel |-> !$isunknown({penable, paddr, pwrite, pprot, pstrb}))
  else begin
    $error("apb_if: PENABLE / PADDR / PWRITE / PPROT / PSTRB is X or Z while PSEL is HIGH");
  end
  a_x_ready : assert property (@(posedge pclk) disable iff (!presetn||!CHECK) psel&&penable |-> !$isunknown(pready))
  else begin
    $error("apb_if: PREADY is X or Z in the ACCESS phase");
  end
  a_x_resp : assert property (@(posedge pclk) disable iff (!presetn||!CHECK) psel&&penable&&pready |-> !$isunknown(pslverr))
  else begin
    $error("apb_if: PSLVERR is X or Z at the end of the transfer");
  end
  a_x_rdata : assert property (@(posedge pclk) disable iff (!presetn||!CHECK) psel&&penable&&pready&&!pwrite |-> !$isunknown(prdata))
  else begin
    $error("apb_if: PRDATA is X or Z at the end of a read transfer");
  end
`else
  // 合成では pclk / presetn / CHECK / TB_ROLE を使わない (未使用の警告を避けるだけで、論理は残らない)
  wire unused_ok = &{1'b0, pclk, presetn, CHECK, (TB_ROLE!=0)};
`endif

endinterface
