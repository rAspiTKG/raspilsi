//=============================================================================
// ahb_if.sv
//-----------------------------------------------------------------------------
//  AMBA AHB5 / AHB-Lite の interface (1 つのリンク分)。
//  これまでの ahb_master_mem (AHB5 マネージャ) と shared_sram の SCP 側 (AHB-Lite サブオーディネート) の
//  信号をまとめる。AHB-Lite で使わない信号 (HNONSEC / HEXCL / HMASTER / HWSTRB / HEXOKAY) も持つので、
//  使わない側は固定値を出す。
//
//  parameter
//    ADDR_WIDTH / DATA_WIDTH : 幅
//    HPROT_WIDTH  : 4 (AHB-Lite) / 7 (AHB5 の Extended_Memory_Types)
//    MASTER_WIDTH : HMASTER の幅 (1 以上)
//    DIRECT  : 1 = マネージャとサブオーディネートを直接つなぐ。この interface の中で
//                  HSEL=1、HREADY=HREADYOUT にする (デコーダ / マルチプレクサを置かない)
//              0 = 間にインターコネクトを置く。HSEL と HREADY は dec の modport 側が出す
//    CHECK   : 1 = プロトコルチェックを有効にする (シミュレーションだけ)
//    TB_ROLE : TB が clocking block で駆動する側 (シミュレーションだけ)
//              0 = なし (RTL 同士をつなぐ) / 1 = マネージャ (mgr_cb) / 2 = サブオーディネート (sub_cb) / 3 = 両方
//
//  modport (合成用)
//    mgr : マネージャ側。アドレスフェーズと HWDATA を出し、HREADY / HRESP / HRDATA を受ける
//    sub : サブオーディネート側。HSEL / HREADY を受け、HREADYOUT / HRESP / HRDATA を出す
//    dec : インターコネクトのサブオーディネート向きのポート。マネージャの信号に加えて HSEL と
//          HREADY (選んだサブオーディネートの HREADYOUT) を出す
//    mon : 全て入力 (観測用)
//  インターコネクトのマネージャ向きのポートは sub を使う (HREADYOUT にマルチプレクサの出力を出す。
//  そのリンクは DIRECT=1 にする)。
//
//  SYNTHESIS が定義されていないとき (シミュレーション) だけ、次も入る
//    clocking block : mgr_cb / sub_cb / mon_cb (入力は #1step、出力は 100ps 後)
//    modport        : mgr_tb / sub_tb / mon_tb (clocking block + hresetn)
//    TB_ROLE の確認 : TB_ROLE がつながない側の clocking block の出力を書くと $warning を出す
//                     (その出力は信号につながっていないので、書いても信号は変わらない)
//    プロトコルチェック (違反は $error)
//      - マネージャ : 待ちの間は NONSEQ / SEQ のアドレスフェーズを変えない (ERROR の後の IDLE は可)、
//        固定長バーストの BUSY は SEQ にだけ変えてよい (IHI 0033C 3.7.1 / 3.7.2)、
//        書き込みの待ちの間は HWDATA / HWSTRB を変えない (6.1.1)、HSIZE はデータ幅以下 (3.4)、
//        アドレスは HSIZE にアライン (3.6)、リセット中は IDLE (IHI 0033A 7.1.2)
//      - バースト : SEQ / BUSY はバーストの中だけ、SEQ のアドレスは前の転送の続き (WRAP は折り返す)、
//        制御信号はバーストの間同じ、固定長バーストのビート数 (ERROR の後の打ち切りは可)、
//        INCR は 1KB 境界をまたがない (IHI 0033C 3.2 / 3.6 / 3.6.2)
//      - サブオーディネート : IDLE / BUSY には待ち無しの OKAY (3.2)、ERROR は 2 サイクル (5.1.3)、
//        リセット中は HREADYOUT=1 (IHI 0033A 7.1.2)
//      - 制御信号と、NONSEQ / SEQ の間のアドレスフェーズ、データフェーズの応答が X / Z でない
//
//  合成では SYNTHESIS を定義して読む (Genus : read_hdl -define SYNTHESIS ...)。
//  interface とモジュールの ADDR_WIDTH / DATA_WIDTH / HPROT_WIDTH / MASTER_WIDTH は同じ値にすること。
//
//  参考: AMBA AHB Protocol Specification (Arm IHI 0033C)、AMBA 3 AHB-Lite Protocol Specification (IHI 0033A)
//=============================================================================
`timescale 1ns / 1ps

interface ahb_if #(
  parameter int unsigned ADDR_WIDTH   = 32
 ,parameter int unsigned DATA_WIDTH   = 32
 ,parameter int unsigned HPROT_WIDTH  = 4
 ,parameter int unsigned MASTER_WIDTH = 4
 ,parameter bit          DIRECT       = 1'b1
 ,parameter bit          CHECK        = 1'b1
 ,parameter int unsigned TB_ROLE      = 0
) (
  input logic hclk
 ,input logic hresetn
);

  //---------------------------------------------------------------------------
  // 信号
  //---------------------------------------------------------------------------
  // インターコネクト (DIRECT=1 ならこの interface の中で決める)
  logic                    hsel;
  // アドレスフェーズ (マネージャ)
  logic [ADDR_WIDTH-1:0]   haddr;
  logic [1:0]              htrans;
  logic                    hwrite;
  logic [2:0]              hsize;
  logic [2:0]              hburst;
  logic [HPROT_WIDTH-1:0]  hprot;
  logic                    hnonsec;
  logic                    hexcl;
  logic [MASTER_WIDTH-1:0] hmaster;
  logic                    hmastlock;
  // データフェーズ (マネージャ)
  logic [DATA_WIDTH-1:0]   hwdata;
  logic [DATA_WIDTH/8-1:0] hwstrb;
  // 応答 (サブオーディネート)
  logic                    hreadyout;
  logic                    hresp;
  logic [DATA_WIDTH-1:0]   hrdata;
  logic                    hexokay;
  // HREADY : マネージャと全てのサブオーディネートが見る転送の完了 (DIRECT=1 なら HREADYOUT)
  logic                    hready;

  //---------------------------------------------------------------------------
  // 直接つなぐとき (DIRECT=1) の HSEL / HREADY
  //---------------------------------------------------------------------------
  if( DIRECT ) begin : g_direct
    assign hsel   = 1'b1;
    assign hready = hreadyout;
  end

  //---------------------------------------------------------------------------
  // modport (合成用)
  //---------------------------------------------------------------------------
  modport mgr (
    output haddr
   ,output htrans
   ,output hwrite
   ,output hsize
   ,output hburst
   ,output hprot
   ,output hnonsec
   ,output hexcl
   ,output hmaster
   ,output hmastlock
   ,output hwdata
   ,output hwstrb
   ,input  hresp
   ,input  hrdata
   ,input  hexokay
   ,input  hready
  );

  modport sub (
    input  hsel
   ,input  haddr
   ,input  htrans
   ,input  hwrite
   ,input  hsize
   ,input  hburst
   ,input  hprot
   ,input  hnonsec
   ,input  hexcl
   ,input  hmaster
   ,input  hmastlock
   ,input  hwdata
   ,input  hwstrb
   ,output hreadyout
   ,output hresp
   ,output hrdata
   ,output hexokay
   ,input  hready
  );

  modport dec (
    output hsel
   ,output haddr
   ,output htrans
   ,output hwrite
   ,output hsize
   ,output hburst
   ,output hprot
   ,output hnonsec
   ,output hexcl
   ,output hmaster
   ,output hmastlock
   ,output hwdata
   ,output hwstrb
   ,input  hreadyout
   ,input  hresp
   ,input  hrdata
   ,input  hexokay
   ,output hready
  );

  modport mon (
    input hsel
   ,input haddr
   ,input htrans
   ,input hwrite
   ,input hsize
   ,input hburst
   ,input hprot
   ,input hnonsec
   ,input hexcl
   ,input hmaster
   ,input hmastlock
   ,input hwdata
   ,input hwstrb
   ,input hreadyout
   ,input hresp
   ,input hrdata
   ,input hexokay
   ,input hready
  );

`ifndef SYNTHESIS
  //---------------------------------------------------------------------------
  // TB 用 : clocking block と modport
  //   clocking block の出力は tb_* に書き、TB_ROLE で選んだ側だけ、tb_* を本物の信号につなぐ。
  //   (RTL がつながる信号を clocking block の出力にすると、同じ変数を 2 か所から駆動することになり、
  //    IEEE 1800 の規則に反する。RTL 同士をつなぐ interface (TB_ROLE=0) では tb_* は使われない)
  //---------------------------------------------------------------------------
  // verilator lint_off UNUSEDSIGNAL
  logic [ADDR_WIDTH-1:0]   tb_haddr = '0;
  logic [1:0]              tb_htrans = '0;
  logic                    tb_hwrite = '0;
  logic [2:0]              tb_hsize = '0;
  logic [2:0]              tb_hburst = '0;
  logic [HPROT_WIDTH-1:0]  tb_hprot = '0;
  logic                    tb_hnonsec = '0;
  logic                    tb_hexcl = '0;
  logic [MASTER_WIDTH-1:0] tb_hmaster = '0;
  logic                    tb_hmastlock = '0;
  logic [DATA_WIDTH-1:0]   tb_hwdata = '0;
  logic [DATA_WIDTH/8-1:0] tb_hwstrb = '0;
  logic                    tb_hreadyout = 1'b1;
  logic                    tb_hresp = '0;
  logic [DATA_WIDTH-1:0]   tb_hrdata = '0;
  logic                    tb_hexokay = '0;

  clocking mgr_cb @(posedge hclk);
    default input #1step output #100ps;
    output haddr     = tb_haddr;
    output htrans    = tb_htrans;
    output hwrite    = tb_hwrite;
    output hsize     = tb_hsize;
    output hburst    = tb_hburst;
    output hprot     = tb_hprot;
    output hnonsec   = tb_hnonsec;
    output hexcl     = tb_hexcl;
    output hmaster   = tb_hmaster;
    output hmastlock = tb_hmastlock;
    output hwdata    = tb_hwdata;
    output hwstrb    = tb_hwstrb;
    input  hresp;
    input  hrdata;
    input  hexokay;
    input  hready;
  endclocking

  clocking sub_cb @(posedge hclk);
    default input #1step output #100ps;
    input  hsel;
    input  haddr;
    input  htrans;
    input  hwrite;
    input  hsize;
    input  hburst;
    input  hprot;
    input  hnonsec;
    input  hexcl;
    input  hmaster;
    input  hmastlock;
    input  hwdata;
    input  hwstrb;
    output hreadyout = tb_hreadyout;
    output hresp     = tb_hresp;
    output hrdata    = tb_hrdata;
    output hexokay   = tb_hexokay;
    input  hready;
  endclocking

  clocking mon_cb @(posedge hclk);
    default input #1step;
    input hsel;
    input haddr;
    input htrans;
    input hwrite;
    input hsize;
    input hburst;
    input hprot;
    input hnonsec;
    input hexcl;
    input hmaster;
    input hmastlock;
    input hwdata;
    input hwstrb;
    input hreadyout;
    input hresp;
    input hrdata;
    input hexokay;
    input hready;
  endclocking

  // verilator lint_on UNUSEDSIGNAL

  modport mgr_tb (
    clocking mgr_cb
   ,input    hresetn
  );

  modport sub_tb (
    clocking sub_cb
   ,input    hresetn
  );

  modport mon_tb (
    clocking mon_cb
   ,input    hresetn
  );

  // TB_ROLE=1 (または 3) : TB がマネージャの信号を駆動する (mgr_cb)
  if( (TB_ROLE==1)||(TB_ROLE==3) ) begin : g_tb_mgr
    assign haddr     = tb_haddr;
    assign htrans    = tb_htrans;
    assign hwrite    = tb_hwrite;
    assign hsize     = tb_hsize;
    assign hburst    = tb_hburst;
    assign hprot     = tb_hprot;
    assign hnonsec   = tb_hnonsec;
    assign hexcl     = tb_hexcl;
    assign hmaster   = tb_hmaster;
    assign hmastlock = tb_hmastlock;
    assign hwdata    = tb_hwdata;
    assign hwstrb    = tb_hwstrb;
  end else begin : g_chk_mgr
    // TB_ROLE がマネージャをつながないとき、mgr_cb の出力を書いても信号は変わらない。書いたら警告する
    initial begin
      @({
        tb_haddr
       ,tb_htrans
       ,tb_hwrite
       ,tb_hsize
       ,tb_hburst
       ,tb_hprot
       ,tb_hnonsec
       ,tb_hexcl
       ,tb_hmaster
       ,tb_hmastlock
       ,tb_hwdata
       ,tb_hwstrb
      });
      $warning("ahb_if: mgr_cb was written, but TB_ROLE=%0d does not connect mgr_cb to the bus (use TB_ROLE=1 or 3)", TB_ROLE);
    end
  end

  // TB_ROLE=2 (または 3) : TB がサブオーディネートの信号を駆動する (sub_cb)
  if( (TB_ROLE==2)||(TB_ROLE==3) ) begin : g_tb_sub
    assign hreadyout = tb_hreadyout;
    assign hresp     = tb_hresp;
    assign hrdata    = tb_hrdata;
    assign hexokay   = tb_hexokay;
  end else begin : g_chk_sub
    // TB_ROLE がサブオーディネートをつながないとき、sub_cb の出力を書いても信号は変わらない。書いたら警告する
    initial begin
      @({
        tb_hreadyout
       ,tb_hresp
       ,tb_hrdata
       ,tb_hexokay
      });
      $warning("ahb_if: sub_cb was written, but TB_ROLE=%0d does not connect sub_cb to the bus (use TB_ROLE=2 or 3)", TB_ROLE);
    end
  end

  //---------------------------------------------------------------------------
  // プロトコルチェック (CHECK=1 のとき)
  //---------------------------------------------------------------------------
  localparam int unsigned OFSW       = $clog2(DATA_WIDTH/8);
  localparam logic [1:0]  TR_IDLE    = 2'b00;
  localparam logic [1:0]  TR_BUSY    = 2'b01;
  localparam logic [1:0]  TR_NONSEQ  = 2'b10;
  localparam logic [1:0]  TR_SEQ     = 2'b11;
  localparam logic [2:0]  BST_SINGLE = 3'b000;
  localparam logic [2:0]  BST_INCR   = 3'b001;

  // データフェーズの状態 (HREADY=1 のエッジで、そのアドレスフェーズを受け付ける)
  logic chk_dp_act;  // NONSEQ / SEQ のデータフェーズ
  logic chk_dp_wr;   // その転送が書き込み
  logic chk_dp_sel;  // このリンクのサブオーディネートが選ばれた NONSEQ / SEQ
  logic chk_dp_nop;  // このリンクのサブオーディネートが選ばれた IDLE / BUSY

  always @(posedge hclk or negedge hresetn) begin
    if( !hresetn ) begin
      chk_dp_act <= 1'b0;
      chk_dp_wr  <= 1'b0;
      chk_dp_sel <= 1'b0;
      chk_dp_nop <= 1'b0;
    end else if( hready ) begin
      chk_dp_act <= htrans[1];
      chk_dp_wr  <= htrans[1]&&hwrite;
      chk_dp_sel <= hsel&&htrans[1];
      chk_dp_nop <= hsel&&!htrans[1];
    end
  end

  // マネージャ : 待ち (HREADY=0) の間は NONSEQ / SEQ のアドレスフェーズを変えない。
  // ERROR の 1 サイクル目の後だけは IDLE にしてよい (IHI 0033C 3.7.1 / 3.7.2 / 3.6.2)
  a_wait_hold : assert property (@(posedge hclk) disable iff (!hresetn||!CHECK) !hready&&htrans[1] |=> $stable({htrans, haddr, hwrite, hsize, hburst, hprot, hnonsec, hexcl, hmaster, hmastlock})||($past(hresp)&&(htrans==TR_IDLE)))
  else begin
    $error("ahb_if: address phase changed during a wait state (IHI 0033C 3.7.1 / 3.7.2)");
  end
  // マネージャ : 固定長バーストの BUSY は、待ちの間に SEQ にだけ変えてよい (3.7.1)
  a_wait_busy : assert property (@(posedge hclk) disable iff (!hresetn||!CHECK) !hready&&!hresp&&(htrans==TR_BUSY)&&(hburst>BST_INCR) |=> (htrans==TR_BUSY)||(htrans==TR_SEQ))
  else begin
    $error("ahb_if: BUSY in a fixed-length burst changed to other than SEQ during a wait state (IHI 0033C 3.7.1)");
  end
  // マネージャ : 書き込みのデータフェーズの待ちの間は HWDATA / HWSTRB を変えない (6.1.1 / 2.2)
  a_wdata_hold : assert property (@(posedge hclk) disable iff (!hresetn||!CHECK) chk_dp_wr&&!hready |=> $stable({hwdata, hwstrb}))
  else begin
    $error("ahb_if: HWDATA / HWSTRB changed during a wait state (IHI 0033C 6.1.1)");
  end
  // マネージャ : HSIZE はデータ幅以下 (3.4)、アドレスは HSIZE にアライン (3.6)
  a_size : assert property (@(posedge hclk) disable iff (!hresetn||!CHECK) htrans[1] |-> hsize<=3'(OFSW))
  else begin
    $error("ahb_if: HSIZE exceeds the data bus width (IHI 0033C 3.4)");
  end
  a_align : assert property (@(posedge hclk) disable iff (!hresetn||!CHECK) htrans[1] |-> (64'(haddr)&((64'd1<<hsize)-64'd1))==64'd0)
  else begin
    $error("ahb_if: HADDR is not aligned to HSIZE (IHI 0033C 3.6)");
  end
  // リセット中 : マネージャは IDLE、サブオーディネートは HREADYOUT=1 (IHI 0033A 7.1.2)
  a_rst_trans : assert property (@(posedge hclk) disable iff (!CHECK) !hresetn |-> htrans==TR_IDLE)
  else begin
    $error("ahb_if: HTRANS must be IDLE during reset (IHI 0033A 7.1.2)");
  end
  a_rst_ready : assert property (@(posedge hclk) disable iff (!CHECK) !hresetn |-> hreadyout)
  else begin
    $error("ahb_if: HREADYOUT must be HIGH during reset (IHI 0033A 7.1.2)");
  end
  // サブオーディネート : IDLE / BUSY には待ち無しの OKAY (IHI 0033C 3.2)
  a_idle_okay : assert property (@(posedge hclk) disable iff (!hresetn||!CHECK) chk_dp_nop |-> hreadyout&&!hresp)
  else begin
    $error("ahb_if: IDLE / BUSY transfer did not get a zero wait state OKAY response (IHI 0033C 3.2)");
  end
  // サブオーディネート : ERROR は 2 サイクル (1 サイクル目 HREADYOUT=0、2 サイクル目 HREADYOUT=1) (5.1.3)
  a_err_2nd : assert property (@(posedge hclk) disable iff (!hresetn||!CHECK) chk_dp_sel&&hresp&&!hreadyout |=> hresp&&hreadyout)
  else begin
    $error("ahb_if: second cycle of the ERROR response is missing (IHI 0033C 5.1.3)");
  end
  a_err_1st : assert property (@(posedge hclk) disable iff (!hresetn||!CHECK) chk_dp_sel&&hresp&&hreadyout |-> $past(hresp&&!hreadyout))
  else begin
    $error("ahb_if: ERROR response with HREADYOUT HIGH but without the first cycle (IHI 0033C 5.1.3)");
  end

  // X / Z
  a_x_ctrl : assert property (@(posedge hclk) disable iff (!hresetn||!CHECK) !$isunknown({hsel, htrans, hready}))
  else begin
    $error("ahb_if: HSEL / HTRANS / HREADY is X or Z");
  end
  a_x_addr : assert property (@(posedge hclk) disable iff (!hresetn||!CHECK) htrans[1] |-> !$isunknown({haddr, hwrite, hsize, hburst, hprot, hnonsec, hexcl, hmaster, hmastlock}))
  else begin
    $error("ahb_if: address phase is X or Z");
  end
  a_x_resp : assert property (@(posedge hclk) disable iff (!hresetn||!CHECK) chk_dp_sel |-> !$isunknown({hreadyout, hresp}))
  else begin
    $error("ahb_if: HREADYOUT / HRESP is X or Z in the data phase");
  end

  //---------------------------------------------------------------------------
  // バースト : SEQ はバーストの中だけ、アドレスは前の転送の続き、制御は先頭と同じ、
  // 固定長バーストのビート数、1KB 境界 (IHI 0033C 3.2 Table 3-1 / 3.6 / 3.6.2)
  //---------------------------------------------------------------------------
  localparam int unsigned CTRLW = 1+3+3+HPROT_WIDTH+1+1+MASTER_WIDTH+1;

  logic                  chk_bst_act;   // バーストの途中
  logic [2:0]            chk_bst_burst;
  int unsigned           chk_bst_left;  // 固定長バーストの残りのビート数
  logic                  chk_bst_err;   // このバーストで ERROR を受けた
  logic [ADDR_WIDTH-1:0] chk_bst_addr;  // 直前の転送のアドレス
  logic [CTRLW-1:0]      chk_bst_ctrl;  // 先頭の転送の制御信号

  // 固定長バーストのビート数 (SINGLE は 1、INCR は 0 = 未定義)
  function automatic int unsigned chk_beats(input logic [2:0] burst);
    case( burst )
      3'b000 : begin
        return 1;
      end
      3'b010, 3'b011 : begin
        return 4;
      end
      3'b100, 3'b101 : begin
        return 8;
      end
      3'b110, 3'b111 : begin
        return 16;
      end
      default : begin
        return 0;
      end
    endcase
  endfunction

  // バーストの次の転送のアドレス (WRAP4 / WRAP8 / WRAP16 は折り返す)
  function automatic logic [ADDR_WIDTH-1:0] chk_next(input logic [ADDR_WIDTH-1:0] a, input logic [2:0] size, input logic [2:0] burst);
    logic [ADDR_WIDTH-1:0] nb;
    logic [ADDR_WIDTH-1:0] wm;
    nb = ADDR_WIDTH'(1)<<size;
    wm = '1;
    if( !burst[0]&&(burst!=BST_SINGLE) ) begin
      wm = (nb*ADDR_WIDTH'(chk_beats(burst)))-1'b1;
    end
    return (a&~wm)|((a+nb)&wm);
  endfunction

  function automatic void chk_clear();
    chk_bst_act   = 1'b0;
    chk_bst_burst = '0;
    chk_bst_left  = 0;
    chk_bst_err   = 1'b0;
    chk_bst_addr  = '0;
    chk_bst_ctrl  = '0;
  endfunction

  function automatic void chk_update();
    logic [CTRLW-1:0] ctrl;
    logic [63:0]      last;
    ctrl = {hwrite, hsize, hburst, hprot, hnonsec, hexcl, hmaster, hmastlock};
    if( chk_dp_act&&hresp ) begin
      chk_bst_err = 1'b1;
    end
    if( hready ) begin
      if( (htrans==TR_IDLE)||(htrans==TR_NONSEQ) ) begin
        if( chk_bst_act&&(chk_bst_left!=0)&&!chk_bst_err ) begin
          $error("ahb_if: fixed-length burst ended with %0d beats left (IHI 0033C 3.6.2)", chk_bst_left);
        end
        chk_bst_act = 1'b0;
      end
      if( (htrans==TR_BUSY)&&!chk_bst_act ) begin
        $error("ahb_if: BUSY outside a burst (IHI 0033C 3.2)");
      end
      if( htrans==TR_NONSEQ ) begin
        chk_bst_act   = (hburst!=BST_SINGLE);
        chk_bst_burst = hburst;
        chk_bst_left  = (chk_beats(hburst)==0) ? 0 : chk_beats(hburst)-1;
        chk_bst_err   = 1'b0;
        chk_bst_addr  = haddr;
        chk_bst_ctrl  = ctrl;
        // 固定長の INCR は 1KB 境界をまたがない
        if( hburst[0]&&(hburst!=BST_INCR) ) begin
          last = (64'(haddr)&64'h3FF)+(64'(chk_beats(hburst))<<hsize)-64'd1;
          if( last>64'h3FF ) begin
            $error("ahb_if: INCR%0d burst crosses a 1KB boundary (IHI 0033C 3.6)", chk_beats(hburst));
          end
        end
      end
      if( htrans==TR_SEQ ) begin
        if( !chk_bst_act ) begin
          $error("ahb_if: SEQ outside a burst (IHI 0033C 3.2)");
        end else begin
          if( ctrl!=chk_bst_ctrl ) begin
            $error("ahb_if: control signals changed within a burst (IHI 0033C 3.2)");
          end
          if( haddr!=chk_next(chk_bst_addr,chk_bst_ctrl[CTRLW-2-:3],chk_bst_burst) ) begin
            $error("ahb_if: SEQ address %0h is not the next address of the burst (previous %0h) (IHI 0033C 3.6)", haddr, chk_bst_addr);
          end
          if( (chk_bst_burst==BST_INCR)&&((64'(haddr)>>10)!=(64'(chk_bst_addr)>>10)) ) begin
            $error("ahb_if: INCR burst crosses a 1KB boundary (IHI 0033C 3.6)");
          end
          if( chk_bst_burst!=BST_INCR ) begin
            if( chk_bst_left==0 ) begin
              $error("ahb_if: too many beats in a fixed-length burst (IHI 0033C 3.6)");
            end else begin
              chk_bst_left = chk_bst_left-1;
            end
          end
          chk_bst_addr = haddr;
        end
      end
    end
  endfunction

  always @(posedge hclk or negedge hresetn) begin
    if( !hresetn ) begin
      chk_clear();
    end else if( CHECK ) begin
      chk_update();
    end
  end
`else
  // 合成では hclk / hresetn / CHECK / TB_ROLE を使わない (未使用の警告を避けるだけで、論理は残らない)
  wire unused_ok = &{1'b0, hclk, hresetn, CHECK, (TB_ROLE!=0)};
`endif

endinterface
