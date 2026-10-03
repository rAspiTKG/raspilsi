//=============================================================================
// tb_axi4_master_linebuf.sv
//-----------------------------------------------------------------------------
//  axi4_master_linebuf の簡易テストベンチ (自己チェック)。
//  パラメータは Verilator の -G で上書きして、複数の構成で流す。
//
//    u_src (axi4_slave_mem_model) <== AR/R == DUT == AW/W/B ==> u_dst (同左)
//
//  チェック内容 (フレームごと):
//    - 出力先メモリの全バイト (ライン外のガード領域を含む) が期待値と一致するか
//        ライン内  : 入力画像の画素 (コンテナの余りビットは 0)
//        ライン外  : 事前に書いておいたパターンのまま (WSTRB で壊していないこと)
//    - 発行されたバーストの先頭アドレスと長さの列が、
//      「ラインごとに min(残り, MAX_BURST, 4KB まで) で分割」と一致するか
//    - done_err / err_flags、ライン完了パルスの回数、書き込みバイト数と範囲
//  常時チェック (モニタ):
//    - AxSIZE / AxBURST / AxID / AxCACHE / AxPROT / AxQOS / AxREGION / AxLOCK
//    - WSTRB (ライン最終ビートだけ端数、それ以外は全有効)
//    - バースト中に RREADY を下げない / WVALID を途切れさせない (バスを塞がない)
//    - スレーブモデルのプロトコル違反 0 件、scratchpad の同一ライン同時アクセス 0 件
//
//  テスト:
//    TEST1 : 基本 (数ライン、stride がライン長ちょうど)
//    TEST2 : 入力・出力とも 4KB 境界を跨ぐ
//    TEST3 : 幅 / 高さの端 (1 画素、1 ワード前後、最大幅、1 ライン、NUM_LINES 前後)
//    TEST4 : 出力側を完全に止める (scratchpad が満杯になり、入力の AR も止まること)
//    TEST5 : READY が VALID を待つスレーブ
//    TEST6 : SLVERR 注入 (入力側 / 出力側)
//    TEST7 : コマンド誤り (幅超過・非アライン)、0 画素 / 0 ライン
//    TEST8 : busy 中に次のコマンドを待たせる (連続フレーム)
//    TEST9 : ランダムフレーム x 4 条件 (ストール無し / 入力が遅い / 出力が遅い /
//            両側ストール + READY が VALID を待つ)
//=============================================================================
`timescale 1ns / 1ps

module tb_axi4_master_linebuf #(
  parameter int unsigned IN_ADDR_WIDTH   = 32
 ,parameter int unsigned IN_DATA_WIDTH   = 64
 ,parameter int unsigned IN_ID_WIDTH     = 4
 ,parameter int unsigned IN_AXI_ID       = 2
 ,parameter int unsigned IN_MAX_BURST    = 16
 ,parameter int unsigned IN_FIFO_DEPTH   = 32
 ,parameter int unsigned OUT_ADDR_WIDTH  = 32
 ,parameter int unsigned OUT_DATA_WIDTH  = 64
 ,parameter int unsigned OUT_ID_WIDTH    = 4
 ,parameter int unsigned OUT_AXI_ID      = 5
 ,parameter int unsigned OUT_MAX_BURST   = 16
 ,parameter int unsigned OUT_FIFO_DEPTH  = 32
 ,parameter int unsigned PIXEL_BITS      = 8
 ,parameter int unsigned PIX_MEM_BITS    = ((PIXEL_BITS + 7) / 8) * 8
 ,parameter bit          PIX_ALIGN_MSB   = 1'b0
 ,parameter int unsigned PIX_PER_WORD    = 1
 ,parameter int unsigned MAX_LINE_PIXELS = 200
 ,parameter int unsigned NUM_LINES       = 4
 ,parameter int unsigned HEIGHT_WIDTH    = 16
 ,parameter int unsigned STRIDE_WIDTH    = 20
 ,parameter int unsigned N_RAND          = 30
);

  //---------------------------------------------------------------------------
  // Local parameters
  //---------------------------------------------------------------------------
  localparam int unsigned IN_BYTES    = IN_DATA_WIDTH / 8;
  localparam int unsigned OUT_BYTES   = OUT_DATA_WIDTH / 8;
  localparam int unsigned PIX_OFS     = PIX_ALIGN_MSB ? (PIX_MEM_BITS - PIXEL_BITS) : 0;
  localparam int unsigned XW          = $clog2(MAX_LINE_PIXELS+1);
  localparam int unsigned GUARD       = 64;               // ライン外チェック用のガード [バイト]
  localparam int unsigned MAX_H       = (3 * NUM_LINES) + 2;
  localparam int unsigned TIMEOUT_CYC = 3000000;          // 受付 / 完了待ちの上限 [cycle]

  // DUT に渡す AXI 属性 (既定値と違う値にして、出力に反映されることを確認する)
  localparam logic [3:0] ARCACHE_V  = 4'b1011;
  localparam logic [2:0] ARPROT_V   = 3'b010;
  localparam logic [3:0] ARQOS_V    = 4'd3;
  localparam logic [3:0] ARREGION_V = 4'd6;
  localparam logic [3:0] AWCACHE_V  = 4'b0111;
  localparam logic [2:0] AWPROT_V   = 3'b001;
  localparam logic [3:0] AWQOS_V    = 4'd9;
  localparam logic [3:0] AWREGION_V = 4'd12;

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
  // DUT 接続信号
  //---------------------------------------------------------------------------
  logic                              cmd_valid;
  logic                              cmd_ready;
  logic [IN_ADDR_WIDTH-1:0]          cmd_src_addr;
  logic [OUT_ADDR_WIDTH-1:0]         cmd_dst_addr;
  logic [STRIDE_WIDTH-1:0]           cmd_src_stride;
  logic [STRIDE_WIDTH-1:0]           cmd_dst_stride;
  logic [XW-1:0]                     cmd_width;
  logic [HEIGHT_WIDTH-1:0]           cmd_height;
  logic                              busy;
  logic                              done;
  logic                              done_err;
  logic [2:0]                        err_flags;
  logic                              line_in_done;
  logic                              line_out_done;
  logic [$clog2(NUM_LINES+1)-1:0]    sp_level;

  logic [IN_ID_WIDTH-1:0]            in_arid;
  logic [IN_ADDR_WIDTH-1:0]          in_araddr;
  logic [7:0]                        in_arlen;
  logic [2:0]                        in_arsize;
  logic [1:0]                        in_arburst;
  logic                              in_arlock;
  logic [3:0]                        in_arcache;
  logic [2:0]                        in_arprot;
  logic [3:0]                        in_arqos;
  logic [3:0]                        in_arregion;
  logic                              in_arvalid;
  logic                              in_arready;
  logic [IN_ID_WIDTH-1:0]            in_rid;
  logic [IN_DATA_WIDTH-1:0]          in_rdata;
  logic [1:0]                        in_rresp;
  logic                              in_rlast;
  logic                              in_rvalid;
  logic                              in_rready;

  logic [OUT_ID_WIDTH-1:0]           out_awid;
  logic [OUT_ADDR_WIDTH-1:0]         out_awaddr;
  logic [7:0]                        out_awlen;
  logic [2:0]                        out_awsize;
  logic [1:0]                        out_awburst;
  logic                              out_awlock;
  logic [3:0]                        out_awcache;
  logic [2:0]                        out_awprot;
  logic [3:0]                        out_awqos;
  logic [3:0]                        out_awregion;
  logic                              out_awvalid;
  logic                              out_awready;
  logic [OUT_DATA_WIDTH-1:0]         out_wdata;
  logic [OUT_BYTES-1:0]              out_wstrb;
  logic                              out_wlast;
  logic                              out_wvalid;
  logic                              out_wready;
  logic [OUT_ID_WIDTH-1:0]           out_bid;
  logic [1:0]                        out_bresp;
  logic                              out_bvalid;
  logic                              out_bready;

  //---------------------------------------------------------------------------
  // DUT
  //---------------------------------------------------------------------------
  axi4_master_linebuf #(
    .IN_ADDR_WIDTH(IN_ADDR_WIDTH)
   ,.IN_DATA_WIDTH(IN_DATA_WIDTH)
   ,.IN_ID_WIDTH(IN_ID_WIDTH)
   ,.IN_AXI_ID(IN_AXI_ID)
   ,.IN_MAX_BURST(IN_MAX_BURST)
   ,.IN_FIFO_DEPTH(IN_FIFO_DEPTH)
   ,.IN_ARCACHE(ARCACHE_V)
   ,.IN_ARPROT(ARPROT_V)
   ,.IN_ARQOS(ARQOS_V)
   ,.IN_ARREGION(ARREGION_V)
   ,.OUT_ADDR_WIDTH(OUT_ADDR_WIDTH)
   ,.OUT_DATA_WIDTH(OUT_DATA_WIDTH)
   ,.OUT_ID_WIDTH(OUT_ID_WIDTH)
   ,.OUT_AXI_ID(OUT_AXI_ID)
   ,.OUT_MAX_BURST(OUT_MAX_BURST)
   ,.OUT_FIFO_DEPTH(OUT_FIFO_DEPTH)
   ,.OUT_AWCACHE(AWCACHE_V)
   ,.OUT_AWPROT(AWPROT_V)
   ,.OUT_AWQOS(AWQOS_V)
   ,.OUT_AWREGION(AWREGION_V)
   ,.PIXEL_BITS(PIXEL_BITS)
   ,.PIX_MEM_BITS(PIX_MEM_BITS)
   ,.PIX_ALIGN_MSB(PIX_ALIGN_MSB)
   ,.PIX_PER_WORD(PIX_PER_WORD)
   ,.MAX_LINE_PIXELS(MAX_LINE_PIXELS)
   ,.NUM_LINES(NUM_LINES)
   ,.HEIGHT_WIDTH(HEIGHT_WIDTH)
   ,.STRIDE_WIDTH(STRIDE_WIDTH)
  ) u_dut (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.cmd_valid(cmd_valid)
   ,.cmd_ready(cmd_ready)
   ,.cmd_src_addr(cmd_src_addr)
   ,.cmd_dst_addr(cmd_dst_addr)
   ,.cmd_src_stride(cmd_src_stride)
   ,.cmd_dst_stride(cmd_dst_stride)
   ,.cmd_width(cmd_width)
   ,.cmd_height(cmd_height)
   ,.busy(busy)
   ,.done(done)
   ,.done_err(done_err)
   ,.err_flags(err_flags)
   ,.line_in_done(line_in_done)
   ,.line_out_done(line_out_done)
   ,.sp_level(sp_level)
   ,.m_axi_in_arid(in_arid)
   ,.m_axi_in_araddr(in_araddr)
   ,.m_axi_in_arlen(in_arlen)
   ,.m_axi_in_arsize(in_arsize)
   ,.m_axi_in_arburst(in_arburst)
   ,.m_axi_in_arlock(in_arlock)
   ,.m_axi_in_arcache(in_arcache)
   ,.m_axi_in_arprot(in_arprot)
   ,.m_axi_in_arqos(in_arqos)
   ,.m_axi_in_arregion(in_arregion)
   ,.m_axi_in_arvalid(in_arvalid)
   ,.m_axi_in_arready(in_arready)
   ,.m_axi_in_rid(in_rid)
   ,.m_axi_in_rdata(in_rdata)
   ,.m_axi_in_rresp(in_rresp)
   ,.m_axi_in_rlast(in_rlast)
   ,.m_axi_in_rvalid(in_rvalid)
   ,.m_axi_in_rready(in_rready)
   ,.m_axi_out_awid(out_awid)
   ,.m_axi_out_awaddr(out_awaddr)
   ,.m_axi_out_awlen(out_awlen)
   ,.m_axi_out_awsize(out_awsize)
   ,.m_axi_out_awburst(out_awburst)
   ,.m_axi_out_awlock(out_awlock)
   ,.m_axi_out_awcache(out_awcache)
   ,.m_axi_out_awprot(out_awprot)
   ,.m_axi_out_awqos(out_awqos)
   ,.m_axi_out_awregion(out_awregion)
   ,.m_axi_out_awvalid(out_awvalid)
   ,.m_axi_out_awready(out_awready)
   ,.m_axi_out_wdata(out_wdata)
   ,.m_axi_out_wstrb(out_wstrb)
   ,.m_axi_out_wlast(out_wlast)
   ,.m_axi_out_wvalid(out_wvalid)
   ,.m_axi_out_wready(out_wready)
   ,.m_axi_out_bid(out_bid)
   ,.m_axi_out_bresp(out_bresp)
   ,.m_axi_out_bvalid(out_bvalid)
   ,.m_axi_out_bready(out_bready)
  );

  //---------------------------------------------------------------------------
  // 入力側スレーブ (Read だけ使う。Write チャネルは未使用)
  //---------------------------------------------------------------------------
  logic                      src_awready_nc;
  logic                      src_wready_nc;
  logic [IN_ID_WIDTH-1:0]    src_bid_nc;
  logic [1:0]                src_bresp_nc;
  logic                      src_bvalid_nc;

  axi4_slave_mem_model #(
    .ADDR_WIDTH(IN_ADDR_WIDTH)
   ,.DATA_WIDTH(IN_DATA_WIDTH)
   ,.ID_WIDTH(IN_ID_WIDTH)
   ,.MAX_BURST(IN_MAX_BURST)
  ) u_src (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.s_axi_awid({IN_ID_WIDTH{1'b0}})
   ,.s_axi_awaddr({IN_ADDR_WIDTH{1'b0}})
   ,.s_axi_awlen(8'd0)
   ,.s_axi_awsize(3'd0)
   ,.s_axi_awburst(2'b01)
   ,.s_axi_awvalid(1'b0)
   ,.s_axi_awready(src_awready_nc)
   ,.s_axi_wdata({IN_DATA_WIDTH{1'b0}})
   ,.s_axi_wstrb({IN_BYTES{1'b0}})
   ,.s_axi_wlast(1'b0)
   ,.s_axi_wvalid(1'b0)
   ,.s_axi_wready(src_wready_nc)
   ,.s_axi_bid(src_bid_nc)
   ,.s_axi_bresp(src_bresp_nc)
   ,.s_axi_bvalid(src_bvalid_nc)
   ,.s_axi_bready(1'b0)
   ,.s_axi_arid(in_arid)
   ,.s_axi_araddr(in_araddr)
   ,.s_axi_arlen(in_arlen)
   ,.s_axi_arsize(in_arsize)
   ,.s_axi_arburst(in_arburst)
   ,.s_axi_arvalid(in_arvalid)
   ,.s_axi_arready(in_arready)
   ,.s_axi_rid(in_rid)
   ,.s_axi_rdata(in_rdata)
   ,.s_axi_rresp(in_rresp)
   ,.s_axi_rlast(in_rlast)
   ,.s_axi_rvalid(in_rvalid)
   ,.s_axi_rready(in_rready)
  );

  //---------------------------------------------------------------------------
  // 出力側スレーブ (Write だけ使う。Read チャネルは未使用)
  //---------------------------------------------------------------------------
  logic                      dst_arready_nc;
  logic [OUT_ID_WIDTH-1:0]   dst_rid_nc;
  logic [OUT_DATA_WIDTH-1:0] dst_rdata_nc;
  logic [1:0]                dst_rresp_nc;
  logic                      dst_rlast_nc;
  logic                      dst_rvalid_nc;

  axi4_slave_mem_model #(
    .ADDR_WIDTH(OUT_ADDR_WIDTH)
   ,.DATA_WIDTH(OUT_DATA_WIDTH)
   ,.ID_WIDTH(OUT_ID_WIDTH)
   ,.MAX_BURST(OUT_MAX_BURST)
  ) u_dst (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.s_axi_awid(out_awid)
   ,.s_axi_awaddr(out_awaddr)
   ,.s_axi_awlen(out_awlen)
   ,.s_axi_awsize(out_awsize)
   ,.s_axi_awburst(out_awburst)
   ,.s_axi_awvalid(out_awvalid)
   ,.s_axi_awready(out_awready)
   ,.s_axi_wdata(out_wdata)
   ,.s_axi_wstrb(out_wstrb)
   ,.s_axi_wlast(out_wlast)
   ,.s_axi_wvalid(out_wvalid)
   ,.s_axi_wready(out_wready)
   ,.s_axi_bid(out_bid)
   ,.s_axi_bresp(out_bresp)
   ,.s_axi_bvalid(out_bvalid)
   ,.s_axi_bready(out_bready)
   ,.s_axi_arid({OUT_ID_WIDTH{1'b0}})
   ,.s_axi_araddr({OUT_ADDR_WIDTH{1'b0}})
   ,.s_axi_arlen(8'd0)
   ,.s_axi_arsize(3'd0)
   ,.s_axi_arburst(2'b01)
   ,.s_axi_arvalid(1'b0)
   ,.s_axi_arready(dst_arready_nc)
   ,.s_axi_rid(dst_rid_nc)
   ,.s_axi_rdata(dst_rdata_nc)
   ,.s_axi_rresp(dst_rresp_nc)
   ,.s_axi_rlast(dst_rlast_nc)
   ,.s_axi_rvalid(dst_rvalid_nc)
   ,.s_axi_rready(1'b0)
  );

  //---------------------------------------------------------------------------
  // フレームの記述
  //---------------------------------------------------------------------------
  typedef struct {
    logic [63:0] src;
    logic [63:0] dst;
    int unsigned sstr;
    int unsigned dstr;
    int unsigned w;
    int unsigned h;
  } frame_t;

  // WSTRB モニタ用: フレームごとの期待値 (コマンドを出す順に積む)
  typedef struct {
    int unsigned out_beats;     // 1 ラインのビート数
    int unsigned last_bytes;    // 最終ビートの有効バイト数
    int unsigned total_beats;   // フレーム全体のビート数
  } wexp_t;

  wexp_t       wexp_q[$];

  // 期待するバースト列
  logic [63:0] exp_ar_addr[$];
  int unsigned exp_ar_len[$];
  logic [63:0] exp_aw_addr[$];
  int unsigned exp_aw_len[$];

  int unsigned err_cnt;
  int unsigned n_frames;
  longint unsigned n_pix_total;

  //---------------------------------------------------------------------------
  // 握手 / 完了の記録 (posedge でサンプル)
  //---------------------------------------------------------------------------
  int unsigned n_acc;
  int unsigned n_done;
  bit          last_err;
  bit [2:0]    last_flags;
  int unsigned n_line_in;
  int unsigned n_line_out;
  int unsigned cyc;
  int unsigned acc_cyc;
  int unsigned done_cyc;
  int unsigned max_sp_level;
  int unsigned mon_err_cnt;
  logic        done_q;
  logic [31:0] sp_level32;

  assign sp_level32 = 32'(sp_level);

  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      n_acc        <= 0;
      n_done       <= 0;
      last_err     <= 1'b0;
      last_flags   <= 3'b000;
      n_line_in    <= 0;
      n_line_out   <= 0;
      cyc          <= 0;
      acc_cyc      <= 0;
      done_cyc     <= 0;
      max_sp_level <= 0;
      done_q       <= 1'b0;
    end else begin
      cyc    <= cyc + 1;
      done_q <= done;
      if( cmd_valid&&cmd_ready ) begin
        n_acc   <= n_acc + 1;
        acc_cyc <= cyc;
      end
      if( done ) begin
        n_done     <= n_done + 1;
        last_err   <= done_err;
        last_flags <= err_flags;
        done_cyc   <= cyc;
      end
      if( line_in_done ) begin
        n_line_in <= n_line_in + 1;
      end
      if( line_out_done ) begin
        n_line_out <= n_line_out + 1;
      end
      if( sp_level32>max_sp_level ) begin
        max_sp_level <= sp_level32;
      end
    end
  end

  //---------------------------------------------------------------------------
  // 常時モニタ
  //---------------------------------------------------------------------------
  bit          r_open;        // AR 握手後、RLAST まで
  bit          w_open;        // AW 握手後、WLAST まで
  bit          wexp_vld;
  wexp_t       wexp_cur;
  int unsigned w_line_beat;   // ライン内のビート位置
  int unsigned w_frame_beat;  // フレーム内のビート位置

  // AR / AW の属性が期待どおりか (DUT は常にバス幅・INCR・parameter の値を出す)
  logic ar_attr_ok;
  logic aw_attr_ok;

  assign ar_attr_ok = (in_arsize===3'($clog2(IN_BYTES)))&&(in_arburst===2'b01)&&(in_arid===IN_ID_WIDTH'(IN_AXI_ID))
                    &&(in_arcache===ARCACHE_V)&&(in_arprot===ARPROT_V)&&(in_arqos===ARQOS_V)&&(in_arregion===ARREGION_V)
                    &&(in_arlock===1'b0)&&((in_araddr&IN_ADDR_WIDTH'(IN_BYTES-1))==='0);
  assign aw_attr_ok = (out_awsize===3'($clog2(OUT_BYTES)))&&(out_awburst===2'b01)&&(out_awid===OUT_ID_WIDTH'(OUT_AXI_ID))
                    &&(out_awcache===AWCACHE_V)&&(out_awprot===AWPROT_V)&&(out_awqos===AWQOS_V)&&(out_awregion===AWREGION_V)
                    &&(out_awlock===1'b0)&&((out_awaddr&OUT_ADDR_WIDTH'(OUT_BYTES-1))==='0);

  function automatic logic [OUT_BYTES-1:0] f_strb( input int unsigned nbytes );
    logic [OUT_BYTES-1:0] s;
    for( int unsigned i=0; i<OUT_BYTES; i++ ) begin
      s[i] = (i<nbytes);
    end
    return s;
  endfunction

  always @(posedge aclk or negedge aresetn) begin
    logic [OUT_BYTES-1:0] exp_strb;
    wexp_t                e;
    if( !aresetn ) begin
      mon_err_cnt  <= 0;
      r_open       <= 1'b0;
      w_open       <= 1'b0;
      wexp_vld     <= 1'b0;
      w_line_beat  <= 0;
      w_frame_beat <= 0;
    end else begin
      // --- ステータスの整合 ---
      if( cmd_ready!==!busy ) begin
        $display("[FAIL] monitor : cmd_ready=%b busy=%b", cmd_ready, busy);
        mon_err_cnt <= mon_err_cnt + 1;
      end
      if( done&&done_q ) begin
        $display("[FAIL] monitor : done is longer than 1 cycle");
        mon_err_cnt <= mon_err_cnt + 1;
      end
      if( sp_level32>NUM_LINES ) begin
        $display("[FAIL] monitor : sp_level=%0d exceeds NUM_LINES", sp_level);
        mon_err_cnt <= mon_err_cnt + 1;
      end
      // --- AR の属性 ---
      if( in_arvalid&&!ar_attr_ok ) begin
        $display("[FAIL] monitor : AR attribute : addr=%h size=%0d burst=%b id=%0d cache=%b prot=%b qos=%0d region=%0d lock=%b"
                , in_araddr, in_arsize, in_arburst, in_arid, in_arcache, in_arprot, in_arqos, in_arregion, in_arlock);
        mon_err_cnt <= mon_err_cnt + 1;
      end
      // --- AW の属性 ---
      if( out_awvalid&&!aw_attr_ok ) begin
        $display("[FAIL] monitor : AW attribute : addr=%h size=%0d burst=%b id=%0d cache=%b prot=%b qos=%0d region=%0d lock=%b"
                , out_awaddr, out_awsize, out_awburst, out_awid, out_awcache, out_awprot, out_awqos, out_awregion, out_awlock);
        mon_err_cnt <= mon_err_cnt + 1;
      end
      // --- R : バースト中に RREADY を下げない ---
      if( r_open&&!in_rready ) begin
        $display("[FAIL] monitor : RREADY is low during a read burst");
        mon_err_cnt <= mon_err_cnt + 1;
      end
      if( in_arvalid&&in_arready ) begin
        r_open <= 1'b1;
      end else if( in_rvalid&&in_rready&&in_rlast ) begin
        r_open <= 1'b0;
      end
      // --- W : バースト中に WVALID を途切れさせない ---
      if( w_open&&!out_wvalid ) begin
        $display("[FAIL] monitor : WVALID is low during a write burst");
        mon_err_cnt <= mon_err_cnt + 1;
      end
      if( out_awvalid&&out_awready ) begin
        w_open <= 1'b1;
      end else if( out_wvalid&&out_wready&&out_wlast ) begin
        w_open <= 1'b0;
      end
      // --- W : WSTRB (ライン最終ビートだけ端数) ---
      if( out_wvalid&&out_wready ) begin
        e = wexp_cur;
        if( !wexp_vld ) begin
          if( wexp_q.size()==0 ) begin
            $display("[FAIL] monitor : W beat without an expected frame");
            mon_err_cnt <= mon_err_cnt + 1;
            e.out_beats   = 1;
            e.last_bytes  = OUT_BYTES;
            e.total_beats = 1;
          end else begin
            e = wexp_q.pop_front();
          end
        end
        if( w_line_beat==(e.out_beats-1) ) begin
          exp_strb = f_strb(e.last_bytes);
        end else begin
          exp_strb = {OUT_BYTES{1'b1}};
        end
        if( out_wstrb!==exp_strb ) begin
          $display("[FAIL] monitor : WSTRB=%h (exp %h) at line beat %0d", out_wstrb, exp_strb, w_line_beat);
          mon_err_cnt <= mon_err_cnt + 1;
        end
        wexp_cur <= e;
        if( w_line_beat==(e.out_beats-1) ) begin
          w_line_beat <= 0;
        end else begin
          w_line_beat <= w_line_beat + 1;
        end
        if( w_frame_beat==(e.total_beats-1) ) begin
          w_frame_beat <= 0;
          wexp_vld     <= 1'b0;
        end else begin
          w_frame_beat <= w_frame_beat + 1;
          wexp_vld     <= 1'b1;
        end
      end
    end
  end

  //---------------------------------------------------------------------------
  // ヘルパ関数
  //---------------------------------------------------------------------------
  function automatic int unsigned f_line_bytes( input int unsigned w );
    return ((w*PIX_MEM_BITS)+7)/8;
  endfunction

  function automatic int unsigned f_beats( input int unsigned nbytes, input int unsigned bus_bytes );
    return (nbytes+bus_bytes-1)/bus_bytes;
  endfunction

  function automatic int unsigned f_align_up( input int unsigned x, input int unsigned a );
    return ((x+a-1)/a)*a;
  endfunction

  // h-1 (h=0 のときは 0)
  function automatic int unsigned f_hm1( input int unsigned h );
    if( h==0 ) begin
      return 0;
    end
    return h - 1;
  endfunction

  // 出力先に事前に書いておくパターン
  function automatic logic [7:0] f_pattern( input logic [63:0] a );
    return 8'((a*64'd37) ^ (a >> 7) ^ 64'h5A);
  endfunction

  // ライン内 i バイト目の期待値。src_byte は入力側の同じ位置のバイト。
  //   画素フィールド (コンテナ内の PIX_OFS から PIXEL_BITS ビット) だけ残し、
  //   コンテナの余りビットとライン幅より後ろのビットは 0
  function automatic logic [7:0] f_exp_byte( input logic [7:0] src_byte, input int unsigned i, input int unsigned w );
    logic [7:0] e;
    int         k;
    int         c;
    e = 8'h00;
    for( int b=0; b<8; b++ ) begin
      k = (8*int'(i)) + b;
      c = k % int'(PIX_MEM_BITS);
      if( (k<int'(w*PIX_MEM_BITS))&&(c>=int'(PIX_OFS))&&(c<int'(PIX_OFS+PIXEL_BITS)) ) begin
        e[b] = src_byte[b];
      end
    end
    return e;
  endfunction

  // 4KB 境界の近くに置いたランダムな先頭アドレス (bus_bytes アライン)
  function automatic logic [63:0] f_rand_base( input int unsigned aw, input logic [63:0] span, input int unsigned bus_bytes );
    logic [63:0] limit;
    logic [63:0] pages;
    logic [63:0] page;
    logic [63:0] ofs;
    limit = (aw>=64) ? 64'hFFFF_FFFF_FFFF_F000 : ((64'd1 << aw) - 64'd4096);
    pages = (limit - span - 64'd8192) >> 12;
    page  = 64'd1 + ({$urandom(), $urandom()} % pages);
    case( $urandom_range(3,0) )
      0 : begin
        ofs = 64'd0;
      end
      1 : begin
        ofs = 64'($urandom_range(511,0)) * 64'd8;
      end
      default : begin
        // ページ末尾の手前 (1..8 ビート分) → 最初のバーストが 4KB 境界で切れる
        ofs = 64'd4096 - (64'($urandom_range(8,1)) * 64'(bus_bytes));
      end
    endcase
    ofs = (ofs / 64'(bus_bytes)) * 64'(bus_bytes);
    return (page << 12) + ofs;
  endfunction

  function automatic int unsigned f_rand_width();
    int unsigned w;
    case( $urandom_range(11,0) )
      0 : begin
        w = 1;
      end
      1 : begin
        w = MAX_LINE_PIXELS;
      end
      2 : begin
        w = (PIX_PER_WORD>1) ? (PIX_PER_WORD-1) : 1;
      end
      3 : begin
        w = PIX_PER_WORD;
      end
      4 : begin
        w = PIX_PER_WORD + 1;
      end
      5 : begin
        w = (MAX_LINE_PIXELS>1) ? (MAX_LINE_PIXELS-1) : 1;
      end
      default : begin
        w = $urandom_range(MAX_LINE_PIXELS,1);
      end
    endcase
    if( w>MAX_LINE_PIXELS ) begin
      w = MAX_LINE_PIXELS;
    end
    return w;
  endfunction

  function automatic int unsigned f_rand_height();
    int unsigned h;
    case( $urandom_range(7,0) )
      0 : begin
        h = 1;
      end
      1 : begin
        h = NUM_LINES;
      end
      2 : begin
        h = NUM_LINES + 1;
      end
      default : begin
        h = $urandom_range(MAX_H,1);
      end
    endcase
    return h;
  endfunction

  //---------------------------------------------------------------------------
  // 期待するバースト列を積む: min(残り, MAX_BURST, 4KB まで) で分割
  //---------------------------------------------------------------------------
  task automatic push_exp_bursts( input bit is_wr, input logic [63:0] addr, input int unsigned beats );
    logic [63:0] a;
    int unsigned rem;
    int unsigned bl;
    int unsigned b4k;
    int unsigned bus_bytes;
    int unsigned maxb;
    bus_bytes = is_wr ? OUT_BYTES : IN_BYTES;
    maxb      = is_wr ? OUT_MAX_BURST : IN_MAX_BURST;
    a   = addr;
    rem = beats;
    while( rem!=0 ) begin
      b4k = (4096 - 32'(a[11:0])) / bus_bytes;
      bl  = maxb;
      if( rem<bl ) begin
        bl = rem;
      end
      if( b4k<bl ) begin
        bl = b4k;
      end
      if( is_wr ) begin
        exp_aw_addr.push_back(a);
        exp_aw_len.push_back(bl-1);
      end else begin
        exp_ar_addr.push_back(a);
        exp_ar_len.push_back(bl-1);
      end
      a   = a + (64'(bl) * 64'(bus_bytes));
      rem = rem - bl;
    end
  endtask

  //---------------------------------------------------------------------------
  // フレームの準備: 入力画像を書く / 出力先をパターンで埋める / 期待値を積む
  //---------------------------------------------------------------------------
  task automatic prep_frame( input frame_t f, input bit expect_axi );
    int unsigned lb;
    int unsigned ib;
    int unsigned ob;
    logic [63:0] a;
    logic [63:0] lo;
    logic [63:0] hi;
    wexp_t       e;
    lb = f_line_bytes(f.w);
    ib = f_beats(lb, IN_BYTES);
    ob = f_beats(lb, OUT_BYTES);
    // 入力画像 (ビートの端数やコンテナの余りビットも乱数にしておく)
    for( int unsigned y=0; y<f.h; y++ ) begin
      for( int unsigned i=0; i<(ib*IN_BYTES); i++ ) begin
        a = f.src + (64'(y) * 64'(f.sstr)) + 64'(i);
        u_src.poke_byte(IN_ADDR_WIDTH'(a), 8'($urandom()));
      end
    end
    // 出力先: ガード領域を含めてパターンで埋める
    lo = f.dst - 64'(GUARD);
    hi = f.dst + (64'(f_hm1(f.h)) * 64'(f.dstr)) + 64'(ob*OUT_BYTES) + 64'(GUARD);
    for( a=lo; a<hi; a=a+64'd1 ) begin
      u_dst.poke_byte(OUT_ADDR_WIDTH'(a), f_pattern(a));
    end
    // 期待するバースト列と WSTRB
    if( expect_axi ) begin
      for( int unsigned y=0; y<f.h; y++ ) begin
        push_exp_bursts(1'b0, f.src + (64'(y) * 64'(f.sstr)), ib);
        push_exp_bursts(1'b1, f.dst + (64'(y) * 64'(f.dstr)), ob);
      end
      e.out_beats   = ob;
      e.last_bytes  = lb - ((ob-1)*OUT_BYTES);
      e.total_beats = ob * f.h;
      wexp_q.push_back(e);
    end
  endtask

  //---------------------------------------------------------------------------
  // ハングしたときはその場で終了する (後続のテストを流しても意味がない)
  //---------------------------------------------------------------------------
  task automatic abort_test();
    $display("=== tb_axi4_master_linebuf : TEST FAILED (timeout, aborted) ===");
    $finish;
  endtask

  //---------------------------------------------------------------------------
  // コマンド発行 (negedge で駆動し、受付は posedge でサンプルした n_acc で確認)
  //---------------------------------------------------------------------------
  task automatic send_cmd( input frame_t f );
    int unsigned na;
    int unsigned guard;
    @(negedge aclk);
    na             = n_acc;
    cmd_src_addr   = IN_ADDR_WIDTH'(f.src);
    cmd_dst_addr   = OUT_ADDR_WIDTH'(f.dst);
    cmd_src_stride = STRIDE_WIDTH'(f.sstr);
    cmd_dst_stride = STRIDE_WIDTH'(f.dstr);
    cmd_width      = XW'(f.w);
    cmd_height     = HEIGHT_WIDTH'(f.h);
    cmd_valid      = 1'b1;
    guard          = 0;
    while( (n_acc==na)&&(guard<TIMEOUT_CYC) ) begin
      @(negedge aclk);
      guard++;
    end
    cmd_valid = 1'b0;
    if( n_acc==na ) begin
      $display("[FAIL] command was not accepted (timeout)");
      abort_test();
    end
  endtask

  task automatic wait_done( input string tag, input int unsigned target );
    int unsigned guard;
    guard = 0;
    while( (n_done<target)&&(guard<TIMEOUT_CYC) ) begin
      @(negedge aclk);
      guard++;
    end
    if( n_done<target ) begin
      $display("[FAIL] %s : done timeout", tag);
      abort_test();
    end
  endtask

  //---------------------------------------------------------------------------
  // 照合
  //---------------------------------------------------------------------------
  // 発行されたバースト列
  task automatic check_bursts( input string tag );
    int unsigned n;
    if( u_src.ar_log_addr.size()!=exp_ar_addr.size() ) begin
      $display("[FAIL] %s : AR bursts %0d (exp %0d)", tag, u_src.ar_log_addr.size(), exp_ar_addr.size());
      err_cnt++;
    end
    n = (u_src.ar_log_addr.size()<exp_ar_addr.size()) ? u_src.ar_log_addr.size() : exp_ar_addr.size();
    for( int unsigned i=0; i<n; i++ ) begin
      if( (64'(u_src.ar_log_addr[i])!==exp_ar_addr[i])||(32'(u_src.ar_log_len[i])!==exp_ar_len[i]) ) begin
        $display("[FAIL] %s : AR #%0d addr=%h len=%0d (exp addr=%h len=%0d)", tag, i, u_src.ar_log_addr[i], u_src.ar_log_len[i], exp_ar_addr[i], exp_ar_len[i]);
        err_cnt++;
        break;
      end
    end
    if( u_dst.aw_log_addr.size()!=exp_aw_addr.size() ) begin
      $display("[FAIL] %s : AW bursts %0d (exp %0d)", tag, u_dst.aw_log_addr.size(), exp_aw_addr.size());
      err_cnt++;
    end
    n = (u_dst.aw_log_addr.size()<exp_aw_addr.size()) ? u_dst.aw_log_addr.size() : exp_aw_addr.size();
    for( int unsigned i=0; i<n; i++ ) begin
      if( (64'(u_dst.aw_log_addr[i])!==exp_aw_addr[i])||(32'(u_dst.aw_log_len[i])!==exp_aw_len[i]) ) begin
        $display("[FAIL] %s : AW #%0d addr=%h len=%0d (exp addr=%h len=%0d)", tag, i, u_dst.aw_log_addr[i], u_dst.aw_log_len[i], exp_aw_addr[i], exp_aw_len[i]);
        err_cnt++;
        break;
      end
    end
    u_src.ar_log_addr.delete();
    u_src.ar_log_len.delete();
    u_dst.aw_log_addr.delete();
    u_dst.aw_log_len.delete();
    exp_ar_addr.delete();
    exp_ar_len.delete();
    exp_aw_addr.delete();
    exp_aw_len.delete();
  endtask

  // 出力先メモリ (ガード領域を含む全バイト)
  //   written=0 のときは「1 バイトも書かれていない」ことを確認する
  task automatic check_mem( input string tag, input frame_t f, input bit written );
    int unsigned lb;
    int unsigned ob;
    int unsigned n_mis;
    logic [63:0] a;
    logic [63:0] lo;
    logic [63:0] hi;
    logic [63:0] rel;
    logic [63:0] y;
    logic [63:0] off;
    logic [7:0]  e;
    logic [7:0]  act;
    lb    = f_line_bytes(f.w);
    ob    = f_beats(lb, OUT_BYTES);
    n_mis = 0;
    lo    = f.dst - 64'(GUARD);
    hi    = f.dst + (64'(f_hm1(f.h)) * 64'(f.dstr)) + 64'(ob*OUT_BYTES) + 64'(GUARD);
    for( a=lo; a<hi; a=a+64'd1 ) begin
      e = f_pattern(a);
      if( written&&(a>=f.dst) ) begin
        rel = a - f.dst;
        if( f.dstr!=0 ) begin
          y   = rel / 64'(f.dstr);
          off = rel % 64'(f.dstr);
        end else begin
          y   = 64'd0;
          off = rel;
        end
        if( (y<64'(f.h))&&(off<64'(lb)) ) begin
          e = f_exp_byte(u_src.peek_byte(IN_ADDR_WIDTH'(f.src + (y * 64'(f.sstr)) + off)), 32'(off), f.w);
        end
      end
      act = u_dst.peek_byte(OUT_ADDR_WIDTH'(a));
      if( act!==e ) begin
        if( n_mis<4 ) begin
          $display("[FAIL] %s : dst[%h] = %h (exp %h)", tag, a, act, e);
        end
        n_mis++;
      end
    end
    if( n_mis!=0 ) begin
      $display("[FAIL] %s : %0d bytes mismatch (w=%0d h=%0d)", tag, n_mis, f.w, f.h);
      err_cnt++;
    end
  endtask

  //---------------------------------------------------------------------------
  // 1 フレーム実行
  //   exp_flags  : 期待する err_flags
  //   chk_data   : 出力先メモリを照合する (Write 側のエラー注入時は 0)
  //---------------------------------------------------------------------------
  int unsigned sf_nd;
  int unsigned sf_li;
  int unsigned sf_lo;

  // コマンドを出すところまで
  task automatic start_frame( input frame_t f, input bit [2:0] exp_flags );
    bit expect_axi;
    expect_axi = (f.w!=0)&&(f.h!=0)&&!exp_flags[2];
    sf_nd      = n_done;
    sf_li      = n_line_in;
    sf_lo      = n_line_out;
    u_dst.clear_wr_range();
    prep_frame(f, expect_axi);
    send_cmd(f);
  endtask

  // 完了待ちと照合
  task automatic finish_frame( input string tag, input frame_t f, input bit [2:0] exp_flags, input bit chk_data );
    int unsigned nd;
    int unsigned li;
    int unsigned lo;
    int unsigned lb;
    logic [63:0] exp_hi;
    bit          expect_axi;
    expect_axi = (f.w!=0)&&(f.h!=0)&&!exp_flags[2];
    lb         = f_line_bytes(f.w);
    nd         = sf_nd;
    li         = sf_li;
    lo         = sf_lo;
    wait_done(tag, nd+1);
    @(negedge aclk);
    if( last_flags!==exp_flags ) begin
      $display("[FAIL] %s : err_flags=%b (exp %b)", tag, last_flags, exp_flags);
      err_cnt++;
    end
    if( last_err!==(|exp_flags) ) begin
      $display("[FAIL] %s : done_err=%b (exp %b)", tag, last_err, |exp_flags);
      err_cnt++;
    end
    check_bursts(tag);
    if( expect_axi ) begin
      if( ((n_line_in-li)!=f.h)||((n_line_out-lo)!=f.h) ) begin
        $display("[FAIL] %s : line_in_done=%0d line_out_done=%0d (exp %0d)", tag, n_line_in-li, n_line_out-lo, f.h);
        err_cnt++;
      end
      if( chk_data ) begin
        check_mem(tag, f, 1'b1);
        if( u_dst.n_wbyte!=(f.h*lb) ) begin
          $display("[FAIL] %s : written bytes=%0d (exp %0d)", tag, u_dst.n_wbyte, f.h*lb);
          err_cnt++;
        end
        exp_hi = f.dst + ((64'(f.h) - 64'd1) * 64'(f.dstr)) + 64'(lb) - 64'd1;
        if( (64'(u_dst.wr_lo)!==f.dst)||(64'(u_dst.wr_hi)!==exp_hi) ) begin
          $display("[FAIL] %s : written range %h..%h", tag, u_dst.wr_lo, u_dst.wr_hi);
          err_cnt++;
        end
      end
    end else begin
      // 転送しないコマンド: AXI に何も出ず、出力先も変わらないこと
      check_mem(tag, f, 1'b0);
      if( ((n_line_in-li)!=0)||((n_line_out-lo)!=0)||(u_dst.n_wbyte!=0) ) begin
        $display("[FAIL] %s : unexpected activity for a rejected / empty command", tag);
        err_cnt++;
      end
    end
    n_frames++;
    n_pix_total += longint'(f.w) * longint'(f.h);
  endtask

  task automatic run_frame( input string tag, input frame_t f, input bit [2:0] exp_flags, input bit chk_data );
    start_frame(f, exp_flags);
    finish_frame(tag, f, exp_flags, chk_data);
  endtask

  // ランダムなフレームを作る
  function automatic frame_t f_rand_frame();
    frame_t      f;
    int unsigned lb;
    f.w    = f_rand_width();
    f.h    = f_rand_height();
    lb     = f_line_bytes(f.w);
    f.sstr = f_align_up(lb, IN_BYTES) + (IN_BYTES * $urandom_range(3,0));
    f.dstr = f_align_up(lb, OUT_BYTES) + (OUT_BYTES * $urandom_range(3,0));
    // たまに入力 stride = 0 (同じラインを繰り返し読む)
    if( $urandom_range(9,0)==0 ) begin
      f.sstr = 0;
    end
    f.src  = f_rand_base(IN_ADDR_WIDTH, 64'(f.h)*64'(f.sstr) + 64'(lb) + 64'd4096, IN_BYTES);
    f.dst  = f_rand_base(OUT_ADDR_WIDTH, 64'(f.h)*64'(f.dstr) + 64'(lb) + 64'd4096, OUT_BYTES);
    return f;
  endfunction

  task automatic set_stall( input int unsigned src_pct, input bit src_rwv, input int unsigned dst_pct, input bit dst_rwv );
    @(negedge aclk);
    u_src.stall_pct        = src_pct;
    u_src.ready_wait_valid = src_rwv;
    u_dst.stall_pct        = dst_pct;
    u_dst.ready_wait_valid = dst_rwv;
  endtask

  //---------------------------------------------------------------------------
  // メイン
  //---------------------------------------------------------------------------
  initial begin
    frame_t      f;
    frame_t      g;
    int unsigned lb;
    int unsigned ob;
    int unsigned nd;
    int unsigned t0;

    err_cnt        = 0;
    n_frames       = 0;
    n_pix_total    = 0;
    cmd_valid      = 1'b0;
    cmd_src_addr   = '0;
    cmd_dst_addr   = '0;
    cmd_src_stride = '0;
    cmd_dst_stride = '0;
    cmd_width      = '0;
    cmd_height     = '0;
    aresetn        = 1'b0;
    repeat( 10 ) begin
      @(negedge aclk);
    end
    aresetn = 1'b1;
    repeat( 5 ) begin
      @(negedge aclk);
    end

    $display("[INFO] IN: addr=%0d data=%0d burst=%0d / OUT: addr=%0d data=%0d burst=%0d / pixel=%0d (mem %0d, msb=%0d) x%0d per word / max width=%0d / lines=%0d"
            , IN_ADDR_WIDTH, IN_DATA_WIDTH, IN_MAX_BURST, OUT_ADDR_WIDTH, OUT_DATA_WIDTH, OUT_MAX_BURST
            , PIXEL_BITS, PIX_MEM_BITS, PIX_ALIGN_MSB, PIX_PER_WORD, MAX_LINE_PIXELS, NUM_LINES);

    //-------------------------------------------------------------------------
    // TEST1 : 基本 (stride がライン長ちょうど)
    //-------------------------------------------------------------------------
    f.w    = (MAX_LINE_PIXELS>=40) ? 40 : MAX_LINE_PIXELS;
    f.h    = NUM_LINES + 2;
    lb     = f_line_bytes(f.w);
    f.sstr = f_align_up(lb, IN_BYTES);
    f.dstr = f_align_up(lb, OUT_BYTES);
    f.src  = 64'h0000_0000_0001_0000;
    f.dst  = 64'h0000_0000_0002_0000;
    run_frame("TEST1", f, 3'b000, 1'b1);
    $display("[INFO] TEST1 (basic %0dx%0d) done : %0d cycles", f.w, f.h, done_cyc-acc_cyc);

    //-------------------------------------------------------------------------
    // TEST2 : 入力・出力とも 4KB 境界を跨ぐ (ページ末尾の 2 ビート手前から)
    //-------------------------------------------------------------------------
    f.w    = MAX_LINE_PIXELS;
    f.h    = 3;
    lb     = f_line_bytes(f.w);
    f.sstr = f_align_up(lb, IN_BYTES) + IN_BYTES;
    f.dstr = f_align_up(lb, OUT_BYTES) + (2*OUT_BYTES);
    f.src  = 64'h0000_0000_0003_1000 - 64'(2*IN_BYTES);
    f.dst  = 64'h0000_0000_0004_1000 - 64'(3*OUT_BYTES);
    run_frame("TEST2", f, 3'b000, 1'b1);
    $display("[INFO] TEST2 (4KB crossing) done");

    //-------------------------------------------------------------------------
    // TEST3 : 幅 / 高さの端
    //-------------------------------------------------------------------------
    for( int unsigned k=0; k<8; k++ ) begin
      case( k )
        0 : begin
          f.w = 1;
          f.h = 1;
        end
        1 : begin
          f.w = (PIX_PER_WORD>1) ? (PIX_PER_WORD-1) : 1;
          f.h = NUM_LINES;
        end
        2 : begin
          f.w = PIX_PER_WORD;
          f.h = NUM_LINES + 1;
        end
        3 : begin
          f.w = PIX_PER_WORD + 1;
          f.h = 2;
        end
        4 : begin
          f.w = MAX_LINE_PIXELS;
          f.h = 1;
        end
        5 : begin
          f.w = (MAX_LINE_PIXELS>1) ? (MAX_LINE_PIXELS-1) : 1;
          f.h = (2*NUM_LINES) + 1;
        end
        6 : begin
          f.w = 1;
          f.h = MAX_H;
        end
        default : begin
          f.w = MAX_LINE_PIXELS;
          f.h = MAX_H;
        end
      endcase
      if( f.w>MAX_LINE_PIXELS ) begin
        f.w = MAX_LINE_PIXELS;
      end
      lb     = f_line_bytes(f.w);
      f.sstr = f_align_up(lb, IN_BYTES);
      f.dstr = f_align_up(lb, OUT_BYTES);
      f.src  = 64'h0000_0000_0005_0000;
      f.dst  = 64'h0000_0000_0006_0000;
      run_frame($sformatf("TEST3.%0d", k), f, 3'b000, 1'b1);
    end
    // 最後の 1 本 (最大幅 x MAX_H ライン、ストール無し) の所要サイクルを性能の目安として出す
    $display("[INFO] TEST3 (width / height corners) done");
    $display("[INFO] PERF : %0dx%0d pixels in %0d cycles = %0.2f pixel/cycle (in %0.2f beat/cycle, out %0.2f beat/cycle)"
            , f.w, f.h, done_cyc-acc_cyc
            , real'(f.w*f.h)/real'(done_cyc-acc_cyc)
            , real'(f.h*f_beats(f_line_bytes(f.w), IN_BYTES))/real'(done_cyc-acc_cyc)
            , real'(f.h*f_beats(f_line_bytes(f.w), OUT_BYTES))/real'(done_cyc-acc_cyc));

    //-------------------------------------------------------------------------
    // TEST4 : 出力側を完全に止める → scratchpad が NUM_LINES 本で満杯になり、
    //         入力側の AR 発行も止まる。再開すると最後まで流れる
    //   (出力側の FIFO だけで全ラインを吸収できてしまう構成では、満杯の確認は省く)
    //-------------------------------------------------------------------------
    set_stall(0, 1'b0, 100, 1'b0);
    f.w    = MAX_LINE_PIXELS;
    f.h    = MAX_H;
    lb     = f_line_bytes(f.w);
    f.sstr = f_align_up(lb, IN_BYTES);
    f.dstr = f_align_up(lb, OUT_BYTES);
    f.src  = 64'h0000_0000_0007_0000;
    f.dst  = 64'h0000_0000_0008_0000;
    start_frame(f, 3'b000);
    repeat( 30000 ) begin
      @(negedge aclk);
    end
    ob = f_beats(lb, OUT_BYTES);
    if( ((MAX_H-NUM_LINES-1)*ob)>(OUT_FIFO_DEPTH+16) ) begin
      t0 = u_src.n_ar;
      if( (sp_level32!=NUM_LINES)||!busy ) begin
        $display("[FAIL] TEST4 : scratchpad is not full while the output is stopped (sp_level=%0d)", sp_level);
        err_cnt++;
      end
      repeat( 2000 ) begin
        @(negedge aclk);
      end
      if( (u_src.n_ar!=t0)||(sp_level32!=NUM_LINES) ) begin
        $display("[FAIL] TEST4 : AR kept being issued while the scratchpad is full");
        err_cnt++;
      end
      $display("[INFO] TEST4 : scratchpad full check done (sp_level=%0d)", sp_level);
    end
    set_stall(0, 1'b0, 30, 1'b0);
    finish_frame("TEST4", f, 3'b000, 1'b1);
    set_stall(0, 1'b0, 0, 1'b0);
    $display("[INFO] TEST4 (output stopped, then resumed) done : max sp_level=%0d", max_sp_level);

    //-------------------------------------------------------------------------
    // TEST5 : READY が VALID を待つスレーブ (両側)
    //-------------------------------------------------------------------------
    set_stall(30, 1'b1, 30, 1'b1);
    f = f_rand_frame();
    run_frame("TEST5", f, 3'b000, 1'b1);
    set_stall(0, 1'b0, 0, 1'b0);
    $display("[INFO] TEST5 (READY waits for VALID) done");

    //-------------------------------------------------------------------------
    // TEST6 : SLVERR 注入
    //-------------------------------------------------------------------------
    f.w    = MAX_LINE_PIXELS;
    f.h    = NUM_LINES + 1;
    lb     = f_line_bytes(f.w);
    f.sstr = f_align_up(lb, IN_BYTES);
    f.dstr = f_align_up(lb, OUT_BYTES);
    f.src  = 64'h0000_0000_0009_0000;
    f.dst  = 64'h0000_0000_000A_0000;
    // 入力側: 2 ライン目の先頭ビート (データは読めるので出力は照合する)
    u_src.err_lo = IN_ADDR_WIDTH'(f.src + 64'(f.sstr));
    u_src.err_hi = IN_ADDR_WIDTH'(f.src + 64'(f.sstr) + 64'(IN_BYTES-1));
    run_frame("TEST6a", f, 3'b001, 1'b1);
    u_src.err_lo = '1;
    u_src.err_hi = '0;
    // 出力側: 最終ラインの先頭ビート
    u_dst.err_lo = OUT_ADDR_WIDTH'(f.dst + ((64'(f.h) - 64'd1) * 64'(f.dstr)));
    u_dst.err_hi = OUT_ADDR_WIDTH'(f.dst + ((64'(f.h) - 64'd1) * 64'(f.dstr)) + 64'(OUT_BYTES-1));
    run_frame("TEST6b", f, 3'b010, 1'b0);
    // 両側
    u_src.err_lo = IN_ADDR_WIDTH'(f.src);
    u_src.err_hi = IN_ADDR_WIDTH'(f.src + 64'(IN_BYTES-1));
    run_frame("TEST6c", f, 3'b011, 1'b0);
    u_src.err_lo = '1;
    u_src.err_hi = '0;
    u_dst.err_lo = '1;
    u_dst.err_hi = '0;
    // エラーの後、次のフレームは正常に流れる (エラーフラグが残らない)
    run_frame("TEST6d", f, 3'b000, 1'b1);
    $display("[INFO] TEST6 (SLVERR -> err_flags) done");

    //-------------------------------------------------------------------------
    // TEST7 : コマンド誤り / 空コマンド
    //-------------------------------------------------------------------------
    f.w    = (MAX_LINE_PIXELS>=8) ? 8 : MAX_LINE_PIXELS;
    f.h    = 2;
    lb     = f_line_bytes(f.w);
    f.sstr = f_align_up(lb, IN_BYTES);
    f.dstr = f_align_up(lb, OUT_BYTES);
    f.src  = 64'h0000_0000_000B_0000;
    f.dst  = 64'h0000_0000_000C_0000;
    g      = f;
    g.w    = 0;
    run_frame("TEST7.w0", g, 3'b000, 1'b0);
    g      = f;
    g.h    = 0;
    run_frame("TEST7.h0", g, 3'b000, 1'b0);
    if( ((1<<XW)-1)>MAX_LINE_PIXELS ) begin
      g   = f;
      g.w = MAX_LINE_PIXELS + 1;
      run_frame("TEST7.wide", g, 3'b100, 1'b0);
    end
    if( IN_BYTES>1 ) begin
      g     = f;
      g.src = f.src + 64'd1;
      run_frame("TEST7.src", g, 3'b100, 1'b0);
      g      = f;
      g.sstr = f.sstr + (IN_BYTES/2);
      run_frame("TEST7.sstr", g, 3'b100, 1'b0);
    end
    if( OUT_BYTES>1 ) begin
      g     = f;
      g.dst = f.dst + 64'(OUT_BYTES-1);
      run_frame("TEST7.dst", g, 3'b100, 1'b0);
      g      = f;
      g.dstr = f.dstr + 1;
      run_frame("TEST7.dstr", g, 3'b100, 1'b0);
    end
    run_frame("TEST7.ok", f, 3'b000, 1'b1);
    $display("[INFO] TEST7 (rejected / empty commands) done");

    //-------------------------------------------------------------------------
    // TEST8 : busy 中に次のコマンドを待たせる
    //   1 本目の実行中に 2 本目の cmd_valid を立てておき、1 本目の done の後で
    //   受け付けられること。2 本とも結果が正しいこと
    //-------------------------------------------------------------------------
    f.w    = MAX_LINE_PIXELS;
    f.h    = NUM_LINES + 1;
    lb     = f_line_bytes(f.w);
    f.sstr = f_align_up(lb, IN_BYTES);
    f.dstr = f_align_up(lb, OUT_BYTES);
    f.src  = 64'h0000_0000_000D_0000;
    f.dst  = 64'h0000_0000_000E_0000;
    g      = f;
    g.w    = (MAX_LINE_PIXELS>3) ? (MAX_LINE_PIXELS/3) : 1;
    g.h    = 2;
    lb     = f_line_bytes(g.w);
    g.sstr = f_align_up(lb, IN_BYTES) + IN_BYTES;
    g.dstr = f_align_up(lb, OUT_BYTES) + OUT_BYTES;
    g.src  = f.src + (((64'(f.h) * 64'(f.sstr)) + 64'd8191) & ~64'd4095);
    g.dst  = f.dst + (((64'(f.h) * 64'(f.dstr)) + 64'd8191) & ~64'd4095);
    nd     = n_done;
    prep_frame(f, 1'b1);
    prep_frame(g, 1'b1);
    send_cmd(f);
    t0 = n_done;
    send_cmd(g);
    if( (t0!=nd)||(n_done!=(nd+1)) ) begin
      $display("[FAIL] TEST8 : second command was not held until the first one finished (done %0d -> %0d)", t0-nd, n_done-nd);
      err_cnt++;
    end
    wait_done("TEST8", nd+2);
    @(negedge aclk);
    if( last_flags!==3'b000 ) begin
      $display("[FAIL] TEST8 : err_flags=%b", last_flags);
      err_cnt++;
    end
    check_bursts("TEST8");
    check_mem("TEST8 first", f, 1'b1);
    check_mem("TEST8 second", g, 1'b1);
    n_frames += 2;
    $display("[INFO] TEST8 (command held while busy) done");

    //-------------------------------------------------------------------------
    // TEST9 : ランダムフレーム x 4 条件
    //-------------------------------------------------------------------------
    for( int unsigned ph=0; ph<4; ph++ ) begin
      case( ph )
        0 : begin
          set_stall(0, 1'b0, 0, 1'b0);
        end
        1 : begin
          set_stall(70, 1'b0, 0, 1'b0);
        end
        2 : begin
          set_stall(0, 1'b0, 80, 1'b0);
        end
        default : begin
          set_stall(40, 1'b1, 40, 1'b1);
        end
      endcase
      for( int unsigned n=0; n<N_RAND; n++ ) begin
        f = f_rand_frame();
        run_frame($sformatf("TEST9.%0d.%0d", ph, n), f, 3'b000, 1'b1);
      end
    end
    set_stall(0, 1'b0, 0, 1'b0);
    $display("[INFO] TEST9 (random frames x 4 conditions, %0d each) done", N_RAND);

    //-------------------------------------------------------------------------
    // 集計
    //-------------------------------------------------------------------------
    repeat( 10 ) begin
      @(negedge aclk);
    end
    if( (u_src.n_viol!=0)||(u_dst.n_viol!=0) ) begin
      $display("[FAIL] protocol violations : src=%0d dst=%0d", u_src.n_viol, u_dst.n_viol);
      err_cnt++;
    end
    if( (u_dut.u_scratchpad.sim_conflict_cnt!=0)||(u_dut.u_scratchpad.sim_uninit_rd_cnt!=0) ) begin
      $display("[FAIL] scratchpad : %0d slot conflicts / out-of-range writes, %0d reads of unwritten words"
              , u_dut.u_scratchpad.sim_conflict_cnt, u_dut.u_scratchpad.sim_uninit_rd_cnt);
      err_cnt++;
    end
    if( mon_err_cnt!=0 ) begin
      $display("[FAIL] monitor errors : %0d", mon_err_cnt);
      err_cnt++;
    end
    if( busy||(wexp_q.size()!=0) ) begin
      $display("[FAIL] DUT still busy or expected W beats left at the end");
      err_cnt++;
    end
    $display("[INFO] frames=%0d pixels=%0d AR bursts=%0d (max len %0d) R beats=%0d AW bursts=%0d (max len %0d) W beats=%0d max sp_level=%0d"
            , n_frames, n_pix_total, u_src.n_ar, u_src.max_arlen, u_src.n_rbeat, u_dst.n_aw, u_dst.max_awlen, u_dst.n_wbeat, max_sp_level);
    if( err_cnt==0 ) begin
      $display("=== tb_axi4_master_linebuf : TEST PASSED ===");
    end else begin
      $display("=== tb_axi4_master_linebuf : TEST FAILED (%0d errors) ===", err_cnt);
    end
    $finish;
  end

  // 全体のタイムアウト
  initial begin
    #2s;
    $display("=== tb_axi4_master_linebuf : TEST FAILED (global timeout) ===");
    $finish;
  end

endmodule
