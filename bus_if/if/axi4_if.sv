//=============================================================================
// axi4_if.sv
//-----------------------------------------------------------------------------
//  AMBA AXI4 (AW / W / B / AR / R) の interface。
//  これまでのモジュールの m_axi_* / s_axi_* と同じ信号 (QOS / REGION あり、USER なし) をまとめる。
//
//  parameter
//    ADDR_WIDTH / DATA_WIDTH / ID_WIDTH : 幅 (DATA_WIDTH は 8 の倍数)
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
//      - バースト : AxBURST が予約値でない、AxSIZE がデータ幅以下、WRAP は 2 / 4 / 8 / 16 ビートで
//        AxSIZE にアライン、FIXED は 16 ビートまで、INCR は 4KB 境界をまたがない (A3.4.1)
//      - 排他アクセス : 16 ビートまで、総バイト数が 2 のべき乗で 128 以下、総バイト数にアライン
//      - WLAST が AWLEN+1 ビート目だけに立つ (W が AW より先に来ても確かめる)
//      - B は AW と最後の W を受け取った後、R は AR を受け取った後 (A3.3.1)。BID / RID が
//        未完了のトランザクションの ID と合う。RLAST が ARLEN+1 ビート目だけに立つ
//      - EXOKAY は排他アクセスにだけ返す
//      - VALID / READY と、VALID の間の中身が X / Z でない (4 値シミュレータで有効)
//
//  合成では SYNTHESIS を定義して読む (Genus : read_hdl -define SYNTHESIS ...)。
//  モジュールのポートは「axi4_if.mgr m_axi」のように modport 付きで書く。
//  interface とモジュールの ADDR_WIDTH / DATA_WIDTH / ID_WIDTH は同じ値にすること。
//
//  参考: AMBA AXI and ACE Protocol Specification (Arm IHI 0022E)
//=============================================================================
`timescale 1ns / 1ps

interface axi4_if #(
  parameter int unsigned ADDR_WIDTH = 32
 ,parameter int unsigned DATA_WIDTH = 64
 ,parameter int unsigned ID_WIDTH   = 4
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
  logic [ID_WIDTH-1:0]   awid;
  logic [ADDR_WIDTH-1:0] awaddr;
  logic [7:0]            awlen;
  logic [2:0]            awsize;
  logic [1:0]            awburst;
  logic                  awlock;
  logic [3:0]            awcache;
  logic [2:0]            awprot;
  logic [3:0]            awqos;
  logic [3:0]            awregion;
  logic                  awvalid;
  logic                  awready;
  // W
  logic [DATA_WIDTH-1:0] wdata;
  logic [STRB_WIDTH-1:0] wstrb;
  logic                  wlast;
  logic                  wvalid;
  logic                  wready;
  // B
  logic [ID_WIDTH-1:0]   bid;
  logic [1:0]            bresp;
  logic                  bvalid;
  logic                  bready;
  // AR
  logic [ID_WIDTH-1:0]   arid;
  logic [ADDR_WIDTH-1:0] araddr;
  logic [7:0]            arlen;
  logic [2:0]            arsize;
  logic [1:0]            arburst;
  logic                  arlock;
  logic [3:0]            arcache;
  logic [2:0]            arprot;
  logic [3:0]            arqos;
  logic [3:0]            arregion;
  logic                  arvalid;
  logic                  arready;
  // R
  logic [ID_WIDTH-1:0]   rid;
  logic [DATA_WIDTH-1:0] rdata;
  logic [1:0]            rresp;
  logic                  rlast;
  logic                  rvalid;
  logic                  rready;

  //---------------------------------------------------------------------------
  // modport (合成用)
  //---------------------------------------------------------------------------
  modport mgr (
    output awid
   ,output awaddr
   ,output awlen
   ,output awsize
   ,output awburst
   ,output awlock
   ,output awcache
   ,output awprot
   ,output awqos
   ,output awregion
   ,output awvalid
   ,input  awready
   ,output wdata
   ,output wstrb
   ,output wlast
   ,output wvalid
   ,input  wready
   ,input  bid
   ,input  bresp
   ,input  bvalid
   ,output bready
   ,output arid
   ,output araddr
   ,output arlen
   ,output arsize
   ,output arburst
   ,output arlock
   ,output arcache
   ,output arprot
   ,output arqos
   ,output arregion
   ,output arvalid
   ,input  arready
   ,input  rid
   ,input  rdata
   ,input  rresp
   ,input  rlast
   ,input  rvalid
   ,output rready
  );

  modport sub (
    input  awid
   ,input  awaddr
   ,input  awlen
   ,input  awsize
   ,input  awburst
   ,input  awlock
   ,input  awcache
   ,input  awprot
   ,input  awqos
   ,input  awregion
   ,input  awvalid
   ,output awready
   ,input  wdata
   ,input  wstrb
   ,input  wlast
   ,input  wvalid
   ,output wready
   ,output bid
   ,output bresp
   ,output bvalid
   ,input  bready
   ,input  arid
   ,input  araddr
   ,input  arlen
   ,input  arsize
   ,input  arburst
   ,input  arlock
   ,input  arcache
   ,input  arprot
   ,input  arqos
   ,input  arregion
   ,input  arvalid
   ,output arready
   ,output rid
   ,output rdata
   ,output rresp
   ,output rlast
   ,output rvalid
   ,input  rready
  );

  modport mon (
    input awid
   ,input awaddr
   ,input awlen
   ,input awsize
   ,input awburst
   ,input awlock
   ,input awcache
   ,input awprot
   ,input awqos
   ,input awregion
   ,input awvalid
   ,input awready
   ,input wdata
   ,input wstrb
   ,input wlast
   ,input wvalid
   ,input wready
   ,input bid
   ,input bresp
   ,input bvalid
   ,input bready
   ,input arid
   ,input araddr
   ,input arlen
   ,input arsize
   ,input arburst
   ,input arlock
   ,input arcache
   ,input arprot
   ,input arqos
   ,input arregion
   ,input arvalid
   ,input arready
   ,input rid
   ,input rdata
   ,input rresp
   ,input rlast
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
  logic [ID_WIDTH-1:0]   tb_awid = '0;
  logic [ADDR_WIDTH-1:0] tb_awaddr = '0;
  logic [7:0]            tb_awlen = '0;
  logic [2:0]            tb_awsize = '0;
  logic [1:0]            tb_awburst = '0;
  logic                  tb_awlock = '0;
  logic [3:0]            tb_awcache = '0;
  logic [2:0]            tb_awprot = '0;
  logic [3:0]            tb_awqos = '0;
  logic [3:0]            tb_awregion = '0;
  logic                  tb_awvalid = '0;
  logic                  tb_awready = '0;
  logic [DATA_WIDTH-1:0] tb_wdata = '0;
  logic [STRB_WIDTH-1:0] tb_wstrb = '0;
  logic                  tb_wlast = '0;
  logic                  tb_wvalid = '0;
  logic                  tb_wready = '0;
  logic [ID_WIDTH-1:0]   tb_bid = '0;
  logic [1:0]            tb_bresp = '0;
  logic                  tb_bvalid = '0;
  logic                  tb_bready = '0;
  logic [ID_WIDTH-1:0]   tb_arid = '0;
  logic [ADDR_WIDTH-1:0] tb_araddr = '0;
  logic [7:0]            tb_arlen = '0;
  logic [2:0]            tb_arsize = '0;
  logic [1:0]            tb_arburst = '0;
  logic                  tb_arlock = '0;
  logic [3:0]            tb_arcache = '0;
  logic [2:0]            tb_arprot = '0;
  logic [3:0]            tb_arqos = '0;
  logic [3:0]            tb_arregion = '0;
  logic                  tb_arvalid = '0;
  logic                  tb_arready = '0;
  logic [ID_WIDTH-1:0]   tb_rid = '0;
  logic [DATA_WIDTH-1:0] tb_rdata = '0;
  logic [1:0]            tb_rresp = '0;
  logic                  tb_rlast = '0;
  logic                  tb_rvalid = '0;
  logic                  tb_rready = '0;

  clocking mgr_cb @(posedge aclk);
    default input #1step output #100ps;
    output awid     = tb_awid;
    output awaddr   = tb_awaddr;
    output awlen    = tb_awlen;
    output awsize   = tb_awsize;
    output awburst  = tb_awburst;
    output awlock   = tb_awlock;
    output awcache  = tb_awcache;
    output awprot   = tb_awprot;
    output awqos    = tb_awqos;
    output awregion = tb_awregion;
    output awvalid  = tb_awvalid;
    input  awready;
    output wdata    = tb_wdata;
    output wstrb    = tb_wstrb;
    output wlast    = tb_wlast;
    output wvalid   = tb_wvalid;
    input  wready;
    input  bid;
    input  bresp;
    input  bvalid;
    output bready   = tb_bready;
    output arid     = tb_arid;
    output araddr   = tb_araddr;
    output arlen    = tb_arlen;
    output arsize   = tb_arsize;
    output arburst  = tb_arburst;
    output arlock   = tb_arlock;
    output arcache  = tb_arcache;
    output arprot   = tb_arprot;
    output arqos    = tb_arqos;
    output arregion = tb_arregion;
    output arvalid  = tb_arvalid;
    input  arready;
    input  rid;
    input  rdata;
    input  rresp;
    input  rlast;
    input  rvalid;
    output rready   = tb_rready;
  endclocking

  clocking sub_cb @(posedge aclk);
    default input #1step output #100ps;
    input  awid;
    input  awaddr;
    input  awlen;
    input  awsize;
    input  awburst;
    input  awlock;
    input  awcache;
    input  awprot;
    input  awqos;
    input  awregion;
    input  awvalid;
    output awready = tb_awready;
    input  wdata;
    input  wstrb;
    input  wlast;
    input  wvalid;
    output wready  = tb_wready;
    output bid     = tb_bid;
    output bresp   = tb_bresp;
    output bvalid  = tb_bvalid;
    input  bready;
    input  arid;
    input  araddr;
    input  arlen;
    input  arsize;
    input  arburst;
    input  arlock;
    input  arcache;
    input  arprot;
    input  arqos;
    input  arregion;
    input  arvalid;
    output arready = tb_arready;
    output rid     = tb_rid;
    output rdata   = tb_rdata;
    output rresp   = tb_rresp;
    output rlast   = tb_rlast;
    output rvalid  = tb_rvalid;
    input  rready;
  endclocking

  clocking mon_cb @(posedge aclk);
    default input #1step;
    input awid;
    input awaddr;
    input awlen;
    input awsize;
    input awburst;
    input awlock;
    input awcache;
    input awprot;
    input awqos;
    input awregion;
    input awvalid;
    input awready;
    input wdata;
    input wstrb;
    input wlast;
    input wvalid;
    input wready;
    input bid;
    input bresp;
    input bvalid;
    input bready;
    input arid;
    input araddr;
    input arlen;
    input arsize;
    input arburst;
    input arlock;
    input arcache;
    input arprot;
    input arqos;
    input arregion;
    input arvalid;
    input arready;
    input rid;
    input rdata;
    input rresp;
    input rlast;
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
    assign awid     = tb_awid;
    assign awaddr   = tb_awaddr;
    assign awlen    = tb_awlen;
    assign awsize   = tb_awsize;
    assign awburst  = tb_awburst;
    assign awlock   = tb_awlock;
    assign awcache  = tb_awcache;
    assign awprot   = tb_awprot;
    assign awqos    = tb_awqos;
    assign awregion = tb_awregion;
    assign awvalid  = tb_awvalid;
    assign wdata    = tb_wdata;
    assign wstrb    = tb_wstrb;
    assign wlast    = tb_wlast;
    assign wvalid   = tb_wvalid;
    assign bready   = tb_bready;
    assign arid     = tb_arid;
    assign araddr   = tb_araddr;
    assign arlen    = tb_arlen;
    assign arsize   = tb_arsize;
    assign arburst  = tb_arburst;
    assign arlock   = tb_arlock;
    assign arcache  = tb_arcache;
    assign arprot   = tb_arprot;
    assign arqos    = tb_arqos;
    assign arregion = tb_arregion;
    assign arvalid  = tb_arvalid;
    assign rready   = tb_rready;
  end else begin : g_chk_mgr
    // TB_ROLE がマネージャをつながないとき、mgr_cb の出力を書いても信号は変わらない。書いたら警告する
    initial begin
      @({
        tb_awid
       ,tb_awaddr
       ,tb_awlen
       ,tb_awsize
       ,tb_awburst
       ,tb_awlock
       ,tb_awcache
       ,tb_awprot
       ,tb_awqos
       ,tb_awregion
       ,tb_awvalid
       ,tb_wdata
       ,tb_wstrb
       ,tb_wlast
       ,tb_wvalid
       ,tb_bready
       ,tb_arid
       ,tb_araddr
       ,tb_arlen
       ,tb_arsize
       ,tb_arburst
       ,tb_arlock
       ,tb_arcache
       ,tb_arprot
       ,tb_arqos
       ,tb_arregion
       ,tb_arvalid
       ,tb_rready
      });
      $warning("axi4_if: mgr_cb was written, but TB_ROLE=%0d does not connect mgr_cb to the bus (use TB_ROLE=1 or 3)", TB_ROLE);
    end
  end

  // TB_ROLE=2 (または 3) : TB がサブオーディネートの信号を駆動する (sub_cb)
  if( (TB_ROLE==2)||(TB_ROLE==3) ) begin : g_tb_sub
    assign awready = tb_awready;
    assign wready  = tb_wready;
    assign bid     = tb_bid;
    assign bresp   = tb_bresp;
    assign bvalid  = tb_bvalid;
    assign arready = tb_arready;
    assign rid     = tb_rid;
    assign rdata   = tb_rdata;
    assign rresp   = tb_rresp;
    assign rlast   = tb_rlast;
    assign rvalid  = tb_rvalid;
  end else begin : g_chk_sub
    // TB_ROLE がサブオーディネートをつながないとき、sub_cb の出力を書いても信号は変わらない。書いたら警告する
    initial begin
      @({
        tb_awready
       ,tb_wready
       ,tb_bid
       ,tb_bresp
       ,tb_bvalid
       ,tb_arready
       ,tb_rid
       ,tb_rdata
       ,tb_rresp
       ,tb_rlast
       ,tb_rvalid
      });
      $warning("axi4_if: sub_cb was written, but TB_ROLE=%0d does not connect sub_cb to the bus (use TB_ROLE=2 or 3)", TB_ROLE);
    end
  end

  //---------------------------------------------------------------------------
  // プロトコルチェック (CHECK=1 のとき)
  //---------------------------------------------------------------------------
  localparam int unsigned OFSW        = $clog2(STRB_WIDTH);
  localparam logic [1:0]  BURST_FIXED = 2'b00;
  localparam logic [1:0]  BURST_INCR  = 2'b01;
  localparam logic [1:0]  BURST_WRAP  = 2'b10;
  localparam logic [1:0]  RESP_EXOKAY = 2'b01;

  // VALID は READY までの間、下げず、中身も変えない (A3.2.1)
  property p_hold(v, r, pl);
    @(posedge aclk) disable iff (!aresetn||!CHECK) v&&!r |=> v&&$stable(pl);
  endproperty

  // VALID の間、中身が X / Z でない
  property p_known(v, pl);
    @(posedge aclk) disable iff (!aresetn||!CHECK) v |-> !$isunknown(pl);
  endproperty

  // AW / AR の規則 (成り立つべき条件)
  property p_rule(v, ok);
    @(posedge aclk) disable iff (!aresetn||!CHECK) v |-> ok;
  endproperty

  // WRAP : 2 / 4 / 8 / 16 ビートで、先頭アドレスが AxSIZE にアライン
  function automatic bit wrap_ok(input logic [ADDR_WIDTH-1:0] a, input logic [7:0] len, input logic [2:0] size);
    logic [63:0] a64;
    a64 = 64'(a);
    return ((len==8'd1)||(len==8'd3)||(len==8'd7)||(len==8'd15))&&((a64&((64'd1<<size)-64'd1))==64'd0);
  endfunction

  // INCR : 4KB 境界をまたがない (最初のビートは AxSIZE にアラインした位置から数える)
  function automatic bit incr_4kb_ok(input logic [ADDR_WIDTH-1:0] a, input logic [7:0] len, input logic [2:0] size);
    logic [63:0] a64;
    logic [63:0] last;
    a64  = 64'(a);
    last = (a64&64'hFFF&~((64'd1<<size)-64'd1))+((64'(len)+64'd1)<<size)-64'd1;
    return last<=64'hFFF;
  endfunction

  // 排他アクセス : 16 ビートまで、総バイト数が 2 のべき乗で 128 以下、総バイト数にアライン
  function automatic bit excl_ok(input logic [ADDR_WIDTH-1:0] a, input logic [7:0] len, input logic [2:0] size);
    logic [63:0] a64;
    logic [63:0] beats;
    logic [63:0] bytes;
    a64   = 64'(a);
    beats = 64'(len)+64'd1;
    bytes = beats<<size;
    return (len<=8'd15)&&((beats&(beats-64'd1))==64'd0)&&(bytes<=64'd128)&&((a64&(bytes-64'd1))==64'd0);
  endfunction

  a_aw_hold : assert property (p_hold(awvalid, awready, {awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion}))
  else begin
    $error("axi4_if: AWVALID dropped or AW changed before AWREADY (IHI 0022E A3.2.1)");
  end
  a_w_hold : assert property (p_hold(wvalid, wready, {wdata, wstrb, wlast}))
  else begin
    $error("axi4_if: WVALID dropped or W changed before WREADY (IHI 0022E A3.2.1)");
  end
  a_b_hold : assert property (p_hold(bvalid, bready, {bid, bresp}))
  else begin
    $error("axi4_if: BVALID dropped or B changed before BREADY (IHI 0022E A3.2.1)");
  end
  a_ar_hold : assert property (p_hold(arvalid, arready, {arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion}))
  else begin
    $error("axi4_if: ARVALID dropped or AR changed before ARREADY (IHI 0022E A3.2.1)");
  end
  a_r_hold : assert property (p_hold(rvalid, rready, {rid, rdata, rresp, rlast}))
  else begin
    $error("axi4_if: RVALID dropped or R changed before RREADY (IHI 0022E A3.2.1)");
  end

  // リセット中は VALID が 0。マネージャはリセット解除の直後のエッジでもまだ 0 (A3.1.2)
  a_rst_mgr : assert property (@(posedge aclk) disable iff (!CHECK) !aresetn |-> !awvalid&&!wvalid&&!arvalid)
  else begin
    $error("axi4_if: AWVALID / WVALID / ARVALID must be LOW during reset (IHI 0022E A3.1.2)");
  end
  a_rst_sub : assert property (@(posedge aclk) disable iff (!CHECK) !aresetn |-> !bvalid&&!rvalid)
  else begin
    $error("axi4_if: BVALID / RVALID must be LOW during reset (IHI 0022E A3.1.2)");
  end
  a_rst_first : assert property (@(posedge aclk) disable iff (!CHECK) $rose(aresetn) |-> !awvalid&&!wvalid&&!arvalid)
  else begin
    $error("axi4_if: VALID HIGH at the first edge after reset (IHI 0022E A3.1.2)");
  end

  // バースト (A3.4.1)
  a_aw_burst : assert property (p_rule(awvalid, awburst!=2'b11))
  else begin
    $error("axi4_if: AWBURST is reserved (IHI 0022E A3.4.1)");
  end
  a_aw_size : assert property (p_rule(awvalid, awsize<=3'(OFSW)))
  else begin
    $error("axi4_if: AWSIZE exceeds the data bus width (IHI 0022E A3.4.1)");
  end
  a_aw_wrap : assert property (p_rule(awvalid&&(awburst==BURST_WRAP), wrap_ok(awaddr, awlen, awsize)))
  else begin
    $error("axi4_if: WRAP write burst must be 2/4/8/16 beats and aligned to AWSIZE (IHI 0022E A3.4.1)");
  end
  a_aw_fixed : assert property (p_rule(awvalid&&(awburst==BURST_FIXED), awlen<=8'd15))
  else begin
    $error("axi4_if: FIXED write burst longer than 16 beats (IHI 0022E A3.4.1)");
  end
  a_aw_4kb : assert property (p_rule(awvalid&&(awburst==BURST_INCR), incr_4kb_ok(awaddr, awlen, awsize)))
  else begin
    $error("axi4_if: INCR write burst crosses a 4KB boundary (IHI 0022E A3.4.1)");
  end
  a_aw_excl : assert property (p_rule(awvalid&&awlock, excl_ok(awaddr, awlen, awsize)))
  else begin
    $error("axi4_if: exclusive write violates the exclusive access restrictions");
  end
  a_ar_burst : assert property (p_rule(arvalid, arburst!=2'b11))
  else begin
    $error("axi4_if: ARBURST is reserved (IHI 0022E A3.4.1)");
  end
  a_ar_size : assert property (p_rule(arvalid, arsize<=3'(OFSW)))
  else begin
    $error("axi4_if: ARSIZE exceeds the data bus width (IHI 0022E A3.4.1)");
  end
  a_ar_wrap : assert property (p_rule(arvalid&&(arburst==BURST_WRAP), wrap_ok(araddr, arlen, arsize)))
  else begin
    $error("axi4_if: WRAP read burst must be 2/4/8/16 beats and aligned to ARSIZE (IHI 0022E A3.4.1)");
  end
  a_ar_fixed : assert property (p_rule(arvalid&&(arburst==BURST_FIXED), arlen<=8'd15))
  else begin
    $error("axi4_if: FIXED read burst longer than 16 beats (IHI 0022E A3.4.1)");
  end
  a_ar_4kb : assert property (p_rule(arvalid&&(arburst==BURST_INCR), incr_4kb_ok(araddr, arlen, arsize)))
  else begin
    $error("axi4_if: INCR read burst crosses a 4KB boundary (IHI 0022E A3.4.1)");
  end
  a_ar_excl : assert property (p_rule(arvalid&&arlock, excl_ok(araddr, arlen, arsize)))
  else begin
    $error("axi4_if: exclusive read violates the exclusive access restrictions");
  end

  // X / Z
  a_x_valid : assert property (@(posedge aclk) disable iff (!aresetn||!CHECK) !$isunknown({awvalid, wvalid, bvalid, arvalid, rvalid}))
  else begin
    $error("axi4_if: VALID is X or Z");
  end
  a_x_ready : assert property (@(posedge aclk) disable iff (!aresetn||!CHECK) !$isunknown({awready, wready, bready, arready, rready}))
  else begin
    $error("axi4_if: READY is X or Z");
  end
  a_x_aw : assert property (p_known(awvalid, {awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion}))
  else begin
    $error("axi4_if: AW payload is X or Z while AWVALID is HIGH");
  end
  a_x_w : assert property (p_known(wvalid, {wstrb, wlast}))
  else begin
    $error("axi4_if: WSTRB / WLAST is X or Z while WVALID is HIGH");
  end
  a_x_b : assert property (p_known(bvalid, {bid, bresp}))
  else begin
    $error("axi4_if: B payload is X or Z while BVALID is HIGH");
  end
  a_x_ar : assert property (p_known(arvalid, {arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion}))
  else begin
    $error("axi4_if: AR payload is X or Z while ARVALID is HIGH");
  end
  a_x_r : assert property (p_known(rvalid, {rid, rresp, rlast}))
  else begin
    $error("axi4_if: RID / RRESP / RLAST is X or Z while RVALID is HIGH");
  end

  //---------------------------------------------------------------------------
  // トランザクションの対応 (WLAST / B / R の順番と ID)
  //---------------------------------------------------------------------------
  typedef struct packed {
    logic [ID_WIDTH-1:0] id;
    logic [8:0]          beats;  // AxLEN+1
    logic                excl;   // AxLOCK
    logic                wdone;  // 書き込み : 最後の W まで受け取った
    logic [8:0]          cnt;    // 読み出し : 受け取った R のビート数
  } chk_tx_t;

  chk_tx_t     chk_aw_q[$];     // B を待っている書き込み (AW の順)
  chk_tx_t     chk_ar_q[$];     // R を待っている読み出し (AR の順)
  int unsigned chk_wdone_q[$];  // AW より先に終わった W のバーストのビート数
  int unsigned chk_wcnt;        // 今の W のバーストのビート数

  // W のデータの行き先 (最後の W をまだ受け取っていない、いちばん古い AW)。無ければ -1
  function automatic int chk_wtarget();
    for( int i=0; i<chk_aw_q.size(); i++ ) begin
      if( !chk_aw_q[i].wdone ) begin
        return i;
      end
    end
    return -1;
  endfunction

  function automatic void chk_clear();
    chk_aw_q.delete();
    chk_ar_q.delete();
    chk_wdone_q.delete();
    chk_wcnt = 0;
  endfunction

  // B : AW と最後の W のハンドシェイクが、このサイクルより前に終わっていること (A3.3.1)
  function automatic void chk_b();
    int idx;
    idx = -1;
    for( int i=0; i<chk_aw_q.size(); i++ ) begin
      if( chk_aw_q[i].wdone&&(chk_aw_q[i].id==bid) ) begin
        idx = i;
        break;
      end
    end
    if( idx<0 ) begin
      $error("axi4_if: BVALID without a completed write (AW and the last W) for BID=%0h (IHI 0022E A3.3.1)", bid);
    end else if( bready ) begin
      if( (bresp==RESP_EXOKAY)&&!chk_aw_q[idx].excl ) begin
        $error("axi4_if: EXOKAY for a write that is not exclusive (BID=%0h)", bid);
      end
      chk_aw_q.delete(idx);
    end
  endfunction

  // R : AR のハンドシェイクが、このサイクルより前に終わっていること (A3.3.1)。RLAST は最後のビートだけ
  function automatic void chk_r();
    int      idx;
    chk_tx_t e;
    idx = -1;
    for( int i=0; i<chk_ar_q.size(); i++ ) begin
      if( chk_ar_q[i].id==rid ) begin
        idx = i;
        break;
      end
    end
    if( idx<0 ) begin
      $error("axi4_if: RVALID without an outstanding read for RID=%0h (IHI 0022E A3.3.1)", rid);
    end else if( rready ) begin
      e     = chk_ar_q[idx];
      e.cnt = e.cnt+9'd1;
      if( rlast!=(e.cnt==e.beats) ) begin
        $error("axi4_if: RLAST=%0d at beat %0d of ARLEN+1=%0d (RID=%0h)", rlast, e.cnt, e.beats, rid);
      end
      if( (rresp==RESP_EXOKAY)&&!e.excl ) begin
        $error("axi4_if: EXOKAY for a read that is not exclusive (RID=%0h)", rid);
      end
      if( e.cnt==e.beats ) begin
        chk_ar_q.delete(idx);
      end else begin
        chk_ar_q[idx] = e;
      end
    end
  endfunction

  // このサイクルの AW / W / AR のハンドシェイクを反映する
  function automatic void chk_update();
    chk_tx_t     e;
    int          t;
    int unsigned n;
    if( awvalid&&awready ) begin
      e.id    = awid;
      e.beats = 9'(awlen)+9'd1;
      e.excl  = awlock;
      e.wdone = 1'b0;
      e.cnt   = '0;
      if( chk_wdone_q.size()>0 ) begin
        // データが先に終わっていた
        n = chk_wdone_q.pop_front();
        if( n!=int'(e.beats) ) begin
          $error("axi4_if: WLAST at beat %0d but AWLEN+1=%0d", n, e.beats);
        end
        e.wdone = 1'b1;
      end else if( (chk_wtarget()<0)&&(chk_wcnt>=int'(e.beats)) ) begin
        // データが先に来ていて、AWLEN+1 ビートを超えても WLAST が無い
        $error("axi4_if: %0d W beats without WLAST but AWLEN+1=%0d", chk_wcnt, e.beats);
        e.wdone  = 1'b1;
        chk_wcnt = 0;
      end
      chk_aw_q.push_back(e);
    end
    if( wvalid&&wready ) begin
      chk_wcnt = chk_wcnt+1;
      t        = chk_wtarget();
      if( t>=0 ) begin
        e = chk_aw_q[t];
        if( wlast!=(chk_wcnt==int'(e.beats)) ) begin
          $error("axi4_if: WLAST=%0d at beat %0d of AWLEN+1=%0d", wlast, chk_wcnt, e.beats);
        end
        if( wlast||(chk_wcnt>=int'(e.beats)) ) begin
          e.wdone     = 1'b1;
          chk_aw_q[t] = e;
          chk_wcnt    = 0;
        end
      end else if( wlast ) begin
        chk_wdone_q.push_back(chk_wcnt);
        chk_wcnt = 0;
      end
    end
    if( arvalid&&arready ) begin
      e.id    = arid;
      e.beats = 9'(arlen)+9'd1;
      e.excl  = arlock;
      e.wdone = 1'b0;
      e.cnt   = '0;
      chk_ar_q.push_back(e);
    end
  endfunction

  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      chk_clear();
    end else if( CHECK ) begin
      if( bvalid ) begin
        chk_b();
      end
      if( rvalid ) begin
        chk_r();
      end
      chk_update();
    end
  end
`else
  // 合成では aclk / aresetn / CHECK / TB_ROLE を使わない (未使用の警告を避けるだけで、論理は残らない)
  wire unused_ok = &{1'b0, aclk, aresetn, CHECK, (TB_ROLE!=0)};
`endif

endinterface
