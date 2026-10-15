//=============================================================================
// axil_if.sv
//-----------------------------------------------------------------------------
//  AMBA AXI4-Lite の interface。
//  これまでのモジュール (axil_master_mem など) の m_axi_* / s_axi_* と同じ信号をまとめる。
//
//  parameter
//    ADDR_WIDTH / DATA_WIDTH : 幅 (DATA_WIDTH は AXI4-Lite では 32 か 64)
//    CHECK   : 1 = プロトコルチェックを有効にする (シミュレーションだけ)
//    TB_ROLE : TB が clocking block で駆動する側 (シミュレーションだけ)
//              0 = なし (RTL 同士をつなぐ) / 1 = マネージャ (mgr_cb) / 2 = サブオーディネート (sub_cb) / 3 = 両方
//
//  modport (合成用)
//    mgr : マネージャ (マスタ) 側。AW / W / AR を出し、B / R を受ける
//    sub : サブオーディネート (スレーブ) 側
//    mon : 全て入力 (観測用)
//
//  SYNTHESIS が定義されていないとき (シミュレーション) だけ、次も入る
//    clocking block : mgr_cb / sub_cb / mon_cb (入力は #1step、出力は 100ps 後)
//    modport        : mgr_tb / sub_tb / mon_tb (clocking block + aresetn)
//    TB_ROLE の確認 : TB_ROLE がつながない側の clocking block の出力を書くと $warning を出す
//                     (その出力は信号につながっていないので、書いても信号は変わらない)
//    プロトコルチェック (違反は $error)
//      - VALID は READY までの間、下げず、中身も変えない (IHI 0022E A3.2.1)
//      - リセット中とリセット解除の直後のエッジで VALID が 0 (A3.1.2)
//      - B は AW と W を受け取った後、R は AR を受け取った後 (A3.3.1)
//      - EXOKAY を返さない (AXI4-Lite には排他アクセスが無い)
//      - VALID / READY と、VALID の間の中身が X / Z でない (4 値シミュレータで有効)
//
//  合成では SYNTHESIS を定義して読む (Genus : read_hdl -define SYNTHESIS ...)。
//  interface とモジュールの ADDR_WIDTH / DATA_WIDTH は同じ値にすること。
//
//  参考: AMBA AXI and ACE Protocol Specification (Arm IHI 0022E)
//=============================================================================
`timescale 1ns / 1ps

interface axil_if #(
  parameter int unsigned ADDR_WIDTH = 32
 ,parameter int unsigned DATA_WIDTH = 32
 ,parameter bit          CHECK      = 1'b1
 ,parameter int unsigned TB_ROLE    = 0
) (
  input logic aclk
 ,input logic aresetn
);

  localparam int unsigned STRB_WIDTH = DATA_WIDTH/8;

  //---------------------------------------------------------------------------
  // 信号
  //---------------------------------------------------------------------------
  // AW
  logic [ADDR_WIDTH-1:0] awaddr;
  logic [2:0]            awprot;
  logic                  awvalid;
  logic                  awready;
  // W
  logic [DATA_WIDTH-1:0] wdata;
  logic [STRB_WIDTH-1:0] wstrb;
  logic                  wvalid;
  logic                  wready;
  // B
  logic [1:0]            bresp;
  logic                  bvalid;
  logic                  bready;
  // AR
  logic [ADDR_WIDTH-1:0] araddr;
  logic [2:0]            arprot;
  logic                  arvalid;
  logic                  arready;
  // R
  logic [DATA_WIDTH-1:0] rdata;
  logic [1:0]            rresp;
  logic                  rvalid;
  logic                  rready;

  //---------------------------------------------------------------------------
  // modport (合成用)
  //---------------------------------------------------------------------------
  modport mgr (
    output awaddr
   ,output awprot
   ,output awvalid
   ,input  awready
   ,output wdata
   ,output wstrb
   ,output wvalid
   ,input  wready
   ,input  bresp
   ,input  bvalid
   ,output bready
   ,output araddr
   ,output arprot
   ,output arvalid
   ,input  arready
   ,input  rdata
   ,input  rresp
   ,input  rvalid
   ,output rready
  );

  modport sub (
    input  awaddr
   ,input  awprot
   ,input  awvalid
   ,output awready
   ,input  wdata
   ,input  wstrb
   ,input  wvalid
   ,output wready
   ,output bresp
   ,output bvalid
   ,input  bready
   ,input  araddr
   ,input  arprot
   ,input  arvalid
   ,output arready
   ,output rdata
   ,output rresp
   ,output rvalid
   ,input  rready
  );

  modport mon (
    input awaddr
   ,input awprot
   ,input awvalid
   ,input awready
   ,input wdata
   ,input wstrb
   ,input wvalid
   ,input wready
   ,input bresp
   ,input bvalid
   ,input bready
   ,input araddr
   ,input arprot
   ,input arvalid
   ,input arready
   ,input rdata
   ,input rresp
   ,input rvalid
   ,input rready
  );

`ifndef SYNTHESIS
  //---------------------------------------------------------------------------
  // TB 用 : clocking block と modport
  //   clocking block の出力は tb_* に書き、TB_ROLE で選んだ側だけ、tb_* を本物の信号につなぐ。
  //   (RTL がつながる信号を clocking block の出力にすると、同じ変数を 2 か所から駆動することになり、
  //    IEEE 1800 の規則に反する。RTL 同士をつなぐ interface (TB_ROLE=0) では tb_* は使われない)
  //---------------------------------------------------------------------------
  // verilator lint_off UNUSEDSIGNAL
  logic [ADDR_WIDTH-1:0] tb_awaddr = '0;
  logic [2:0]            tb_awprot = '0;
  logic                  tb_awvalid = '0;
  logic                  tb_awready = '0;
  logic [DATA_WIDTH-1:0] tb_wdata = '0;
  logic [STRB_WIDTH-1:0] tb_wstrb = '0;
  logic                  tb_wvalid = '0;
  logic                  tb_wready = '0;
  logic [1:0]            tb_bresp = '0;
  logic                  tb_bvalid = '0;
  logic                  tb_bready = '0;
  logic [ADDR_WIDTH-1:0] tb_araddr = '0;
  logic [2:0]            tb_arprot = '0;
  logic                  tb_arvalid = '0;
  logic                  tb_arready = '0;
  logic [DATA_WIDTH-1:0] tb_rdata = '0;
  logic [1:0]            tb_rresp = '0;
  logic                  tb_rvalid = '0;
  logic                  tb_rready = '0;

  clocking mgr_cb @(posedge aclk);
    default input #1step output #100ps;
    output awaddr  = tb_awaddr;
    output awprot  = tb_awprot;
    output awvalid = tb_awvalid;
    input  awready;
    output wdata   = tb_wdata;
    output wstrb   = tb_wstrb;
    output wvalid  = tb_wvalid;
    input  wready;
    input  bresp;
    input  bvalid;
    output bready  = tb_bready;
    output araddr  = tb_araddr;
    output arprot  = tb_arprot;
    output arvalid = tb_arvalid;
    input  arready;
    input  rdata;
    input  rresp;
    input  rvalid;
    output rready  = tb_rready;
  endclocking

  clocking sub_cb @(posedge aclk);
    default input #1step output #100ps;
    input  awaddr;
    input  awprot;
    input  awvalid;
    output awready = tb_awready;
    input  wdata;
    input  wstrb;
    input  wvalid;
    output wready  = tb_wready;
    output bresp   = tb_bresp;
    output bvalid  = tb_bvalid;
    input  bready;
    input  araddr;
    input  arprot;
    input  arvalid;
    output arready = tb_arready;
    output rdata   = tb_rdata;
    output rresp   = tb_rresp;
    output rvalid  = tb_rvalid;
    input  rready;
  endclocking

  clocking mon_cb @(posedge aclk);
    default input #1step;
    input awaddr;
    input awprot;
    input awvalid;
    input awready;
    input wdata;
    input wstrb;
    input wvalid;
    input wready;
    input bresp;
    input bvalid;
    input bready;
    input araddr;
    input arprot;
    input arvalid;
    input arready;
    input rdata;
    input rresp;
    input rvalid;
    input rready;
  endclocking

  // verilator lint_on UNUSEDSIGNAL

  modport mgr_tb (
    clocking mgr_cb
   ,input    aresetn
  );

  modport sub_tb (
    clocking sub_cb
   ,input    aresetn
  );

  modport mon_tb (
    clocking mon_cb
   ,input    aresetn
  );

  // TB_ROLE=1 (または 3) : TB がマネージャの信号を駆動する (mgr_cb)
  if( (TB_ROLE==1)||(TB_ROLE==3) ) begin : g_tb_mgr
    assign awaddr  = tb_awaddr;
    assign awprot  = tb_awprot;
    assign awvalid = tb_awvalid;
    assign wdata   = tb_wdata;
    assign wstrb   = tb_wstrb;
    assign wvalid  = tb_wvalid;
    assign bready  = tb_bready;
    assign araddr  = tb_araddr;
    assign arprot  = tb_arprot;
    assign arvalid = tb_arvalid;
    assign rready  = tb_rready;
  end else begin : g_chk_mgr
    // TB_ROLE がマネージャをつながないとき、mgr_cb の出力を書いても信号は変わらない。書いたら警告する
    initial begin
      @({
        tb_awaddr
       ,tb_awprot
       ,tb_awvalid
       ,tb_wdata
       ,tb_wstrb
       ,tb_wvalid
       ,tb_bready
       ,tb_araddr
       ,tb_arprot
       ,tb_arvalid
       ,tb_rready
      });
      $warning("axil_if: mgr_cb was written, but TB_ROLE=%0d does not connect mgr_cb to the bus (use TB_ROLE=1 or 3)", TB_ROLE);
    end
  end

  // TB_ROLE=2 (または 3) : TB がサブオーディネートの信号を駆動する (sub_cb)
  if( (TB_ROLE==2)||(TB_ROLE==3) ) begin : g_tb_sub
    assign awready = tb_awready;
    assign wready  = tb_wready;
    assign bresp   = tb_bresp;
    assign bvalid  = tb_bvalid;
    assign arready = tb_arready;
    assign rdata   = tb_rdata;
    assign rresp   = tb_rresp;
    assign rvalid  = tb_rvalid;
  end else begin : g_chk_sub
    // TB_ROLE がサブオーディネートをつながないとき、sub_cb の出力を書いても信号は変わらない。書いたら警告する
    initial begin
      @({
        tb_awready
       ,tb_wready
       ,tb_bresp
       ,tb_bvalid
       ,tb_arready
       ,tb_rdata
       ,tb_rresp
       ,tb_rvalid
      });
      $warning("axil_if: sub_cb was written, but TB_ROLE=%0d does not connect sub_cb to the bus (use TB_ROLE=2 or 3)", TB_ROLE);
    end
  end

  //---------------------------------------------------------------------------
  // プロトコルチェック (CHECK=1 のとき)
  //---------------------------------------------------------------------------
  localparam logic [1:0] RESP_EXOKAY = 2'b01;

  // VALID は READY までの間、下げず、中身も変えない (A3.2.1)
  property p_hold(v, r, pl);
    @(posedge aclk) disable iff (!aresetn||!CHECK) v&&!r |=> v&&$stable(pl);
  endproperty

  // VALID の間、中身が X / Z でない
  property p_known(v, pl);
    @(posedge aclk) disable iff (!aresetn||!CHECK) v |-> !$isunknown(pl);
  endproperty

  a_aw_hold : assert property (p_hold(awvalid, awready, {awaddr, awprot}))
  else begin
    $error("axil_if: AWVALID dropped or AW changed before AWREADY (IHI 0022E A3.2.1)");
  end
  a_w_hold : assert property (p_hold(wvalid, wready, {wdata, wstrb}))
  else begin
    $error("axil_if: WVALID dropped or W changed before WREADY (IHI 0022E A3.2.1)");
  end
  a_b_hold : assert property (p_hold(bvalid, bready, bresp))
  else begin
    $error("axil_if: BVALID dropped or BRESP changed before BREADY (IHI 0022E A3.2.1)");
  end
  a_ar_hold : assert property (p_hold(arvalid, arready, {araddr, arprot}))
  else begin
    $error("axil_if: ARVALID dropped or AR changed before ARREADY (IHI 0022E A3.2.1)");
  end
  a_r_hold : assert property (p_hold(rvalid, rready, {rdata, rresp}))
  else begin
    $error("axil_if: RVALID dropped or R changed before RREADY (IHI 0022E A3.2.1)");
  end

  // リセット中は VALID が 0。マネージャはリセット解除の直後のエッジでもまだ 0 (A3.1.2)
  a_rst_mgr : assert property (@(posedge aclk) disable iff (!CHECK) !aresetn |-> !awvalid&&!wvalid&&!arvalid)
  else begin
    $error("axil_if: AWVALID / WVALID / ARVALID must be LOW during reset (IHI 0022E A3.1.2)");
  end
  a_rst_sub : assert property (@(posedge aclk) disable iff (!CHECK) !aresetn |-> !bvalid&&!rvalid)
  else begin
    $error("axil_if: BVALID / RVALID must be LOW during reset (IHI 0022E A3.1.2)");
  end
  a_rst_first : assert property (@(posedge aclk) disable iff (!CHECK) $rose(aresetn) |-> !awvalid&&!wvalid&&!arvalid)
  else begin
    $error("axil_if: VALID HIGH at the first edge after reset (IHI 0022E A3.1.2)");
  end

  // AXI4-Lite には排他アクセスが無いので EXOKAY は返らない
  a_b_exokay : assert property (@(posedge aclk) disable iff (!aresetn||!CHECK) bvalid |-> bresp!=RESP_EXOKAY)
  else begin
    $error("axil_if: EXOKAY on BRESP (AXI4-Lite has no exclusive access)");
  end
  a_r_exokay : assert property (@(posedge aclk) disable iff (!aresetn||!CHECK) rvalid |-> rresp!=RESP_EXOKAY)
  else begin
    $error("axil_if: EXOKAY on RRESP (AXI4-Lite has no exclusive access)");
  end

  // X / Z
  a_x_valid : assert property (@(posedge aclk) disable iff (!aresetn||!CHECK) !$isunknown({awvalid, wvalid, bvalid, arvalid, rvalid}))
  else begin
    $error("axil_if: VALID is X or Z");
  end
  a_x_ready : assert property (@(posedge aclk) disable iff (!aresetn||!CHECK) !$isunknown({awready, wready, bready, arready, rready}))
  else begin
    $error("axil_if: READY is X or Z");
  end
  a_x_aw : assert property (p_known(awvalid, {awaddr, awprot}))
  else begin
    $error("axil_if: AW payload is X or Z while AWVALID is HIGH");
  end
  a_x_w : assert property (p_known(wvalid, wstrb))
  else begin
    $error("axil_if: WSTRB is X or Z while WVALID is HIGH");
  end
  a_x_b : assert property (p_known(bvalid, bresp))
  else begin
    $error("axil_if: BRESP is X or Z while BVALID is HIGH");
  end
  a_x_ar : assert property (p_known(arvalid, {araddr, arprot}))
  else begin
    $error("axil_if: AR payload is X or Z while ARVALID is HIGH");
  end
  a_x_r : assert property (p_known(rvalid, rresp))
  else begin
    $error("axil_if: RRESP is X or Z while RVALID is HIGH");
  end

  //---------------------------------------------------------------------------
  // 応答の順番 : B は AW と W の後、R は AR の後 (このサイクルより前のハンドシェイクだけを数える。A3.3.1)
  //---------------------------------------------------------------------------
  int unsigned chk_n_aw;
  int unsigned chk_n_w;
  int unsigned chk_n_b;
  int unsigned chk_n_ar;
  int unsigned chk_n_r;

  function automatic void chk_clear();
    chk_n_aw = 0;
    chk_n_w  = 0;
    chk_n_b  = 0;
    chk_n_ar = 0;
    chk_n_r  = 0;
  endfunction

  function automatic void chk_update();
    if( bvalid&&((chk_n_b>=chk_n_aw)||(chk_n_b>=chk_n_w)) ) begin
      $error("axil_if: BVALID without a completed write (AW and W) (IHI 0022E A3.3.1)");
    end
    if( rvalid&&(chk_n_r>=chk_n_ar) ) begin
      $error("axil_if: RVALID without an outstanding read (IHI 0022E A3.3.1)");
    end
    if( awvalid&&awready ) begin
      chk_n_aw = chk_n_aw+1;
    end
    if( wvalid&&wready ) begin
      chk_n_w = chk_n_w+1;
    end
    if( bvalid&&bready ) begin
      chk_n_b = chk_n_b+1;
    end
    if( arvalid&&arready ) begin
      chk_n_ar = chk_n_ar+1;
    end
    if( rvalid&&rready ) begin
      chk_n_r = chk_n_r+1;
    end
  endfunction

  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      chk_clear();
    end else if( CHECK ) begin
      chk_update();
    end
  end
`else
  // 合成では aclk / aresetn / CHECK / TB_ROLE を使わない (未使用の警告を避けるだけで、論理は残らない)
  wire unused_ok = &{1'b0, aclk, aresetn, CHECK, (TB_ROLE!=0)};
`endif

endinterface
