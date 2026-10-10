//=============================================================================
// tb_axil_master_mem.sv
//-----------------------------------------------------------------------------
//  axil_master_mem (+ axil_to_axi4) のテストベンチ (自己チェック)。
//
//  構成:
//    書き込みコマンド / 読み出しコマンド / ローカルポートの操作 (別プロセスで同時に出せる)
//      --> axil_master_mem --(AXI4-Lite)--> axil_to_axi4 --(AXI4)--> axil_slave_mem_model
//
//  チェック:
//    - コマンドごと: バス上のトランザクションの列 (アドレス / PROT / データ / WSTRB / 応答)、
//      done_count / err_flags / err_index / done_err、内部メモリとスレーブのメモリの内容
//    - STOP_ON_ERROR=1 でエラー応答を受けたとき: done_count が err_index+1 .. err_index+MAX_*_OUTSTANDING
//      (理想的なスレーブでは「エラー応答を受けたサイクルで止まる」ときの数と一致すること)
//    - 理想的なスレーブ (READY が常に 1、応答の遅延 0) で、受付から done までのサイクル数が
//        書き込み 7 + f(n-1) / 読み出し 5 + f(n-1) / 転送しないコマンド 1
//        (n = 出したトランザクション数、f(i) = i (MAX>=3)、3*(i/MAX) + i%MAX (MAX<3))
//    - 常時 (モニタ): ready / busy / done の関係、done は 1 サイクル、ステータスは次の受付まで保持、
//      ローカルポートの ready (書き込みポートは読み出しコマンド中 0 / 読み出しポートは書き込みコマンド中 0)、
//      mem_r_rvalid、axil_to_axi4 の固定値、AWAKEUP (AxVALID や未完了があれば 1、両方アイドルなら 0)
//    - 最後に: スレーブモデルのプロトコル違反 0 件、非アライン 0 件、
//      内部メモリモデルの範囲外アクセス 0 件 / 同じアドレスの同時読み書き 0 件
//
//  parameter は Verilator の -G で上書きできる。
//=============================================================================
`timescale 1ns / 1ps

module tb_axil_master_mem #(
  parameter int unsigned ADDR_WIDTH         = 32
 ,parameter int unsigned DATA_WIDTH         = 32
 ,parameter int unsigned MEM_DEPTH          = 16
 ,parameter int unsigned MAX_WR_OUTSTANDING = 4
 ,parameter int unsigned MAX_RD_OUTSTANDING = 4
 ,parameter bit          STOP_ON_ERROR      = 1'b1
 ,parameter int unsigned N_RAND             = 240
);

  localparam int unsigned     STRB_W      = DATA_WIDTH / 8;
  localparam int unsigned     STRB_LSB    = $clog2(STRB_W);
  localparam int unsigned     MEM_AW      = (MEM_DEPTH<2) ? 1 : $clog2(MEM_DEPTH);
  localparam int unsigned     LEN_W       = $clog2(MEM_DEPTH+1);
  localparam int unsigned     ID_W        = 3;
  localparam logic [3:0]      QOS         = 4'b1010;
  localparam logic [2:0]      SIZE_FULL   = 3'(STRB_LSB);
  // アドレス空間のワード数
  localparam longint unsigned SPACE_WORDS = 64'd1 << (ADDR_WIDTH-STRB_LSB);
  // 書き込み用 / 読み出し用の窓 (スレーブのワード位置)。同時に動くコマンドが触る場所を分ける
  //   アドレス空間が広ければ、上位ビットが 1 になる位置 (空間の中央) に置く
  localparam longint unsigned WIN         = ((SPACE_WORDS/2)<64'(MEM_DEPTH)) ? (SPACE_WORDS/2) : 64'(MEM_DEPTH);
  localparam longint unsigned WB          = (SPACE_WORDS>=(4*WIN)) ? (SPACE_WORDS/2) : 64'd0;
  localparam longint unsigned RB          = WB + WIN;
  localparam int unsigned     LWIN        = int'(WIN);
  // 内部メモリを、書き込みコマンド用 [0, MH) と読み出しコマンド用 [MH, MEM_DEPTH) に分けるときの境目
  localparam int unsigned     MH          = MEM_DEPTH / 2;
  // ローカルポートのアドレスで MEM_DEPTH 以上を出せる
  localparam bit              LOC_OOR     = ((64'd1<<MEM_AW)>64'(MEM_DEPTH));
  localparam int unsigned     LEN_MAXV    = (1<<LEN_W) - 1;
  localparam int unsigned     HANG_LIMIT  = 200000;

  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_EXOKAY = 2'b01;
  localparam logic [1:0] RESP_SLVERR = 2'b10;
  localparam logic [1:0] RESP_DECERR = 2'b11;

  //---------------------------------------------------------------------------
  // クロック / リセット
  //---------------------------------------------------------------------------
  logic aclk;
  logic aresetn;

  initial begin
    aclk = 1'b0;
    forever begin
      #5 aclk = ~aclk;
    end
  end

  //---------------------------------------------------------------------------
  // DUT の信号
  //---------------------------------------------------------------------------
  logic                  wcmd_valid;
  logic                  wcmd_ready;
  logic [ADDR_WIDTH-1:0] wcmd_addr;
  logic                  wcmd_incr;
  logic [MEM_AW-1:0]     wcmd_mem_addr;
  logic [LEN_W-1:0]      wcmd_len;
  logic [STRB_W-1:0]     wcmd_strb;
  logic [2:0]            wcmd_prot;
  logic                  wr_busy;
  logic                  wr_done;
  logic                  wr_done_err;
  logic [3:0]            wr_err_flags;
  logic [LEN_W-1:0]      wr_err_index;
  logic [LEN_W-1:0]      wr_done_count;
  logic                  rcmd_valid;
  logic                  rcmd_ready;
  logic [ADDR_WIDTH-1:0] rcmd_addr;
  logic                  rcmd_incr;
  logic [MEM_AW-1:0]     rcmd_mem_addr;
  logic [LEN_W-1:0]      rcmd_len;
  logic [2:0]            rcmd_prot;
  logic                  rd_busy;
  logic                  rd_done;
  logic                  rd_done_err;
  logic [3:0]            rd_err_flags;
  logic [LEN_W-1:0]      rd_err_index;
  logic [LEN_W-1:0]      rd_done_count;
  logic                  mem_w_valid;
  logic                  mem_w_ready;
  logic [MEM_AW-1:0]     mem_w_addr;
  logic [DATA_WIDTH-1:0] mem_w_data;
  logic                  mem_r_valid;
  logic                  mem_r_ready;
  logic [MEM_AW-1:0]     mem_r_addr;
  logic                  mem_r_rvalid;
  logic [DATA_WIDTH-1:0] mem_r_rdata;
  logic                  axi_wakeup;
  // AXI4-Lite (DUT -> axil_to_axi4)
  logic [ADDR_WIDTH-1:0] l_awaddr;
  logic [2:0]            l_awprot;
  logic                  l_awvalid;
  logic                  l_awready;
  logic [DATA_WIDTH-1:0] l_wdata;
  logic [STRB_W-1:0]     l_wstrb;
  logic                  l_wvalid;
  logic                  l_wready;
  logic [1:0]            l_bresp;
  logic                  l_bvalid;
  logic                  l_bready;
  logic [ADDR_WIDTH-1:0] l_araddr;
  logic [2:0]            l_arprot;
  logic                  l_arvalid;
  logic                  l_arready;
  logic [DATA_WIDTH-1:0] l_rdata;
  logic [1:0]            l_rresp;
  logic                  l_rvalid;
  logic                  l_rready;
  // AXI4 (axil_to_axi4 -> スレーブモデル)
  logic [ID_W-1:0]       a_awid;
  logic [ADDR_WIDTH-1:0] a_awaddr;
  logic [7:0]            a_awlen;
  logic [2:0]            a_awsize;
  logic [1:0]            a_awburst;
  logic                  a_awlock;
  logic [3:0]            a_awcache;
  logic [2:0]            a_awprot;
  logic [3:0]            a_awqos;
  logic                  a_awvalid;
  logic                  a_awready;
  logic [DATA_WIDTH-1:0] a_wdata;
  logic [STRB_W-1:0]     a_wstrb;
  logic                  a_wlast;
  logic                  a_wvalid;
  logic                  a_wready;
  logic [ID_W-1:0]       a_bid;
  logic [1:0]            a_bresp;
  logic                  a_bvalid;
  logic                  a_bready;
  logic [ID_W-1:0]       a_arid;
  logic [ADDR_WIDTH-1:0] a_araddr;
  logic [7:0]            a_arlen;
  logic [2:0]            a_arsize;
  logic [1:0]            a_arburst;
  logic                  a_arlock;
  logic [3:0]            a_arcache;
  logic [2:0]            a_arprot;
  logic [3:0]            a_arqos;
  logic                  a_arvalid;
  logic                  a_arready;
  logic [ID_W-1:0]       a_rid;
  logic [DATA_WIDTH-1:0] a_rdata;
  logic [1:0]            a_rresp;
  logic                  a_rlast;
  logic                  a_rvalid;
  logic                  a_rready;
  logic                  a_awakeup;

  //---------------------------------------------------------------------------
  // DUT
  //---------------------------------------------------------------------------
  axil_master_mem #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.MEM_DEPTH(MEM_DEPTH)
   ,.MAX_WR_OUTSTANDING(MAX_WR_OUTSTANDING)
   ,.MAX_RD_OUTSTANDING(MAX_RD_OUTSTANDING)
   ,.STOP_ON_ERROR(STOP_ON_ERROR)
  ) u_dut (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.wcmd_valid(wcmd_valid)
   ,.wcmd_ready(wcmd_ready)
   ,.wcmd_addr(wcmd_addr)
   ,.wcmd_incr(wcmd_incr)
   ,.wcmd_mem_addr(wcmd_mem_addr)
   ,.wcmd_len(wcmd_len)
   ,.wcmd_strb(wcmd_strb)
   ,.wcmd_prot(wcmd_prot)
   ,.wr_busy(wr_busy)
   ,.wr_done(wr_done)
   ,.wr_done_err(wr_done_err)
   ,.wr_err_flags(wr_err_flags)
   ,.wr_err_index(wr_err_index)
   ,.wr_done_count(wr_done_count)
   ,.rcmd_valid(rcmd_valid)
   ,.rcmd_ready(rcmd_ready)
   ,.rcmd_addr(rcmd_addr)
   ,.rcmd_incr(rcmd_incr)
   ,.rcmd_mem_addr(rcmd_mem_addr)
   ,.rcmd_len(rcmd_len)
   ,.rcmd_prot(rcmd_prot)
   ,.rd_busy(rd_busy)
   ,.rd_done(rd_done)
   ,.rd_done_err(rd_done_err)
   ,.rd_err_flags(rd_err_flags)
   ,.rd_err_index(rd_err_index)
   ,.rd_done_count(rd_done_count)
   ,.mem_w_valid(mem_w_valid)
   ,.mem_w_ready(mem_w_ready)
   ,.mem_w_addr(mem_w_addr)
   ,.mem_w_data(mem_w_data)
   ,.mem_r_valid(mem_r_valid)
   ,.mem_r_ready(mem_r_ready)
   ,.mem_r_addr(mem_r_addr)
   ,.mem_r_rvalid(mem_r_rvalid)
   ,.mem_r_rdata(mem_r_rdata)
   ,.axi_wakeup(axi_wakeup)
   ,.m_axi_awaddr(l_awaddr)
   ,.m_axi_awprot(l_awprot)
   ,.m_axi_awvalid(l_awvalid)
   ,.m_axi_awready(l_awready)
   ,.m_axi_wdata(l_wdata)
   ,.m_axi_wstrb(l_wstrb)
   ,.m_axi_wvalid(l_wvalid)
   ,.m_axi_wready(l_wready)
   ,.m_axi_bresp(l_bresp)
   ,.m_axi_bvalid(l_bvalid)
   ,.m_axi_bready(l_bready)
   ,.m_axi_araddr(l_araddr)
   ,.m_axi_arprot(l_arprot)
   ,.m_axi_arvalid(l_arvalid)
   ,.m_axi_arready(l_arready)
   ,.m_axi_rdata(l_rdata)
   ,.m_axi_rresp(l_rresp)
   ,.m_axi_rvalid(l_rvalid)
   ,.m_axi_rready(l_rready)
  );

  //---------------------------------------------------------------------------
  // AXI4-Lite -> AXI4 (NI-700 などにつなぐときの変換。ここではスレーブモデルの前に入れて確認する)
  //---------------------------------------------------------------------------
  axil_to_axi4 #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.ID_WIDTH(ID_W)
   ,.QOS(QOS)
  ) u_conv (
    .s_axi_awaddr(l_awaddr)
   ,.s_axi_awprot(l_awprot)
   ,.s_axi_awvalid(l_awvalid)
   ,.s_axi_awready(l_awready)
   ,.s_axi_wdata(l_wdata)
   ,.s_axi_wstrb(l_wstrb)
   ,.s_axi_wvalid(l_wvalid)
   ,.s_axi_wready(l_wready)
   ,.s_axi_bresp(l_bresp)
   ,.s_axi_bvalid(l_bvalid)
   ,.s_axi_bready(l_bready)
   ,.s_axi_araddr(l_araddr)
   ,.s_axi_arprot(l_arprot)
   ,.s_axi_arvalid(l_arvalid)
   ,.s_axi_arready(l_arready)
   ,.s_axi_rdata(l_rdata)
   ,.s_axi_rresp(l_rresp)
   ,.s_axi_rvalid(l_rvalid)
   ,.s_axi_rready(l_rready)
   ,.s_axi_wakeup(axi_wakeup)
   ,.m_axi_awid(a_awid)
   ,.m_axi_awaddr(a_awaddr)
   ,.m_axi_awlen(a_awlen)
   ,.m_axi_awsize(a_awsize)
   ,.m_axi_awburst(a_awburst)
   ,.m_axi_awlock(a_awlock)
   ,.m_axi_awcache(a_awcache)
   ,.m_axi_awprot(a_awprot)
   ,.m_axi_awqos(a_awqos)
   ,.m_axi_awvalid(a_awvalid)
   ,.m_axi_awready(a_awready)
   ,.m_axi_wdata(a_wdata)
   ,.m_axi_wstrb(a_wstrb)
   ,.m_axi_wlast(a_wlast)
   ,.m_axi_wvalid(a_wvalid)
   ,.m_axi_wready(a_wready)
   ,.m_axi_bid(a_bid)
   ,.m_axi_bresp(a_bresp)
   ,.m_axi_bvalid(a_bvalid)
   ,.m_axi_bready(a_bready)
   ,.m_axi_arid(a_arid)
   ,.m_axi_araddr(a_araddr)
   ,.m_axi_arlen(a_arlen)
   ,.m_axi_arsize(a_arsize)
   ,.m_axi_arburst(a_arburst)
   ,.m_axi_arlock(a_arlock)
   ,.m_axi_arcache(a_arcache)
   ,.m_axi_arprot(a_arprot)
   ,.m_axi_arqos(a_arqos)
   ,.m_axi_arvalid(a_arvalid)
   ,.m_axi_arready(a_arready)
   ,.m_axi_rid(a_rid)
   ,.m_axi_rdata(a_rdata)
   ,.m_axi_rresp(a_rresp)
   ,.m_axi_rlast(a_rlast)
   ,.m_axi_rvalid(a_rvalid)
   ,.m_axi_rready(a_rready)
   ,.m_axi_awakeup(a_awakeup)
  );

  // BID / RID / RLAST は変換で使わないので、乱数を入れておく (見ていないことの確認)
  always @(posedge aclk) begin
    a_bid   <= ID_W'($urandom());
    a_rid   <= ID_W'($urandom());
    a_rlast <= 1'($urandom());
  end

  //---------------------------------------------------------------------------
  // スレーブ
  //---------------------------------------------------------------------------
  axil_slave_mem_model #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.MAX_WR_OUTSTANDING(MAX_WR_OUTSTANDING)
   ,.MAX_RD_OUTSTANDING(MAX_RD_OUTSTANDING)
  ) u_slv (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.awaddr(a_awaddr)
   ,.awprot(a_awprot)
   ,.awvalid(a_awvalid)
   ,.awready(a_awready)
   ,.wdata(a_wdata)
   ,.wstrb(a_wstrb)
   ,.wvalid(a_wvalid)
   ,.wready(a_wready)
   ,.bresp(a_bresp)
   ,.bvalid(a_bvalid)
   ,.bready(a_bready)
   ,.araddr(a_araddr)
   ,.arprot(a_arprot)
   ,.arvalid(a_arvalid)
   ,.arready(a_arready)
   ,.rdata(a_rdata)
   ,.rresp(a_rresp)
   ,.rvalid(a_rvalid)
   ,.rready(a_rready)
  );

  //---------------------------------------------------------------------------
  // エラー集計
  //---------------------------------------------------------------------------
  int unsigned err_cnt = 0;
  int unsigned mon_err_cnt = 0;
  int unsigned cyc = 0;

  task automatic tb_error( input string msg );
    err_cnt++;
    $display("[%0t] [ERROR] %s", $time, msg);
  endtask

  function automatic void mon_error( input string msg );
    mon_err_cnt++;
    $display("[%0t] [ERROR] (monitor) %s", $time, msg);
  endfunction

  task automatic abort_test( input string msg );
    $display("[%0t] [ERROR] %s", $time, msg);
    $display("=== tb_axil_master_mem : TEST FAILED (aborted) ===");
    $finish;
  endtask

  always @(posedge aclk) begin
    cyc <= cyc + 1;
  end

  //---------------------------------------------------------------------------
  // 期待値 / 共通の関数
  //---------------------------------------------------------------------------
  bit [DATA_WIDTH-1:0] ref_mem [MEM_DEPTH];            // 内部メモリの期待値
  bit [DATA_WIDTH-1:0] exp_smem [bit [63:0]];          // スレーブのメモリの期待値 (キーはワード先頭のアドレス)
  bit                  ideal;                          // スレーブが理想的 (READY が常に 1、遅延 0)

  function automatic bit [DATA_WIDTH-1:0] f_rand_data();
    bit [DATA_WIDTH-1:0] d;
    for( int unsigned i=0; i<DATA_WIDTH; i++ ) begin
      d[i] = 1'($urandom());
    end
    return d;
  endfunction

  // ワード位置 -> アドレス
  function automatic bit [ADDR_WIDTH-1:0] f_waddr( input longint unsigned w );
    return ADDR_WIDTH'(w << STRB_LSB);
  endfunction

  // コマンドの i 番目のトランザクションのアドレス
  function automatic bit [ADDR_WIDTH-1:0] f_xaddr( input bit [ADDR_WIDTH-1:0] addr, input bit incr, input int unsigned i );
    if( incr ) begin
      return addr + ADDR_WIDTH'(64'(i) << STRB_LSB);
    end
    return addr;
  endfunction

  function automatic bit [DATA_WIDTH-1:0] f_smem( input bit [63:0] a );
    if( exp_smem.exists(a) ) begin
      return exp_smem[a];
    end
    return {DATA_WIDTH{1'b0}};
  endfunction

  function automatic int unsigned f_min( input int unsigned a, input int unsigned b );
    return (a<b) ? a : b;
  endfunction

  // コマンドの誤り (RTL とは別の書き方で求める)
  function automatic bit f_cmd_bad( input bit [ADDR_WIDTH-1:0] addr, input bit incr, input int unsigned maddr, input int unsigned len );
    longint unsigned w;
    bit              mem_bad;
    bit              align_bad;
    bit              range_bad;
    w         = 64'(addr) >> STRB_LSB;
    mem_bad   = ((64'(maddr) + 64'(len))>64'(MEM_DEPTH));
    align_bad = ((64'(addr) % 64'(STRB_W))!=64'd0);
    range_bad = incr&&(64'(len)>(SPACE_WORDS - w));
    return mem_bad||align_bad||range_bad;
  endfunction

  // 理想的なスレーブで、i 番目のトランザクションをエンジンが受け付けるサイクル (最初から数えて)
  function automatic int unsigned f_acc( input int unsigned i, input int unsigned max_out );
    if( max_out>=3 ) begin
      return i;
    end
    return (3 * (i / max_out)) + (i % max_out);
  endfunction

  // 理想的なスレーブで、k 番目がエラー応答のときに出るトランザクション数
  //   (エラー応答を受けたサイクルから止めるので、受付が f(k)+2 サイクル目までのもの)
  function automatic int unsigned f_stop_cnt( input int unsigned k, input int unsigned len, input int unsigned max_out );
    int unsigned n;
    n = 0;
    for( int unsigned j=0; j<len; j++ ) begin
      if( f_acc(j,max_out)<=(f_acc(k,max_out)+2) ) begin
        n++;
      end
    end
    return n;
  endfunction

  // done_count の範囲
  task automatic calc_nrange
  (
    input  int unsigned n
   ,input  int unsigned k
   ,input  int unsigned max_out
   ,input  bit          idl
   ,output int unsigned nmin
   ,output int unsigned nmax
  );
    if( STOP_ON_ERROR&&(k<n) ) begin
      if( idl ) begin
        nmin = f_stop_cnt(k, n, max_out);
        nmax = nmin;
      end else begin
        nmin = k + 1;
        nmax = f_min(k + max_out, n);
      end
    end else begin
      nmin = n;
      nmax = n;
    end
  endtask

  //---------------------------------------------------------------------------
  // 常時モニタ (posedge でサンプル = 終わったサイクルの値)
  //---------------------------------------------------------------------------
  logic             wr_done_q;
  logic             rd_done_q;
  logic             exp_rvalid_q;
  // done のときのステータス (次の受付まで変わらないこと)
  logic [3:0]       w_hold_flags;
  logic             w_hold_err;
  logic [LEN_W-1:0] w_hold_index;
  logic [LEN_W-1:0] w_hold_count;
  logic [3:0]       r_hold_flags;
  logic             r_hold_err;
  logic [LEN_W-1:0] r_hold_index;
  logic [LEN_W-1:0] r_hold_count;
  int unsigned      n_both_busy = 0;      // 書き込みと読み出しのコマンドが同時に実行中だったサイクル数

  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      wr_done_q    <= 1'b0;
      rd_done_q    <= 1'b0;
      exp_rvalid_q <= 1'b0;
      w_hold_flags <= 4'b0000;
      w_hold_err   <= 1'b0;
      w_hold_index <= {LEN_W{1'b0}};
      w_hold_count <= {LEN_W{1'b0}};
      r_hold_flags <= 4'b0000;
      r_hold_err   <= 1'b0;
      r_hold_index <= {LEN_W{1'b0}};
      r_hold_count <= {LEN_W{1'b0}};
    end else begin
      wr_done_q    <= wr_done;
      rd_done_q    <= rd_done;
      exp_rvalid_q <= mem_r_valid&&mem_r_ready;
      if( wr_done ) begin
        w_hold_flags <= wr_err_flags;
        w_hold_err   <= wr_done_err;
        w_hold_index <= wr_err_index;
        w_hold_count <= wr_done_count;
      end
      if( rd_done ) begin
        r_hold_flags <= rd_err_flags;
        r_hold_err   <= rd_done_err;
        r_hold_index <= rd_err_index;
        r_hold_count <= rd_done_count;
      end
      if( wr_busy&&rd_busy ) begin
        n_both_busy++;
      end
      // コマンドの ready / busy、ローカルポートの ready
      if( wcmd_ready!==!wr_busy ) begin
        mon_error($sformatf("wcmd_ready=%b wr_busy=%b", wcmd_ready, wr_busy));
      end
      if( rcmd_ready!==!rd_busy ) begin
        mon_error($sformatf("rcmd_ready=%b rd_busy=%b", rcmd_ready, rd_busy));
      end
      if( mem_w_ready!==!rd_busy ) begin
        mon_error($sformatf("mem_w_ready=%b rd_busy=%b (local writes are blocked only while a read command runs)", mem_w_ready, rd_busy));
      end
      if( mem_r_ready!==!wr_busy ) begin
        mon_error($sformatf("mem_r_ready=%b wr_busy=%b (local reads are blocked only while a write command runs)", mem_r_ready, wr_busy));
      end
      // done
      if( wr_done&&!wr_busy ) begin
        mon_error("wr_done=1 while wr_busy=0");
      end
      if( rd_done&&!rd_busy ) begin
        mon_error("rd_done=1 while rd_busy=0");
      end
      if( wr_done&&wr_done_q ) begin
        mon_error("wr_done is longer than 1 cycle");
      end
      if( rd_done&&rd_done_q ) begin
        mon_error("rd_done is longer than 1 cycle");
      end
      if( wr_done&&(wr_done_err!==(|wr_err_flags)) ) begin
        mon_error($sformatf("wr_done_err=%b wr_err_flags=%b", wr_done_err, wr_err_flags));
      end
      if( rd_done&&(rd_done_err!==(|rd_err_flags)) ) begin
        mon_error($sformatf("rd_done_err=%b rd_err_flags=%b", rd_done_err, rd_err_flags));
      end
      // ステータスの保持
      if( !wr_busy&&((wr_err_flags!==w_hold_flags)||(wr_done_err!==w_hold_err)||(wr_err_index!==w_hold_index)||(wr_done_count!==w_hold_count)) ) begin
        mon_error($sformatf("write status changed while idle : flags=%b err=%b index=%0d count=%0d (at done %b %b %0d %0d)", wr_err_flags, wr_done_err, wr_err_index, wr_done_count, w_hold_flags, w_hold_err, w_hold_index, w_hold_count));
      end
      if( !rd_busy&&((rd_err_flags!==r_hold_flags)||(rd_done_err!==r_hold_err)||(rd_err_index!==r_hold_index)||(rd_done_count!==r_hold_count)) ) begin
        mon_error($sformatf("read status changed while idle : flags=%b err=%b index=%0d count=%0d (at done %b %b %0d %0d)", rd_err_flags, rd_done_err, rd_err_index, rd_done_count, r_hold_flags, r_hold_err, r_hold_index, r_hold_count));
      end
      // ローカル読み出しのデータは受け付けた次のサイクル
      if( mem_r_rvalid!==exp_rvalid_q ) begin
        mon_error($sformatf("mem_r_rvalid=%b (exp %b)", mem_r_rvalid, exp_rvalid_q));
      end
      // バス
      if( !wr_busy&&(l_awvalid||l_wvalid) ) begin
        mon_error($sformatf("AWVALID=%b WVALID=%b while wr_busy=0", l_awvalid, l_wvalid));
      end
      if( !rd_busy&&l_arvalid ) begin
        mon_error("ARVALID=1 while rd_busy=0");
      end
      if( (l_bready!==1'b1)||(l_rready!==1'b1) ) begin
        mon_error($sformatf("BREADY=%b RREADY=%b (expected to be always 1)", l_bready, l_rready));
      end
      // axil_to_axi4 の固定値
      if( (a_awid!={ID_W{1'b0}})||(a_awlen!=8'd0)||(a_awsize!=SIZE_FULL)||(a_awburst!=2'b01)||(a_awlock!=1'b0)||(a_awcache!=4'b0000)||(a_awqos!=QOS)||(a_wlast!=1'b1) ) begin
        mon_error($sformatf("axil_to_axi4 : AWID=%0d AWLEN=%0d AWSIZE=%0d AWBURST=%b AWLOCK=%b AWCACHE=%b AWQOS=%b WLAST=%b", a_awid, a_awlen, a_awsize, a_awburst, a_awlock, a_awcache, a_awqos, a_wlast));
      end
      if( (a_arid!={ID_W{1'b0}})||(a_arlen!=8'd0)||(a_arsize!=SIZE_FULL)||(a_arburst!=2'b01)||(a_arlock!=1'b0)||(a_arcache!=4'b0000)||(a_arqos!=QOS) ) begin
        mon_error($sformatf("axil_to_axi4 : ARID=%0d ARLEN=%0d ARSIZE=%0d ARBURST=%b ARLOCK=%b ARCACHE=%b ARQOS=%b", a_arid, a_arlen, a_arsize, a_arburst, a_arlock, a_arcache, a_arqos));
      end
      if( a_awakeup!==axi_wakeup ) begin
        mon_error($sformatf("axil_to_axi4 : AWAKEUP=%b axi_wakeup=%b", a_awakeup, axi_wakeup));
      end
    end
  end

  // AWAKEUP は negedge で見る (スレーブモデルの未完了数は posedge で更新されるため)
  always @(negedge aclk) begin
    if( aresetn ) begin
      if( (a_awvalid||a_wvalid||a_arvalid)&&!a_awakeup ) begin
        mon_error($sformatf("AWAKEUP=0 while AWVALID=%b WVALID=%b ARVALID=%b", a_awvalid, a_wvalid, a_arvalid));
      end
      if( ((u_slv.wr_out!=0)||(u_slv.w_out!=0)||(u_slv.rd_out!=0)||a_bvalid||a_rvalid)&&!a_awakeup ) begin
        mon_error($sformatf("AWAKEUP=0 with transactions outstanding on the bus (AW %0d / W %0d / AR %0d)", u_slv.wr_out, u_slv.w_out, u_slv.rd_out));
      end
      if( !wr_busy&&!rd_busy&&a_awakeup ) begin
        mon_error("AWAKEUP=1 while both commands are idle");
      end
    end
  end

  //---------------------------------------------------------------------------
  // ローカルポート
  //   どのタスクも negedge で入り、negedge で戻る。ready はレジスタで決まるので、
  //   negedge で見た値で次の posedge の受付が決まる
  //---------------------------------------------------------------------------
  int unsigned l_wacc_cyc;
  int unsigned l_racc_cyc;
  int unsigned n_loc_wr = 0;
  int unsigned n_loc_rd = 0;

  task automatic mem_wr( input int unsigned a, input bit [DATA_WIDTH-1:0] d );
    int unsigned guard;
    mem_w_valid = 1'b1;
    mem_w_addr  = MEM_AW'(a);
    mem_w_data  = d;
    guard       = 0;
    while( !mem_w_ready ) begin
      guard++;
      if( guard>HANG_LIMIT ) begin
        abort_test("mem_w_ready did not rise");
      end
      @(negedge aclk);
    end
    l_wacc_cyc = cyc;
    @(negedge aclk);
    mem_w_valid = 1'b0;
    if( a<MEM_DEPTH ) begin
      ref_mem[a] = d;
    end
    n_loc_wr++;
  endtask

  task automatic mem_rd( input int unsigned a, output bit [DATA_WIDTH-1:0] d );
    int unsigned guard;
    mem_r_valid = 1'b1;
    mem_r_addr  = MEM_AW'(a);
    guard       = 0;
    while( !mem_r_ready ) begin
      guard++;
      if( guard>HANG_LIMIT ) begin
        abort_test("mem_r_ready did not rise");
      end
      @(negedge aclk);
    end
    l_racc_cyc = cyc;
    @(negedge aclk);
    mem_r_valid = 1'b0;
    if( !mem_r_rvalid ) begin
      tb_error($sformatf("mem_r_rvalid=0 in the cycle after a local read of word %0d", a));
    end
    d = mem_r_rdata;
    n_loc_rd++;
  endtask

  // 読んで期待値と照合 (範囲外は 0)
  task automatic mem_rd_check( input string tag, input int unsigned a );
    bit [DATA_WIDTH-1:0] d;
    bit [DATA_WIDTH-1:0] e;
    mem_rd(a, d);
    e = (a<MEM_DEPTH) ? ref_mem[a] : {DATA_WIDTH{1'b0}};
    if( d!==e ) begin
      tb_error($sformatf("%s : local read of word %0d = %h (exp %h)", tag, a, d, e));
    end
  endtask

  task automatic mem_fill_random();
    for( int unsigned i=0; i<MEM_DEPTH; i++ ) begin
      mem_wr(i, f_rand_data());
    end
  endtask

  // 内部メモリの全ワードを読み、期待値と照合する
  task automatic mem_check_all( input string tag );
    bit [DATA_WIDTH-1:0] d;
    int unsigned         nbad;
    nbad = 0;
    for( int unsigned i=0; i<MEM_DEPTH; i++ ) begin
      mem_rd(i, d);
      if( d!==ref_mem[i] ) begin
        nbad++;
        if( nbad<=4 ) begin
          tb_error($sformatf("%s : internal memory word %0d = %h (exp %h)", tag, i, d, ref_mem[i]));
        end
      end
    end
    if( nbad>4 ) begin
      tb_error($sformatf("%s : %0d internal memory words mismatch in total", tag, nbad));
    end
  endtask

  // 内部メモリの期待値を、ローカルポートで読んだ値に合わせる (リセットの後)
  task automatic mem_resync();
    bit [DATA_WIDTH-1:0] d;
    for( int unsigned i=0; i<MEM_DEPTH; i++ ) begin
      mem_rd(i, d);
      ref_mem[i] = d;
    end
  endtask

  //---------------------------------------------------------------------------
  // スレーブのメモリ
  //---------------------------------------------------------------------------
  task automatic slv_fill_random( input longint unsigned w0, input int unsigned n );
    bit [DATA_WIDTH-1:0] d;
    for( int unsigned i=0; i<n; i++ ) begin
      if( (w0+64'(i))<SPACE_WORDS ) begin
        d = f_rand_data();
        u_slv.poke_word(64'(f_waddr(w0 + 64'(i))), d);
        exp_smem[64'(f_waddr(w0 + 64'(i)))] = d;
      end
    end
  endtask

  // スレーブのメモリ全体を期待値と照合する (書いていないはずの場所が変わっていないことも見る)
  task automatic slv_check_all( input string tag );
    bit [63:0]   k;
    int unsigned nbad;
    nbad = 0;
    if( u_slv.mem.num()!=exp_smem.num() ) begin
      tb_error($sformatf("%s : slave memory has %0d words, expected %0d", tag, u_slv.mem.num(), exp_smem.num()));
    end
    if( exp_smem.first(k)!=0 ) begin
      do begin
        if( !u_slv.mem.exists(k) ) begin
          nbad++;
          tb_error($sformatf("%s : slave addr=%h was never written", tag, k));
        end else if( u_slv.mem[k]!=exp_smem[k] ) begin
          nbad++;
          if( nbad<=4 ) begin
            tb_error($sformatf("%s : slave addr=%h = %h (exp %h)", tag, k, u_slv.mem[k], exp_smem[k]));
          end
        end
      end while( exp_smem.next(k)!=0 );
    end
    if( nbad>4 ) begin
      tb_error($sformatf("%s : %0d slave memory words mismatch in total", tag, nbad));
    end
  endtask

  // スレーブのメモリの期待値を、スレーブモデルの中身に合わせる (リセットの後)
  task automatic slv_resync();
    bit [63:0] k;
    exp_smem.delete();
    if( u_slv.mem.first(k)!=0 ) begin
      do begin
        exp_smem[k] = u_slv.mem[k];
      end while( u_slv.mem.next(k)!=0 );
    end
  endtask

  //---------------------------------------------------------------------------
  // スレーブの振る舞い
  //---------------------------------------------------------------------------
  task automatic set_ideal();
    u_slv.set_ready(100, 100, 100);
    u_slv.set_lat(0, 0, 0, 0);
    u_slv.aw_wait_w = 1'b0;
    u_slv.w_wait_aw = 1'b0;
    ideal = 1'b1;
  endtask

  // READY の確率と応答の遅延を乱数で決める。sel で AWREADY / WREADY の待ち合わせも入れる
  task automatic rand_slave( input int unsigned sel );
    u_slv.set_ready($urandom_range(100, 20), $urandom_range(100, 20), $urandom_range(100, 20));
    u_slv.set_lat(0, $urandom_range(8, 0), 0, $urandom_range(8, 0));
    u_slv.aw_wait_w = ((sel % 4)==1)||((sel % 4)==3);
    u_slv.w_wait_aw = ((sel % 4)==2)||((sel % 4)==3);
    ideal = 1'b0;
  endtask

  // 窓 (ワード位置 w0 から n ワード) の中に、エラー応答の範囲を i 番目として乱数で置く
  task automatic rand_werr( input int unsigned i, input longint unsigned w0, input int unsigned n );
    longint unsigned w;
    w = w0 + 64'($urandom_range(n-1, 0));
    u_slv.set_werr(i, 2'($urandom_range(3, 1)), 64'(f_waddr(w)), 64'(f_waddr(w)) + 64'(STRB_W) * 64'($urandom_range(2, 0)) + 64'(STRB_W-1));
  endtask

  task automatic rand_rerr( input int unsigned i, input longint unsigned w0, input int unsigned n );
    longint unsigned w;
    w = w0 + 64'($urandom_range(n-1, 0));
    u_slv.set_rerr(i, 2'($urandom_range(3, 1)), 64'(f_waddr(w)), 64'(f_waddr(w)) + 64'(STRB_W) * 64'($urandom_range(2, 0)) + 64'(STRB_W-1));
  endtask

  //---------------------------------------------------------------------------
  // 統計
  //---------------------------------------------------------------------------
  int unsigned n_wcmd = 0;          // 転送したコマンド
  int unsigned n_rcmd = 0;
  int unsigned n_wcmd_rsperr = 0;   // エラー応答を受けたコマンド
  int unsigned n_rcmd_rsperr = 0;
  int unsigned n_wcmd_stop = 0;     // エラーで途中で止まったコマンド
  int unsigned n_rcmd_stop = 0;
  int unsigned n_cmd_bad = 0;
  int unsigned n_cmd_empty = 0;
  int unsigned n_wtr = 0;           // バス上のトランザクション
  int unsigned n_rtr = 0;
  int unsigned n_exact_cyc = 0;     // サイクル数を照合したコマンド

  //===========================================================================
  // 書き込みコマンド
  //   w_run がまとめて行う。busy 中にコマンドを出したまま待つテストなどのために、
  //   w_build (期待値) / w_drive (出す) / w_wait_accept (受付を待つ) / w_finish (完了と照合) に分けてある
  //===========================================================================
  bit                  xw_empty;
  bit                  xw_bad;
  bit                  xw_ideal;
  int unsigned         xw_maddr;
  int unsigned         xw_len;
  bit [STRB_W-1:0]     xw_strb;
  bit [2:0]            xw_prot;
  bit [ADDR_WIDTH-1:0] xw_addr [$];     // 出るはずのトランザクション (全部)
  bit [1:0]            xw_resp [$];
  bit [DATA_WIDTH-1:0] xw_data [$];
  int unsigned         xw_k;            // 最初のエラー応答の番号 (無ければトランザクション数)
  int unsigned         xw_nmin;         // done_count の範囲
  int unsigned         xw_nmax;
  int unsigned         w_acc_cyc;
  int unsigned         w_done_cyc;
  bit                  w_acc_rbusy;     // 受け付けたときに読み出しコマンドが実行中だった

  function automatic string f_cmd_str
  (
    input string               tag
   ,input bit                  wr
   ,input bit [ADDR_WIDTH-1:0] addr
   ,input bit                  incr
   ,input int unsigned         maddr
   ,input int unsigned         len
   ,input bit [STRB_W-1:0]     strb
   ,input bit [2:0]            prot
  );
    string s;
    if( wr ) begin
      s = $sformatf("%s [WR addr=%h incr=%0d mem=%0d len=%0d strb=%b prot=%b]", tag, addr, incr, maddr, len, strb, prot);
    end else begin
      s = $sformatf("%s [RD addr=%h incr=%0d mem=%0d len=%0d prot=%b]", tag, addr, incr, maddr, len, prot);
    end
    return s;
  endfunction

  // 期待値を作る (スレーブのエラー範囲、内部メモリの期待値、ideal はこの時点の値を使う)
  task automatic w_build
  (
    input bit [ADDR_WIDTH-1:0] addr
   ,input bit                  incr
   ,input int unsigned         maddr
   ,input int unsigned         len
   ,input bit [STRB_W-1:0]     strb
   ,input bit [2:0]            prot
  );
    bit [ADDR_WIDTH-1:0] a;
    bit [1:0]            r;
    xw_addr.delete();
    xw_resp.delete();
    xw_data.delete();
    xw_empty = (len==0);
    xw_bad   = !xw_empty&&f_cmd_bad(addr, incr, maddr, len);
    xw_ideal = ideal;
    xw_maddr = maddr;
    xw_len   = len;
    xw_strb  = strb;
    xw_prot  = prot;
    xw_k     = 0;
    if( !xw_empty&&!xw_bad ) begin
      xw_k = len;
      for( int unsigned i=0; i<len; i++ ) begin
        a = f_xaddr(addr, incr, i);
        r = u_slv.f_wresp(64'(a));
        xw_addr.push_back(a);
        xw_resp.push_back(r);
        xw_data.push_back(ref_mem[maddr + i]);
        if( (r!=RESP_OKAY)&&(xw_k==len) ) begin
          xw_k = i;
        end
      end
    end
    calc_nrange(xw_addr.size(), xw_k, MAX_WR_OUTSTANDING, xw_ideal, xw_nmin, xw_nmax);
  endtask

  task automatic w_drive
  (
    input bit [ADDR_WIDTH-1:0] addr
   ,input bit                  incr
   ,input int unsigned         maddr
   ,input int unsigned         len
   ,input bit [STRB_W-1:0]     strb
   ,input bit [2:0]            prot
  );
    if( (64'(maddr)>=(64'd1<<MEM_AW))||(len>LEN_MAXV) ) begin
      tb_error($sformatf("testbench : write command field does not fit in the port (mem=%0d len=%0d)", maddr, len));
    end
    wcmd_valid    = 1'b1;
    wcmd_addr     = addr;
    wcmd_incr     = incr;
    wcmd_mem_addr = MEM_AW'(maddr);
    wcmd_len      = LEN_W'(len);
    wcmd_strb     = strb;
    wcmd_prot     = prot;
  endtask

  // 受付を待つ。戻ったときは受付の posedge の次の negedge (wcmd_valid はそのまま)
  task automatic w_wait_accept( input string id );
    int unsigned guard;
    guard = 0;
    while( !wcmd_ready ) begin
      guard++;
      if( guard>HANG_LIMIT ) begin
        abort_test({id, " : wcmd_ready did not rise"});
      end
      @(negedge aclk);
    end
    w_acc_cyc   = cyc;
    w_acc_rbusy = rd_busy;
    @(negedge aclk);
  endtask

  // 完了を待ち、w_build の期待値と照合する。戻るのは done のサイクルの negedge
  task automatic w_finish( input string id );
    int unsigned         guard;
    int unsigned         n;
    int unsigned         nchk;
    int unsigned         exp_cyc;
    bit                  e_slv;
    bit                  e_dec;
    bit                  e_exo;
    bit [3:0]            exp_flags;
    bit [63:0]           a;
    bit [DATA_WIDTH-1:0] m;
    guard = 0;
    while( !wr_done ) begin
      guard++;
      if( guard>HANG_LIMIT ) begin
        abort_test({id, " : wr_done did not arrive"});
      end
      @(negedge aclk);
    end
    w_done_cyc = cyc;
    n          = 32'(wr_done_count);
    if( (n<xw_nmin)||(n>xw_nmax) ) begin
      tb_error($sformatf("%s : wr_done_count=%0d (exp %0d..%0d, first error at %0d)", id, n, xw_nmin, xw_nmax, xw_k));
    end
    nchk  = f_min(n, xw_addr.size());
    e_slv = 1'b0;
    e_dec = 1'b0;
    e_exo = 1'b0;
    for( int unsigned i=0; i<nchk; i++ ) begin
      if( xw_resp[i]==RESP_SLVERR ) begin
        e_slv = 1'b1;
      end
      if( xw_resp[i]==RESP_DECERR ) begin
        e_dec = 1'b1;
      end
      if( xw_resp[i]==RESP_EXOKAY ) begin
        e_exo = 1'b1;
      end
    end
    exp_flags = {e_exo, xw_bad, e_dec, e_slv};
    if( wr_err_flags!==exp_flags ) begin
      tb_error($sformatf("%s : wr_err_flags=%b (exp %b)", id, wr_err_flags, exp_flags));
    end
    if( wr_done_err!==(|exp_flags) ) begin
      tb_error($sformatf("%s : wr_done_err=%b (exp %b)", id, wr_done_err, |exp_flags));
    end
    if( (xw_k<nchk)&&(32'(wr_err_index)!=xw_k) ) begin
      tb_error($sformatf("%s : wr_err_index=%0d (exp %0d)", id, wr_err_index, xw_k));
    end
    // バス上のトランザクション (この時点で全て B を返し終えている)
    if( u_slv.wlog_addr.size()!=n ) begin
      tb_error($sformatf("%s : %0d write transaction(s) completed on the bus (wr_done_count=%0d)", id, u_slv.wlog_addr.size(), n));
    end
    for( int unsigned i=0; (i<nchk)&&(u_slv.wlog_addr.size()!=0); i++ ) begin
      a = 64'(xw_addr[i]);
      if( (u_slv.wlog_addr[0]!=a)||(u_slv.wlog_prot[0]!=xw_prot)||(u_slv.wlog_data[0]!=xw_data[i])||(u_slv.wlog_strb[0]!=xw_strb)||(u_slv.wlog_resp[0]!=xw_resp[i]) ) begin
        tb_error($sformatf("%s : transaction %0d : addr=%h prot=%b data=%h strb=%b resp=%b (exp addr=%h prot=%b data=%h strb=%b resp=%b)", id, i, u_slv.wlog_addr[0], u_slv.wlog_prot[0], u_slv.wlog_data[0], u_slv.wlog_strb[0], u_slv.wlog_resp[0], a, xw_prot, xw_data[i], xw_strb, xw_resp[i]));
      end
      if( u_slv.wlog_resp[0]==RESP_OKAY ) begin
        m = f_smem(a);
        for( int unsigned b=0; b<STRB_W; b++ ) begin
          if( xw_strb[b] ) begin
            m[8*b +: 8] = xw_data[i][8*b +: 8];
          end
        end
        exp_smem[a] = m;
      end
      void'(u_slv.wlog_addr.pop_front());
      void'(u_slv.wlog_prot.pop_front());
      void'(u_slv.wlog_data.pop_front());
      void'(u_slv.wlog_strb.pop_front());
      void'(u_slv.wlog_resp.pop_front());
    end
    if( u_slv.wlog_addr.size()!=0 ) begin
      u_slv.clear_wlog();
    end
    // サイクル数 (理想的なスレーブのとき)
    if( xw_ideal ) begin
      exp_cyc = (n==0) ? 1 : (7 + f_acc(n - 1, MAX_WR_OUTSTANDING));
      if( (w_done_cyc-w_acc_cyc)!=exp_cyc ) begin
        tb_error($sformatf("%s : wr_done came %0d cycles after the command was accepted (exp %0d)", id, w_done_cyc-w_acc_cyc, exp_cyc));
      end
      n_exact_cyc++;
    end
    // 触ったワードをスレーブのメモリと照合
    for( int unsigned i=0; i<nchk; i++ ) begin
      a = 64'(xw_addr[i]);
      if( u_slv.peek_word(a)!=f_smem(a) ) begin
        tb_error($sformatf("%s : slave addr=%h = %h (exp %h)", id, a, u_slv.peek_word(a), f_smem(a)));
      end
    end
    // 統計
    if( xw_empty ) begin
      n_cmd_empty++;
    end else if( xw_bad ) begin
      n_cmd_bad++;
    end else begin
      n_wcmd++;
      n_wtr = n_wtr + n;
      if( e_slv||e_dec||e_exo ) begin
        n_wcmd_rsperr++;
      end
      if( n<xw_addr.size() ) begin
        n_wcmd_stop++;
      end
    end
  endtask

  task automatic w_run
  (
    input string               tag
   ,input bit [ADDR_WIDTH-1:0] addr
   ,input bit                  incr
   ,input int unsigned         maddr
   ,input int unsigned         len
   ,input bit [STRB_W-1:0]     strb
   ,input bit [2:0]            prot
  );
    string id;
    id = f_cmd_str(tag, 1'b1, addr, incr, maddr, len, strb, prot);
    w_build(addr, incr, maddr, len, strb, prot);
    w_drive(addr, incr, maddr, len, strb, prot);
    w_wait_accept(id);
    wcmd_valid = 1'b0;
    w_finish(id);
  endtask

  //===========================================================================
  // 読み出しコマンド (書き込みと同じ分け方)
  //===========================================================================
  bit                  xr_empty;
  bit                  xr_bad;
  bit                  xr_ideal;
  int unsigned         xr_maddr;
  int unsigned         xr_len;
  bit [2:0]            xr_prot;
  bit [ADDR_WIDTH-1:0] xr_addr [$];
  bit [1:0]            xr_resp [$];
  int unsigned         xr_k;
  int unsigned         xr_nmin;
  int unsigned         xr_nmax;
  int unsigned         r_acc_cyc;
  int unsigned         r_done_cyc;
  bit                  r_acc_wbusy;     // 受け付けたときに書き込みコマンドが実行中だった

  task automatic r_build
  (
    input bit [ADDR_WIDTH-1:0] addr
   ,input bit                  incr
   ,input int unsigned         maddr
   ,input int unsigned         len
   ,input bit [2:0]            prot
  );
    bit [ADDR_WIDTH-1:0] a;
    bit [1:0]            r;
    xr_addr.delete();
    xr_resp.delete();
    xr_empty = (len==0);
    xr_bad   = !xr_empty&&f_cmd_bad(addr, incr, maddr, len);
    xr_ideal = ideal;
    xr_maddr = maddr;
    xr_len   = len;
    xr_prot  = prot;
    xr_k     = 0;
    if( !xr_empty&&!xr_bad ) begin
      xr_k = len;
      for( int unsigned i=0; i<len; i++ ) begin
        a = f_xaddr(addr, incr, i);
        r = u_slv.f_rresp(64'(a));
        xr_addr.push_back(a);
        xr_resp.push_back(r);
        if( (r!=RESP_OKAY)&&(xr_k==len) ) begin
          xr_k = i;
        end
      end
    end
    calc_nrange(xr_addr.size(), xr_k, MAX_RD_OUTSTANDING, xr_ideal, xr_nmin, xr_nmax);
  endtask

  task automatic r_drive
  (
    input bit [ADDR_WIDTH-1:0] addr
   ,input bit                  incr
   ,input int unsigned         maddr
   ,input int unsigned         len
   ,input bit [2:0]            prot
  );
    if( (64'(maddr)>=(64'd1<<MEM_AW))||(len>LEN_MAXV) ) begin
      tb_error($sformatf("testbench : read command field does not fit in the port (mem=%0d len=%0d)", maddr, len));
    end
    rcmd_valid    = 1'b1;
    rcmd_addr     = addr;
    rcmd_incr     = incr;
    rcmd_mem_addr = MEM_AW'(maddr);
    rcmd_len      = LEN_W'(len);
    rcmd_prot     = prot;
  endtask

  task automatic r_wait_accept( input string id );
    int unsigned guard;
    guard = 0;
    while( !rcmd_ready ) begin
      guard++;
      if( guard>HANG_LIMIT ) begin
        abort_test({id, " : rcmd_ready did not rise"});
      end
      @(negedge aclk);
    end
    r_acc_cyc   = cyc;
    r_acc_wbusy = wr_busy;
    @(negedge aclk);
  endtask

  task automatic r_finish( input string id );
    int unsigned         guard;
    int unsigned         n;
    int unsigned         nchk;
    int unsigned         exp_cyc;
    bit                  e_slv;
    bit                  e_dec;
    bit                  e_exo;
    bit [3:0]            exp_flags;
    bit [63:0]           a;
    guard = 0;
    while( !rd_done ) begin
      guard++;
      if( guard>HANG_LIMIT ) begin
        abort_test({id, " : rd_done did not arrive"});
      end
      @(negedge aclk);
    end
    r_done_cyc = cyc;
    n          = 32'(rd_done_count);
    if( (n<xr_nmin)||(n>xr_nmax) ) begin
      tb_error($sformatf("%s : rd_done_count=%0d (exp %0d..%0d, first error at %0d)", id, n, xr_nmin, xr_nmax, xr_k));
    end
    nchk  = f_min(n, xr_addr.size());
    e_slv = 1'b0;
    e_dec = 1'b0;
    e_exo = 1'b0;
    for( int unsigned i=0; i<nchk; i++ ) begin
      if( xr_resp[i]==RESP_SLVERR ) begin
        e_slv = 1'b1;
      end
      if( xr_resp[i]==RESP_DECERR ) begin
        e_dec = 1'b1;
      end
      if( xr_resp[i]==RESP_EXOKAY ) begin
        e_exo = 1'b1;
      end
    end
    exp_flags = {e_exo, xr_bad, e_dec, e_slv};
    if( rd_err_flags!==exp_flags ) begin
      tb_error($sformatf("%s : rd_err_flags=%b (exp %b)", id, rd_err_flags, exp_flags));
    end
    if( rd_done_err!==(|exp_flags) ) begin
      tb_error($sformatf("%s : rd_done_err=%b (exp %b)", id, rd_done_err, |exp_flags));
    end
    if( (xr_k<nchk)&&(32'(rd_err_index)!=xr_k) ) begin
      tb_error($sformatf("%s : rd_err_index=%0d (exp %0d)", id, rd_err_index, xr_k));
    end
    // バス上のトランザクション
    if( u_slv.rlog_addr.size()!=n ) begin
      tb_error($sformatf("%s : %0d read transaction(s) completed on the bus (rd_done_count=%0d)", id, u_slv.rlog_addr.size(), n));
    end
    for( int unsigned i=0; (i<nchk)&&(u_slv.rlog_addr.size()!=0); i++ ) begin
      a = 64'(xr_addr[i]);
      if( (u_slv.rlog_addr[0]!=a)||(u_slv.rlog_prot[0]!=xr_prot)||(u_slv.rlog_resp[0]!=xr_resp[i]) ) begin
        tb_error($sformatf("%s : transaction %0d : addr=%h prot=%b resp=%b (exp addr=%h prot=%b resp=%b)", id, i, u_slv.rlog_addr[0], u_slv.rlog_prot[0], u_slv.rlog_resp[0], a, xr_prot, xr_resp[i]));
      end
      if( u_slv.rlog_resp[0]==RESP_OKAY ) begin
        if( u_slv.rlog_data[0]!=f_smem(a) ) begin
          tb_error($sformatf("%s : transaction %0d : RDATA=%h but the slave memory should hold %h", id, i, u_slv.rlog_data[0], f_smem(a)));
        end
        ref_mem[xr_maddr + i] = u_slv.rlog_data[0];
      end
      void'(u_slv.rlog_addr.pop_front());
      void'(u_slv.rlog_prot.pop_front());
      void'(u_slv.rlog_data.pop_front());
      void'(u_slv.rlog_resp.pop_front());
    end
    if( u_slv.rlog_addr.size()!=0 ) begin
      u_slv.clear_rlog();
    end
    // サイクル数 (理想的なスレーブのとき)
    if( xr_ideal ) begin
      exp_cyc = (n==0) ? 1 : (5 + f_acc(n - 1, MAX_RD_OUTSTANDING));
      if( (r_done_cyc-r_acc_cyc)!=exp_cyc ) begin
        tb_error($sformatf("%s : rd_done came %0d cycles after the command was accepted (exp %0d)", id, r_done_cyc-r_acc_cyc, exp_cyc));
      end
      n_exact_cyc++;
    end
    // コマンドの範囲の内部メモリ (エラー応答の場所、止めた後の場所は元のまま)
    //   ローカルポートは書き込みコマンドの実行中は使えないので、メモリモデルの中身を直接見る
    //   (誤り / 0 ワードのコマンドは何も書かないことを、後の全ワードの照合で確認する)
    if( !xr_empty&&!xr_bad ) begin
      for( int unsigned i=xr_maddr; i<(xr_maddr+xr_len); i++ ) begin
        if( u_dut.u_mem.mem[i]!==ref_mem[i] ) begin
          tb_error($sformatf("%s : internal memory word %0d = %h (exp %h)", id, i, u_dut.u_mem.mem[i], ref_mem[i]));
        end
      end
    end
    // 統計
    if( xr_empty ) begin
      n_cmd_empty++;
    end else if( xr_bad ) begin
      n_cmd_bad++;
    end else begin
      n_rcmd++;
      n_rtr = n_rtr + n;
      if( e_slv||e_dec||e_exo ) begin
        n_rcmd_rsperr++;
      end
      if( n<xr_addr.size() ) begin
        n_rcmd_stop++;
      end
    end
  endtask

  task automatic r_run
  (
    input string               tag
   ,input bit [ADDR_WIDTH-1:0] addr
   ,input bit                  incr
   ,input int unsigned         maddr
   ,input int unsigned         len
   ,input bit [2:0]            prot
  );
    string id;
    id = f_cmd_str(tag, 1'b0, addr, incr, maddr, len, {STRB_W{1'b0}}, prot);
    r_build(addr, incr, maddr, len, prot);
    r_drive(addr, incr, maddr, len, prot);
    r_wait_accept(id);
    rcmd_valid = 1'b0;
    r_finish(id);
  endtask

  //---------------------------------------------------------------------------
  // 書き込み (窓 WB、内部メモリ [0, MH)) と読み出し (窓 RB、内部メモリ [MH, MEM_DEPTH)) を
  // 乱数の長さ / 位置で同時に実行する (MEM_DEPTH=1 のときは順に)
  //---------------------------------------------------------------------------
  task automatic pair_run( input string tag );
    bit          iw;
    bit          ir;
    int unsigned lw;
    int unsigned lr;
    int unsigned mw;
    int unsigned mr;
    int unsigned ow;
    int unsigned orr;
    bit [STRB_W-1:0] st;
    iw = ($urandom_range(3, 0)!=0);
    ir = ($urandom_range(3, 0)!=0);
    st = ($urandom_range(3, 0)==0) ? STRB_W'($urandom()) : {STRB_W{1'b1}};
    if( MH==0 ) begin
      w_run({tag, " write"}, f_waddr(WB), iw, 0, 1, st, 3'($urandom()));
      r_run({tag, " read"}, f_waddr(RB), ir, 0, 1, 3'($urandom()));
    end else begin
      lw  = $urandom_range(iw ? f_min(MH, LWIN) : MH, 1);
      mw  = $urandom_range(MH - lw, 0);
      ow  = iw ? $urandom_range(LWIN - lw, 0) : $urandom_range(LWIN - 1, 0);
      lr  = $urandom_range(ir ? f_min(MEM_DEPTH - MH, LWIN) : (MEM_DEPTH - MH), 1);
      mr  = MH + $urandom_range(MEM_DEPTH - MH - lr, 0);
      orr = ir ? $urandom_range(LWIN - lr, 0) : $urandom_range(LWIN - 1, 0);
      fork
        begin
          w_run({tag, " write"}, f_waddr(WB + 64'(ow)), iw, mw, lw, st, 3'($urandom()));
        end
        begin
          r_run({tag, " read"}, f_waddr(RB + 64'(orr)), ir, mr, lr, 3'($urandom()));
        end
      join
    end
  endtask

  //---------------------------------------------------------------------------
  // ランダムテスト (TEST8) : 書き込みコマンド / 読み出しコマンド / ローカルポートを同時に
  //   内部メモリの使用中の範囲を lk_* で管理し、3 つが同じワードを同時に触らないようにする
  //   (0 = 書き込みコマンド / 1 = 読み出しコマンド / 2 = ローカルポート)
  //---------------------------------------------------------------------------
  int unsigned lk_lo [3];
  int unsigned lk_n  [3];

  function automatic bit f_lk_free( input int unsigned self, input int unsigned lo, input int unsigned n );
    for( int unsigned p=0; p<3; p++ ) begin
      if( (p!=self)&&(lk_n[p]!=0)&&(lo<(lk_lo[p]+lk_n[p]))&&(lk_lo[p]<(lo+n)) ) begin
        return 1'b0;
      end
    end
    return 1'b1;
  endfunction

  function automatic int unsigned f_gap();
    if( $urandom_range(1,0)==0 ) begin
      return 0;
    end
    return $urandom_range(4, 1);
  endfunction

  // 誤りのあるコマンド / 0 ワードのコマンドのパラメータ (内部メモリもバスも触らない)
  task automatic rand_nocmd
  (
    input  longint unsigned     wbase
   ,output bit [ADDR_WIDTH-1:0] addr
   ,output bit                  incr
   ,output int unsigned         maddr
   ,output int unsigned         len
  );
    int unsigned kind;
    kind  = $urandom_range(2, 0);
    incr  = 1'($urandom());
    addr  = f_waddr(wbase + 64'($urandom_range(LWIN - 1, 0)));
    maddr = $urandom_range(MEM_DEPTH - 1, 0);
    len   = $urandom_range(MEM_DEPTH - maddr, 1);
    if( kind==0 ) begin
      // 0 ワード (他のフィールドは何でもよい)
      len   = 0;
      maddr = $urandom_range((1<<MEM_AW) - 1, 0);
      addr  = ADDR_WIDTH'({$urandom(), $urandom()});
    end else if( kind==1 ) begin
      // 非アライン
      addr = addr + ADDR_WIDTH'($urandom_range(STRB_W - 1, 1));
    end else begin
      // 内部メモリの範囲を超える
      len   = $urandom_range(LEN_MAXV, 1);
      maddr = (MEM_DEPTH>=len) ? (MEM_DEPTH - len + 1) : 0;
      if( maddr>((1<<MEM_AW)-1) ) begin
        maddr = (1<<MEM_AW) - 1;
      end
      maddr = $urandom_range((1<<MEM_AW) - 1, maddr);
      if( (maddr+len)<=MEM_DEPTH ) begin
        // (このメモリ構成では作れないので非アラインにする)
        addr = addr + ADDR_WIDTH'($urandom_range(STRB_W - 1, 1));
      end
    end
  endtask

  task automatic rand_wcmd( input string tag );
    bit [ADDR_WIDTH-1:0] addr;
    bit                  incr;
    int unsigned         maddr;
    int unsigned         len;
    int unsigned         lmax;
    bit                  ok;
    ok = 1'b0;
    if( $urandom_range(99,0)>=10 ) begin
      for( int unsigned t=0; (t<8)&&!ok; t++ ) begin
        incr  = ($urandom_range(3, 0)!=0);
        lmax  = incr ? LWIN : MEM_DEPTH;
        len   = ($urandom_range(1, 0)==0) ? $urandom_range(f_min(4, lmax), 1) : $urandom_range(lmax, 1);
        maddr = $urandom_range(MEM_DEPTH - len, 0);
        ok    = f_lk_free(0, maddr, len);
      end
    end
    if( ok ) begin
      lk_lo[0] = maddr;
      lk_n[0]  = len;
      addr     = incr ? f_waddr(WB + 64'($urandom_range(LWIN - len, 0))) : f_waddr(WB + 64'($urandom_range(LWIN - 1, 0)));
      w_run(tag, addr, incr, maddr, len, ($urandom_range(3, 0)==0) ? STRB_W'($urandom()) : {STRB_W{1'b1}}, 3'($urandom()));
      lk_n[0]  = 0;
    end else begin
      rand_nocmd(WB, addr, incr, maddr, len);
      w_run(tag, addr, incr, maddr, len, {STRB_W{1'b1}}, 3'($urandom()));
    end
  endtask

  task automatic rand_rcmd( input string tag );
    bit [ADDR_WIDTH-1:0] addr;
    bit                  incr;
    int unsigned         maddr;
    int unsigned         len;
    int unsigned         lmax;
    bit                  ok;
    ok = 1'b0;
    if( $urandom_range(99,0)>=10 ) begin
      for( int unsigned t=0; (t<8)&&!ok; t++ ) begin
        incr  = ($urandom_range(3, 0)!=0);
        lmax  = incr ? LWIN : MEM_DEPTH;
        len   = ($urandom_range(1, 0)==0) ? $urandom_range(f_min(4, lmax), 1) : $urandom_range(lmax, 1);
        maddr = $urandom_range(MEM_DEPTH - len, 0);
        ok    = f_lk_free(1, maddr, len);
      end
    end
    if( ok ) begin
      lk_lo[1] = maddr;
      lk_n[1]  = len;
      addr     = incr ? f_waddr(RB + 64'($urandom_range(LWIN - len, 0))) : f_waddr(RB + 64'($urandom_range(LWIN - 1, 0)));
      r_run(tag, addr, incr, maddr, len, 3'($urandom()));
      lk_n[1]  = 0;
    end else begin
      rand_nocmd(RB, addr, incr, maddr, len);
      r_run(tag, addr, incr, maddr, len, 3'($urandom()));
    end
  endtask

  // ローカルポートの操作を 1 つ (範囲外のアドレスも混ぜる)
  task automatic rand_local( input string tag );
    int unsigned a;
    bit          ok;
    ok = 1'b0;
    if( LOC_OOR&&($urandom_range(9,0)==0) ) begin
      a = $urandom_range((1<<MEM_AW) - 1, MEM_DEPTH);
      if( $urandom_range(1,0)==0 ) begin
        mem_wr(a, f_rand_data());
      end else begin
        mem_rd_check(tag, a);
      end
    end else begin
      for( int unsigned t=0; (t<4)&&!ok; t++ ) begin
        a  = $urandom_range(MEM_DEPTH - 1, 0);
        ok = f_lk_free(2, a, 1);
      end
      if( ok ) begin
        lk_lo[2] = a;
        lk_n[2]  = 1;
        if( $urandom_range(1,0)==0 ) begin
          mem_wr(a, f_rand_data());
        end else begin
          mem_rd_check(tag, a);
        end
        lk_n[2] = 0;
      end else begin
        @(negedge aclk);
      end
    end
  endtask

  //---------------------------------------------------------------------------
  // テスト本体
  //---------------------------------------------------------------------------
  bit [DATA_WIDTH-1:0] snap [MEM_DEPTH];
  int unsigned         nb_slv;
  int unsigned         nb_tb;
  int unsigned         l3;
  int unsigned         lt;
  int unsigned         posv [3];
  bit [1:0]            rsps [3];
  int unsigned         a_done;
  bit [DATA_WIDTH-1:0] dtmp;

  initial begin
    ideal         = 1'b1;
    wcmd_valid    = 1'b0;
    wcmd_addr     = {ADDR_WIDTH{1'b0}};
    wcmd_incr     = 1'b0;
    wcmd_mem_addr = {MEM_AW{1'b0}};
    wcmd_len      = {LEN_W{1'b0}};
    wcmd_strb     = {STRB_W{1'b0}};
    wcmd_prot     = 3'b000;
    rcmd_valid    = 1'b0;
    rcmd_addr     = {ADDR_WIDTH{1'b0}};
    rcmd_incr     = 1'b0;
    rcmd_mem_addr = {MEM_AW{1'b0}};
    rcmd_len      = {LEN_W{1'b0}};
    rcmd_prot     = 3'b000;
    mem_w_valid   = 1'b0;
    mem_w_addr    = {MEM_AW{1'b0}};
    mem_w_data    = {DATA_WIDTH{1'b0}};
    mem_r_valid   = 1'b0;
    mem_r_addr    = {MEM_AW{1'b0}};
    for( int unsigned p=0; p<3; p++ ) begin
      lk_lo[p] = 0;
      lk_n[p]  = 0;
    end
    aresetn = 1'b0;
    repeat( 5 ) begin
      @(negedge aclk);
    end
    aresetn = 1'b1;
    repeat( 3 ) begin
      @(negedge aclk);
    end
    $display("[INFO] ADDR_WIDTH=%0d DATA_WIDTH=%0d MEM_DEPTH=%0d MAX_WR_OUTSTANDING=%0d MAX_RD_OUTSTANDING=%0d STOP_ON_ERROR=%0d N_RAND=%0d", ADDR_WIDTH, DATA_WIDTH, MEM_DEPTH, MAX_WR_OUTSTANDING, MAX_RD_OUTSTANDING, STOP_ON_ERROR, N_RAND);
    $display("[INFO] write window = word %0h.. / read window = word %0h.. (%0d words each)", WB, RB, LWIN);
    if( SPACE_WORDS<4 ) begin
      abort_test("this testbench needs an address space of 4 words or more (ADDR_WIDTH >= log2(DATA_WIDTH/8)+2)");
    end

    //-------------------------------------------------------------------------
    // TEST1 : 基本 (理想的なスレーブ)。書き込み → 内部メモリを書き換え → 読み戻すと元に戻る。
    //         書き込みと読み出しを同じサイクルに受け付けて同時に流す
    //-------------------------------------------------------------------------
    set_ideal();
    mem_fill_random();
    slv_fill_random(WB, LWIN);
    slv_fill_random(RB, LWIN);
    w_run("TEST1 write", f_waddr(WB), 1'b1, 0, LWIN, {STRB_W{1'b1}}, 3'b000);
    $display("[INFO] TEST1 : %0d-word write : %0d cycles from accept to done", LWIN, w_done_cyc-w_acc_cyc);
    for( int unsigned i=0; i<MEM_DEPTH; i++ ) begin
      snap[i] = ref_mem[i];
    end
    mem_fill_random();
    r_run("TEST1 read back", f_waddr(WB), 1'b1, 0, LWIN, 3'b000);
    $display("[INFO] TEST1 : %0d-word read : %0d cycles from accept to done", LWIN, r_done_cyc-r_acc_cyc);
    for( int unsigned i=0; i<LWIN; i++ ) begin
      if( ref_mem[i]!=snap[i] ) begin
        tb_error($sformatf("TEST1 : word %0d was not restored by the read back : %h (written %h)", i, ref_mem[i], snap[i]));
      end
    end
    mem_check_all("TEST1");
    if( MH>=1 ) begin
      nb_slv = u_slv.n_both;
      nb_tb  = n_both_busy;
      fork
        begin
          w_run("TEST1 concurrent write", f_waddr(WB), 1'b1, 0, f_min(MH, LWIN), {STRB_W{1'b1}}, 3'b010);
        end
        begin
          r_run("TEST1 concurrent read", f_waddr(RB), 1'b1, MH, f_min(MEM_DEPTH - MH, LWIN), 3'b001);
        end
      join
      if( w_acc_cyc!=r_acc_cyc ) begin
        tb_error($sformatf("TEST1 : the write and read commands were accepted at different cycles (%0d / %0d)", w_acc_cyc, r_acc_cyc));
      end
      // (同時に動いていることは、両方のサイクル数が単独のときと同じであることでも確認している)
      if( n_both_busy==nb_tb ) begin
        tb_error("TEST1 : the write and read commands did not run at the same time");
      end
      $display("[INFO] TEST1 : concurrent %0d-word write / %0d-word read : done after %0d / %0d cycles, both outstanding on the bus for %0d cycles", f_min(MH, LWIN), f_min(MEM_DEPTH - MH, LWIN), w_done_cyc-w_acc_cyc, r_done_cyc-r_acc_cyc, u_slv.n_both-nb_slv);
    end
    mem_check_all("TEST1");
    slv_check_all("TEST1");
    $display("[INFO] TEST1 (basic write / read back, write and read at the same time) done");

    //-------------------------------------------------------------------------
    // TEST2 : 転送数と内部メモリの位置の端、固定アドレス、WSTRB、PROT、アドレス空間の両端
    //-------------------------------------------------------------------------
    set_ideal();
    w_run("TEST2 len=1 first", f_waddr(WB), 1'b1, 0, 1, {STRB_W{1'b1}}, 3'b001);
    w_run("TEST2 len=1 last", f_waddr(WB + WIN - 1), 1'b1, MEM_DEPTH - 1, 1, {STRB_W{1'b1}}, 3'b010);
    r_run("TEST2 read len=1 last", f_waddr(WB), 1'b1, MEM_DEPTH - 1, 1, 3'b100);
    r_run("TEST2 read len=1 first", f_waddr(WB + WIN - 1), 1'b1, 0, 1, 3'b011);
    if( MEM_DEPTH>=2 ) begin
      w_run("TEST2 tail", f_waddr(RB), 1'b1, MEM_DEPTH - 2, 2, {STRB_W{1'b1}}, 3'b111);
      r_run("TEST2 read tail", f_waddr(RB), 1'b1, MEM_DEPTH - 2, 2, 3'b101);
    end
    // 固定アドレス (全ワードを同じアドレスへ → 最後のワードが残る / 同じアドレスから全ワードへ)
    mem_fill_random();
    w_run("TEST2 fixed write", f_waddr(WB + WIN - 1), 1'b0, 0, MEM_DEPTH, {STRB_W{1'b1}}, 3'b000);
    r_run("TEST2 fixed read", f_waddr(RB + WIN - 1), 1'b0, 0, MEM_DEPTH, 3'b000);
    // WSTRB (1 バイトずつ、乱数、0)
    for( int unsigned b=0; b<STRB_W; b++ ) begin
      mem_fill_random();
      w_run("TEST2 strb", f_waddr(WB), 1'b1, 0, LWIN, STRB_W'(1) << b, 3'b000);
    end
    w_run("TEST2 strb random", f_waddr(WB), 1'b1, 0, LWIN, STRB_W'($urandom()), 3'b000);
    w_run("TEST2 strb=0", f_waddr(WB), 1'b1, 0, LWIN, {STRB_W{1'b0}}, 3'b000);
    r_run("TEST2 strb read back", f_waddr(WB), 1'b1, 0, LWIN, 3'b000);
    // PROT (書き込みと読み出しを同時に)
    for( int unsigned p=0; p<8; p++ ) begin
      if( MH>=1 ) begin
        fork
          begin
            w_run("TEST2 prot", f_waddr(WB), 1'b1, 0, 1, {STRB_W{1'b1}}, 3'(p));
          end
          begin
            r_run("TEST2 prot", f_waddr(RB), 1'b1, MH, 1, 3'(7 - p));
          end
        join
      end else begin
        w_run("TEST2 prot", f_waddr(WB), 1'b1, 0, 1, {STRB_W{1'b1}}, 3'(p));
        r_run("TEST2 prot", f_waddr(RB), 1'b1, 0, 1, 3'(7 - p));
      end
    end
    // アドレス空間の一番上で終わる (ちょうど収まる) / 一番上のワードに固定 / 一番下
    lt = f_min(MEM_DEPTH, int'((SPACE_WORDS<64'(MEM_DEPTH)) ? SPACE_WORDS : 64'(MEM_DEPTH)));
    mem_fill_random();
    w_run("TEST2 top", f_waddr(SPACE_WORDS - 64'(lt)), 1'b1, 0, lt, {STRB_W{1'b1}}, 3'b000);
    mem_fill_random();
    r_run("TEST2 top read", f_waddr(SPACE_WORDS - 64'(lt)), 1'b1, 0, lt, 3'b000);
    w_run("TEST2 top fixed", f_waddr(SPACE_WORDS - 64'd1), 1'b0, 0, f_min(3, MEM_DEPTH), {STRB_W{1'b1}}, 3'b000);
    r_run("TEST2 top fixed read", f_waddr(SPACE_WORDS - 64'd1), 1'b0, 0, f_min(3, MEM_DEPTH), 3'b000);
    w_run("TEST2 bottom", f_waddr(0), 1'b1, 0, f_min(2, MEM_DEPTH), {STRB_W{1'b1}}, 3'b000);
    r_run("TEST2 bottom read", f_waddr(0), 1'b1, 0, f_min(2, MEM_DEPTH), 3'b000);
    mem_check_all("TEST2");
    slv_check_all("TEST2");
    $display("[INFO] TEST2 (length / memory position corners, fixed address, WSTRB, PROT, top / bottom of the address space) done");

    //-------------------------------------------------------------------------
    // TEST3 : READY と応答の遅延
    //-------------------------------------------------------------------------
    // 遅延を長くして、未完了数が上限まで使われること
    set_ideal();
    u_slv.set_lat(MAX_WR_OUTSTANDING + 2, MAX_WR_OUTSTANDING + 6, MAX_RD_OUTSTANDING + 2, MAX_RD_OUTSTANDING + 6);
    ideal = 1'b0;
    u_slv.max_wr_out = 0;
    u_slv.max_rd_out = 0;
    w_run("TEST3 long latency", f_waddr(WB), 1'b0, 0, MEM_DEPTH, {STRB_W{1'b1}}, 3'b000);
    r_run("TEST3 long latency", f_waddr(RB), 1'b0, 0, MEM_DEPTH, 3'b000);
    if( (u_slv.max_wr_out!=f_min(MAX_WR_OUTSTANDING,MEM_DEPTH))||(u_slv.max_rd_out!=f_min(MAX_RD_OUTSTANDING,MEM_DEPTH)) ) begin
      tb_error($sformatf("TEST3 : max outstanding on the bus %0d / %0d (exp %0d / %0d)", u_slv.max_wr_out, u_slv.max_rd_out, f_min(MAX_WR_OUTSTANDING, MEM_DEPTH), f_min(MAX_RD_OUTSTANDING, MEM_DEPTH)));
    end
    $display("[INFO] TEST3 : max outstanding on the bus %0d / %0d", u_slv.max_wr_out, u_slv.max_rd_out);
    // READY / 遅延を乱数に (AWREADY は W を待つ / WREADY は AW を待つ、も入れる)。読み書きを同時に
    for( int unsigned p=0; p<16; p++ ) begin
      rand_slave(p);
      pair_run("TEST3");
    end
    set_ideal();
    mem_check_all("TEST3");
    slv_check_all("TEST3");
    $display("[INFO] TEST3 (READY / response latency, AWREADY waits for W / WREADY waits for AW) done : AW first %0d, W first %0d", u_slv.n_aw_first, u_slv.n_w_first);

    //-------------------------------------------------------------------------
    // TEST4 : エラー応答 (SLVERR / DECERR / EXOKAY を先頭 / 中間 / 最後に)。その後の正常なコマンド
    //-------------------------------------------------------------------------
    set_ideal();
    l3      = LWIN;
    posv[0] = 0;
    posv[1] = l3 / 2;
    posv[2] = l3 - 1;
    rsps[0] = RESP_SLVERR;
    rsps[1] = RESP_DECERR;
    rsps[2] = RESP_EXOKAY;
    for( int unsigned e=0; e<3; e++ ) begin
      for( int unsigned q=0; q<3; q++ ) begin
        u_slv.clear_err();
        u_slv.set_werr(0, rsps[e], 64'(f_waddr(WB + 64'(posv[q]))), 64'(f_waddr(WB + 64'(posv[q]))) + 64'(STRB_W-1));
        u_slv.set_rerr(0, rsps[e], 64'(f_waddr(RB + 64'(posv[q]))), 64'(f_waddr(RB + 64'(posv[q]))) + 64'(STRB_W-1));
        mem_fill_random();
        w_run("TEST4 write error", f_waddr(WB), 1'b1, 0, l3, {STRB_W{1'b1}}, 3'b000);
        r_run("TEST4 read error", f_waddr(RB), 1'b1, 0, l3, 3'b000);
        u_slv.clear_err();
        w_run("TEST4 write after error", f_waddr(WB), 1'b1, 0, l3, {STRB_W{1'b1}}, 3'b000);
        r_run("TEST4 read after error", f_waddr(RB), 1'b1, 0, l3, 3'b000);
      end
    end
    // 全てのトランザクションがエラー (固定アドレス)
    u_slv.set_werr(0, RESP_SLVERR, 64'(f_waddr(WB)), 64'(f_waddr(WB)) + 64'(STRB_W-1));
    u_slv.set_rerr(0, RESP_DECERR, 64'(f_waddr(RB)), 64'(f_waddr(RB)) + 64'(STRB_W-1));
    w_run("TEST4 all errors", f_waddr(WB), 1'b0, 0, MEM_DEPTH, {STRB_W{1'b1}}, 3'b000);
    r_run("TEST4 all errors", f_waddr(RB), 1'b0, 0, MEM_DEPTH, 3'b000);
    u_slv.clear_err();
    // 1 つのコマンドの中で 2 種類のエラー
    if( l3>=3 ) begin
      u_slv.set_werr(0, RESP_SLVERR, 64'(f_waddr(WB + 64'd1)), 64'(f_waddr(WB + 64'd1)) + 64'(STRB_W-1));
      u_slv.set_werr(1, RESP_DECERR, 64'(f_waddr(WB + 64'(l3 - 1))), 64'(f_waddr(WB + 64'(l3 - 1))) + 64'(STRB_W-1));
      u_slv.set_rerr(0, RESP_EXOKAY, 64'(f_waddr(RB + 64'd1)), 64'(f_waddr(RB + 64'd1)) + 64'(STRB_W-1));
      u_slv.set_rerr(1, RESP_SLVERR, 64'(f_waddr(RB + 64'd2)), 64'(f_waddr(RB + 64'd2)) + 64'(STRB_W-1));
      w_run("TEST4 two kinds", f_waddr(WB), 1'b1, 0, l3, {STRB_W{1'b1}}, 3'b000);
      r_run("TEST4 two kinds", f_waddr(RB), 1'b1, 0, l3, 3'b000);
      u_slv.clear_err();
    end
    // READY / 遅延が乱数のときのエラー (STOP_ON_ERROR=1 なら done_count の範囲を確認)
    for( int unsigned p=0; p<16; p++ ) begin
      rand_slave(p);
      rand_werr(0, WB, LWIN);
      rand_rerr(0, RB, LWIN);
      if( (p%2)==1 ) begin
        rand_werr(1, WB, LWIN);
        rand_rerr(1, RB, LWIN);
      end
      pair_run("TEST4 random");
      u_slv.clear_err();
    end
    set_ideal();
    mem_check_all("TEST4");
    slv_check_all("TEST4");
    $display("[INFO] TEST4 (error responses at the first / middle / last transaction) done : commands with error responses %0d / %0d, stopped early %0d / %0d", n_wcmd_rsperr, n_rcmd_rsperr, n_wcmd_stop, n_rcmd_stop);

    //-------------------------------------------------------------------------
    // TEST5 : コマンドの誤り / 0 ワード (バスにも内部メモリにも触らず、受付の次のサイクルで done)
    //-------------------------------------------------------------------------
    set_ideal();
    // 内部メモリの範囲を超える
    if( MEM_DEPTH>=2 ) begin
      w_run("TEST5 mem range", f_waddr(WB), 1'b1, MEM_DEPTH - 1, 2, {STRB_W{1'b1}}, 3'b000);
    end
    if( LOC_OOR ) begin
      w_run("TEST5 mem addr", f_waddr(WB), 1'b1, MEM_DEPTH, 1, {STRB_W{1'b1}}, 3'b000);
      r_run("TEST5 mem addr", f_waddr(RB), 1'b1, (1<<MEM_AW) - 1, 1, 3'b000);
    end
    r_run("TEST5 mem range", f_waddr(RB), 1'b0, 1, MEM_DEPTH, 3'b000);
    if( LEN_MAXV>MEM_DEPTH ) begin
      w_run("TEST5 len", f_waddr(WB), 1'b0, 0, LEN_MAXV, {STRB_W{1'b1}}, 3'b000);
      r_run("TEST5 len", f_waddr(RB), 1'b1, 0, MEM_DEPTH + 1, 3'b000);
    end
    // 非アライン
    for( int unsigned b=1; b<STRB_W; b++ ) begin
      w_run("TEST5 unaligned", f_waddr(WB) + ADDR_WIDTH'(b), 1'b1, 0, 1, {STRB_W{1'b1}}, 3'b000);
      r_run("TEST5 unaligned", f_waddr(RB) + ADDR_WIDTH'(b), 1'b0, 0, 1, 3'b000);
    end
    // アドレス空間の一番上を超える (インクリメント) / 固定なら問題ない
    if( MEM_DEPTH>=2 ) begin
      w_run("TEST5 top overflow", f_waddr(SPACE_WORDS - 64'd1), 1'b1, 0, 2, {STRB_W{1'b1}}, 3'b000);
      r_run("TEST5 top overflow", f_waddr(SPACE_WORDS - 64'd1), 1'b1, 0, 2, 3'b000);
      w_run("TEST5 top fixed", f_waddr(SPACE_WORDS - 64'd1), 1'b0, 0, 2, {STRB_W{1'b1}}, 3'b000);
      r_run("TEST5 top fixed", f_waddr(SPACE_WORDS - 64'd1), 1'b0, 0, 2, 3'b000);
    end
    // 0 ワード (他のフィールドが誤っていても誤りにしない)
    w_run("TEST5 empty", f_waddr(WB), 1'b1, 0, 0, {STRB_W{1'b1}}, 3'b000);
    r_run("TEST5 empty", {ADDR_WIDTH{1'b1}}, 1'b1, (1<<MEM_AW) - 1, 0, 3'b000);
    // 誤りの後の正常なコマンド
    w_run("TEST5 after bad", f_waddr(WB), 1'b1, 0, LWIN, {STRB_W{1'b1}}, 3'b000);
    r_run("TEST5 after bad", f_waddr(RB), 1'b1, 0, LWIN, 3'b000);
    // 反対方向のコマンドの実行中に、誤ったコマンド
    if( MH>=1 ) begin
      fork
        begin
          r_run("TEST5 read during bad write", f_waddr(RB), 1'b1, MH, f_min(MEM_DEPTH - MH, LWIN), 3'b000);
        end
        begin
          @(negedge aclk);
          w_run("TEST5 bad write during read", f_waddr(WB) + ADDR_WIDTH'(1), 1'b1, 0, 1, {STRB_W{1'b1}}, 3'b000);
          w_run("TEST5 empty write during read", f_waddr(WB), 1'b1, 0, 0, {STRB_W{1'b1}}, 3'b000);
        end
      join
      fork
        begin
          w_run("TEST5 write during bad read", f_waddr(WB), 1'b1, 0, f_min(MH, LWIN), {STRB_W{1'b1}}, 3'b000);
        end
        begin
          @(negedge aclk);
          r_run("TEST5 bad read during write", f_waddr(RB), 1'b1, MEM_DEPTH - 1, 2, 3'b000);
          r_run("TEST5 empty read during write", f_waddr(RB), 1'b0, 0, 0, 3'b000);
        end
      join
    end
    mem_check_all("TEST5");
    slv_check_all("TEST5");
    $display("[INFO] TEST5 (rejected / empty commands) done");

    //-------------------------------------------------------------------------
    // TEST6 : ローカルポート
    //-------------------------------------------------------------------------
    set_ideal();
    mem_fill_random();
    // 毎サイクル連続して読む (受け付けた次のサイクルにデータ)
    mem_r_valid = 1'b1;
    for( int unsigned i=0; i<MEM_DEPTH; i++ ) begin
      mem_r_addr = MEM_AW'(i);
      @(negedge aclk);
      if( !mem_r_rvalid||(mem_r_rdata!==ref_mem[i]) ) begin
        tb_error($sformatf("TEST6 : continuous read of word %0d : rvalid=%b rdata=%h (exp %h)", i, mem_r_rvalid, mem_r_rdata, ref_mem[i]));
      end
    end
    mem_r_valid = 1'b0;
    // 毎サイクル連続して書く
    mem_w_valid = 1'b1;
    for( int unsigned i=0; i<MEM_DEPTH; i++ ) begin
      mem_w_addr = MEM_AW'(i);
      mem_w_data = f_rand_data();
      ref_mem[i] = mem_w_data;
      @(negedge aclk);
    end
    mem_w_valid = 1'b0;
    mem_check_all("TEST6 continuous write");
    // 範囲外のアドレス (書き込みは無視、読み出しは 0)
    if( LOC_OOR ) begin
      mem_wr(MEM_DEPTH, f_rand_data());
      mem_wr((1<<MEM_AW) - 1, f_rand_data());
      mem_rd_check("TEST6 out of range", MEM_DEPTH);
      mem_rd_check("TEST6 out of range", (1<<MEM_AW) - 1);
      mem_check_all("TEST6 out of range");
    end
    // 書き込みコマンドの受付と同じサイクルのローカル読み出し (受け付けられる)
    w_build(f_waddr(WB), 1'b1, 0, LWIN, {STRB_W{1'b1}}, 3'b000);
    w_drive(f_waddr(WB), 1'b1, 0, LWIN, {STRB_W{1'b1}}, 3'b000);
    mem_r_valid = 1'b1;
    mem_r_addr  = MEM_AW'(MEM_DEPTH - 1);
    w_wait_accept("TEST6 write with local read");
    wcmd_valid  = 1'b0;
    mem_r_valid = 1'b0;
    if( !mem_r_rvalid||(mem_r_rdata!==ref_mem[MEM_DEPTH-1]) ) begin
      tb_error($sformatf("TEST6 : local read accepted with a write command : rvalid=%b rdata=%h (exp %h)", mem_r_rvalid, mem_r_rdata, ref_mem[MEM_DEPTH-1]));
    end
    w_finish("TEST6 write with local read");
    // 読み出しコマンドの受付と同じサイクルのローカル書き込み (受け付けられる。コマンドの範囲の外へ)
    if( MEM_DEPTH>=2 ) begin
      r_build(f_waddr(RB), 1'b0, 0, MEM_DEPTH - 1, 3'b000);
      r_drive(f_waddr(RB), 1'b0, 0, MEM_DEPTH - 1, 3'b000);
      dtmp        = f_rand_data();
      mem_w_valid = 1'b1;
      mem_w_addr  = MEM_AW'(MEM_DEPTH - 1);
      mem_w_data  = dtmp;
      r_wait_accept("TEST6 read with local write");
      rcmd_valid  = 1'b0;
      mem_w_valid = 1'b0;
      ref_mem[MEM_DEPTH-1] = dtmp;
      r_finish("TEST6 read with local write");
      mem_check_all("TEST6 same cycle");
    end
    // 書き込みコマンドの実行中: ローカル書き込みは受け付けられ、ローカル読み出しは done の次のサイクルまで待たされる
    if( MEM_DEPTH>=2 ) begin
      u_slv.set_lat(3, 3, 3, 3);
      ideal = 1'b0;
      w_build(f_waddr(WB), 1'b0, 0, MEM_DEPTH - 1, {STRB_W{1'b1}}, 3'b000);
      w_drive(f_waddr(WB), 1'b0, 0, MEM_DEPTH - 1, {STRB_W{1'b1}}, 3'b000);
      w_wait_accept("TEST6 write busy");
      wcmd_valid = 1'b0;
      fork
        begin
          w_finish("TEST6 write busy");
        end
        begin
          mem_wr(MEM_DEPTH - 1, f_rand_data());
          if( !wr_busy ) begin
            tb_error("TEST6 : the write command finished before the local write test");
          end
          if( l_wacc_cyc!=(w_acc_cyc+1) ) begin
            tb_error($sformatf("TEST6 : local write during a write command was accepted %0d cycles after the command (exp 1)", l_wacc_cyc-w_acc_cyc));
          end
          mem_rd_check("TEST6 local read waits", MEM_DEPTH - 1);
        end
      join
      if( l_racc_cyc!=(w_done_cyc+1) ) begin
        tb_error($sformatf("TEST6 : local read during a write command was accepted at cycle %0d (exp %0d = the cycle after wr_done)", l_racc_cyc, w_done_cyc + 1));
      end
      // 読み出しコマンドの実行中: ローカル読み出しは受け付けられ、ローカル書き込みは done の次のサイクルまで待たされる
      r_build(f_waddr(RB), 1'b0, 0, MEM_DEPTH - 1, 3'b000);
      r_drive(f_waddr(RB), 1'b0, 0, MEM_DEPTH - 1, 3'b000);
      r_wait_accept("TEST6 read busy");
      rcmd_valid = 1'b0;
      fork
        begin
          r_finish("TEST6 read busy");
        end
        begin
          mem_rd_check("TEST6 local read during read", MEM_DEPTH - 1);
          if( !rd_busy ) begin
            tb_error("TEST6 : the read command finished before the local read test");
          end
          if( l_racc_cyc!=(r_acc_cyc+1) ) begin
            tb_error($sformatf("TEST6 : local read during a read command was accepted %0d cycles after the command (exp 1)", l_racc_cyc-r_acc_cyc));
          end
          mem_wr(MEM_DEPTH - 1, f_rand_data());
        end
      join
      if( l_wacc_cyc!=(r_done_cyc+1) ) begin
        tb_error($sformatf("TEST6 : local write during a read command was accepted at cycle %0d (exp %0d = the cycle after rd_done)", l_wacc_cyc, r_done_cyc + 1));
      end
      set_ideal();
    end
    mem_check_all("TEST6");
    slv_check_all("TEST6");
    $display("[INFO] TEST6 (local ports : continuous access, out of range, same cycle as a command, blocking rules) done");

    //-------------------------------------------------------------------------
    // TEST7 : 実行中に次のコマンドを出したまま待つ (done の次のサイクルで受け付けられる)。
    //         その間、反対方向のコマンドはすぐに受け付けられる
    //-------------------------------------------------------------------------
    u_slv.set_ready(100, 100, 100);
    u_slv.set_lat(2, 2, 2, 2);
    ideal = 1'b0;
    fork
      begin
        // 書き込み A の実行中に書き込み B を出し続ける
        w_build(f_waddr(WB), 1'b1, 0, f_min(LWIN, (MH>=1) ? MH : MEM_DEPTH), {STRB_W{1'b1}}, 3'b001);
        w_drive(f_waddr(WB), 1'b1, 0, f_min(LWIN, (MH>=1) ? MH : MEM_DEPTH), {STRB_W{1'b1}}, 3'b001);
        w_wait_accept("TEST7 write A");
        w_drive(f_waddr(WB + WIN - 1), 1'b0, 0, 1, {STRB_W{1'b1}}, 3'b110);
        w_finish("TEST7 write A");
        a_done = w_done_cyc;
        w_build(f_waddr(WB + WIN - 1), 1'b0, 0, 1, {STRB_W{1'b1}}, 3'b110);
        w_wait_accept("TEST7 write B");
        wcmd_valid = 1'b0;
        if( w_acc_cyc!=(a_done+1) ) begin
          tb_error($sformatf("TEST7 : write B was accepted at cycle %0d (exp %0d = the cycle after wr_done of A)", w_acc_cyc, a_done + 1));
        end
        w_finish("TEST7 write B");
      end
      begin
        // その間に読み出し C
        if( MH>=1 ) begin
          while( !wr_busy ) begin
            @(negedge aclk);
          end
          r_build(f_waddr(RB), 1'b1, MH, 1, 3'b010);
          r_drive(f_waddr(RB), 1'b1, MH, 1, 3'b010);
          r_wait_accept("TEST7 read C");
          rcmd_valid = 1'b0;
          if( !r_acc_wbusy ) begin
            tb_error("TEST7 : read C was not accepted while the write command was running");
          end
          r_finish("TEST7 read C");
        end
      end
    join
    fork
      begin
        // 読み出し A の実行中に読み出し B を出し続ける
        r_build(f_waddr(RB), 1'b1, MH, f_min(LWIN, MEM_DEPTH - MH), 3'b011);
        r_drive(f_waddr(RB), 1'b1, MH, f_min(LWIN, MEM_DEPTH - MH), 3'b011);
        r_wait_accept("TEST7 read A");
        r_drive(f_waddr(RB + WIN - 1), 1'b0, MEM_DEPTH - 1, 1, 3'b100);
        r_finish("TEST7 read A");
        a_done = r_done_cyc;
        r_build(f_waddr(RB + WIN - 1), 1'b0, MEM_DEPTH - 1, 1, 3'b100);
        r_wait_accept("TEST7 read B");
        rcmd_valid = 1'b0;
        if( r_acc_cyc!=(a_done+1) ) begin
          tb_error($sformatf("TEST7 : read B was accepted at cycle %0d (exp %0d = the cycle after rd_done of A)", r_acc_cyc, a_done + 1));
        end
        r_finish("TEST7 read B");
      end
      begin
        // その間に書き込み C
        if( MH>=1 ) begin
          while( !rd_busy ) begin
            @(negedge aclk);
          end
          w_build(f_waddr(WB), 1'b1, 0, 1, {STRB_W{1'b1}}, 3'b101);
          w_drive(f_waddr(WB), 1'b1, 0, 1, {STRB_W{1'b1}}, 3'b101);
          w_wait_accept("TEST7 write C");
          wcmd_valid = 1'b0;
          if( !w_acc_rbusy ) begin
            tb_error("TEST7 : write C was not accepted while the read command was running");
          end
          w_finish("TEST7 write C");
        end
      end
    join
    set_ideal();
    mem_check_all("TEST7");
    slv_check_all("TEST7");
    $display("[INFO] TEST7 (command held while busy, the other direction accepted at once) done");

    //-------------------------------------------------------------------------
    // TEST8 : ランダム (書き込みコマンド / 読み出しコマンド / ローカルポートを同時に)
    //-------------------------------------------------------------------------
    for( int unsigned rnd=0; rnd<8; rnd++ ) begin
      if( (rnd%4)==0 ) begin
        set_ideal();
      end else begin
        rand_slave(rnd);
      end
      u_slv.clear_err();
      if( (rnd%2)==1 ) begin
        rand_werr(0, WB, LWIN);
        rand_werr(1, WB, LWIN);
        rand_rerr(0, RB, LWIN);
        rand_rerr(1, RB, LWIN);
      end
      fork
        begin
          for( int unsigned i=0; i<(N_RAND/8); i++ ) begin
            repeat( f_gap() ) begin
              @(negedge aclk);
            end
            rand_wcmd("TEST8");
          end
        end
        begin
          for( int unsigned i=0; i<(N_RAND/8); i++ ) begin
            repeat( f_gap() ) begin
              @(negedge aclk);
            end
            rand_rcmd("TEST8");
          end
        end
        begin
          for( int unsigned i=0; i<(N_RAND/8); i++ ) begin
            repeat( f_gap() ) begin
              @(negedge aclk);
            end
            rand_local("TEST8");
          end
        end
      join
      u_slv.clear_err();
      mem_check_all("TEST8");
      slv_check_all("TEST8");
    end
    set_ideal();
    $display("[INFO] TEST8 (random commands in both directions + local accesses at the same time) done : both commands running for %0d cycles in total", n_both_busy);

    //-------------------------------------------------------------------------
    // TEST9 : コマンドの実行中にリセット。その後のコマンドが正常に動く
    //-------------------------------------------------------------------------
    u_slv.set_ready(100, 100, 100);
    u_slv.set_lat(10, 10, 10, 10);
    ideal = 1'b0;
    fork
      begin
        w_build(f_waddr(WB), 1'b0, 0, MEM_DEPTH, {STRB_W{1'b1}}, 3'b000);
        w_drive(f_waddr(WB), 1'b0, 0, MEM_DEPTH, {STRB_W{1'b1}}, 3'b000);
        w_wait_accept("TEST9 write");
        wcmd_valid = 1'b0;
      end
      begin
        r_build(f_waddr(RB), 1'b0, 0, MEM_DEPTH, 3'b000);
        r_drive(f_waddr(RB), 1'b0, 0, MEM_DEPTH, 3'b000);
        r_wait_accept("TEST9 read");
        rcmd_valid = 1'b0;
      end
    join
    repeat( 4 ) begin
      @(negedge aclk);
    end
    if( !wr_busy||!rd_busy||(u_slv.wr_out==0)||(u_slv.rd_out==0) ) begin
      tb_error($sformatf("TEST9 : commands are not running at reset (wr_busy=%b rd_busy=%b, outstanding on the bus %0d / %0d)", wr_busy, rd_busy, u_slv.wr_out, u_slv.rd_out));
    end
    aresetn = 1'b0;
    repeat( 2 ) begin
      @(negedge aclk);
    end
    if( wr_busy||rd_busy||wr_done||rd_done||!wcmd_ready||!rcmd_ready||!mem_w_ready||!mem_r_ready||axi_wakeup||l_awvalid||l_wvalid||l_arvalid||mem_r_rvalid ) begin
      tb_error("TEST9 : outputs are not idle during reset");
    end
    if( (wr_err_flags!=4'b0000)||(rd_err_flags!=4'b0000)||(wr_done_count!={LEN_W{1'b0}})||(rd_done_count!={LEN_W{1'b0}}) ) begin
      tb_error("TEST9 : status is not cleared by reset");
    end
    aresetn = 1'b1;
    u_slv.clear_log();
    slv_resync();
    repeat( 2 ) begin
      @(negedge aclk);
    end
    mem_resync();
    set_ideal();
    pair_run("TEST9 after reset");
    w_run("TEST9 after reset", f_waddr(WB), 1'b1, 0, LWIN, {STRB_W{1'b1}}, 3'b000);
    r_run("TEST9 after reset", f_waddr(WB), 1'b1, 0, LWIN, 3'b000);
    mem_check_all("TEST9");
    slv_check_all("TEST9");
    $display("[INFO] TEST9 (reset while both commands are running) done");

    //-------------------------------------------------------------------------
    // 集計
    //-------------------------------------------------------------------------
    repeat( 4 ) begin
      @(negedge aclk);
    end
    if( u_slv.n_viol!=0 ) begin
      tb_error($sformatf("slave model : %0d protocol violation(s)", u_slv.n_viol));
    end
    if( u_slv.n_unaligned!=0 ) begin
      tb_error($sformatf("slave model : %0d unaligned address(es)", u_slv.n_unaligned));
    end
    if( u_dut.u_mem.sim_oor_cnt!=0 ) begin
      tb_error($sformatf("internal memory : %0d access(es) out of range", u_dut.u_mem.sim_oor_cnt));
    end
    if( u_dut.u_mem.sim_same_cnt!=0 ) begin
      tb_error($sformatf("internal memory : %0d read(s) and write(s) of the same address in the same cycle", u_dut.u_mem.sim_same_cnt));
    end
    if( mon_err_cnt!=0 ) begin
      tb_error($sformatf("monitor : %0d error(s)", mon_err_cnt));
    end
    if( (u_slv.wlog_addr.size()!=0)||(u_slv.rlog_addr.size()!=0) ) begin
      tb_error("transactions left in the slave log");
    end
    $display("[INFO] commands: write %0d / read %0d (with error responses %0d / %0d, stopped early %0d / %0d), rejected %0d, empty %0d; cycle-exact checks %0d", n_wcmd, n_rcmd, n_wcmd_rsperr, n_rcmd_rsperr, n_wcmd_stop, n_rcmd_stop, n_cmd_bad, n_cmd_empty, n_exact_cyc);
    $display("[INFO] bus: write %0d / read %0d transactions, both directions outstanding %0d cycles, max outstanding %0d / %0d; local: write %0d / read %0d", n_wtr, n_rtr, u_slv.n_both, u_slv.max_wr_out, u_slv.max_rd_out, n_loc_wr, n_loc_rd);
    if( err_cnt==0 ) begin
      $display("=== tb_axil_master_mem : TEST PASSED ===");
    end else begin
      $display("=== tb_axil_master_mem : TEST FAILED (%0d errors) ===", err_cnt);
    end
    $finish;
  end

endmodule
