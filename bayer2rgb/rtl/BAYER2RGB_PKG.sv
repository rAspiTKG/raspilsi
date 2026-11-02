// ============================================================================
// BAYER2RGB_PKG : 構成定数・型・共通関数
//   構成定数はここで1か所だけ定義する。PPCはコンパイル時に
//   +define+BAYER2RGB_PPC=4 のように変更できる(1/2/4/8)。
// ============================================================================
`ifndef BAYER2RGB_PPC
  `define BAYER2RGB_PPC 8
`endif

package BAYER2RGB_PKG;

  // --------------------------------------------------------------------------
  // 構成定数
  // --------------------------------------------------------------------------
  localparam int PPC        = `BAYER2RGB_PPC;  // 1クロックあたりの画素数(1/2/4/8)
  localparam int IN_BITS    = 14;              // 入力画素のビット幅
  localparam int OUT_BITS   = 8;               // 出力1色のビット幅
  localparam int MAX_WIDTH  = 3840;            // 最大幅(画素)
  localparam int MAX_HEIGHT = 2160;            // 最大高さ(ライン)
  localparam int MIN_WIDTH  = 16;              // 最小幅(画素)
  localparam int MIN_HEIGHT = 16;              // 最小高さ(ライン)

  localparam int MEM_AW     = 40;              // AXI4マスタ アドレス幅
  localparam int MEM_DW     = 128;             // AXI4マスタ データ幅
  localparam int MEM_IDW    = 4;               // AXI4マスタ ID幅
  localparam int MEM_BYTES  = MEM_DW/8;        // 1ビートのバイト数(16)
  localparam int MEM_SIZE   = $clog2(MEM_BYTES); // AxSIZE(4 = 16バイト)
  localparam int BURST_MAX  = 16;              // 最大バースト長(ビート)
  localparam int RD_OST     = 4;               // 読み出しの同時発行バースト数
  localparam int WR_OST     = 4;               // 書き込みの同時発行バースト数
  localparam int RD_BUF_DEPTH = RD_OST*BURST_MAX; // 読み出しバッファ段数(64)
  localparam int WR_BUF_DEPTH = WR_OST*BURST_MAX; // 書き込みバッファ段数(64)

  localparam int REG_AW     = 12;              // AXI4-Lite アドレス幅
  localparam int REG_DW     = 32;              // AXI4-Lite データ幅
  localparam logic [31:0] IP_VERSION = 32'h0001_0000;

  // --------------------------------------------------------------------------
  // 派生定数
  // --------------------------------------------------------------------------
  localparam int LOG2_PPC   = $clog2(PPC);
  localparam int WIDTH_W    = $clog2(MAX_WIDTH+1);   // 幅の設定値ビット数(12)
  localparam int HEIGHT_W   = $clog2(MAX_HEIGHT+2);  // ライン番号(掃き出しラインHを含む, 12)
  localparam int K_MAX      = MAX_WIDTH/PPC;         // 1ラインの最大ビート数(480)
  localparam int COL_W      = $clog2(K_MAX+1);       // 列番号(掃き出し列Kを含む, 9)
  localparam int LB_AW      = $clog2(K_MAX);         // ラインバッファのアドレス幅(9)
  localparam int BEAT_W     = PPC*IN_BITS;           // COREへの入力1ビートの幅(112)
  localparam int RGB_BYTES  = PPC*3;                 // 出力1ビートのバイト数(24)
  localparam int RGB_W      = RGB_BYTES*OUT_BITS;    // 出力1ビートのRGB幅(192)
  localparam int OUT_DATA_W = RGB_W+3;               // {eof, eol, sof, rgb}(195)
  localparam int PIX_MAX    = (1<<IN_BITS)-1;        // 画素の最大値(16383)
  localparam int PIX_MB     = MEM_BYTES/2;           // メモリ1ビートの画素数(8)
  localparam int SUB_BEATS  = PIX_MB/PPC;            // メモリ1ビートあたりのCOREビート数
  localparam int RD_BPL_MAX = MAX_WIDTH/PIX_MB;      // 1ラインの読み出しビート数の最大(480)
  localparam int RD_BPL_W   = $clog2(RD_BPL_MAX+1);  // (9)
  localparam int WR_BPL_MAX = (MAX_WIDTH*3+MEM_BYTES-1)/MEM_BYTES; // 書き込みビート数の最大(720)
  localparam int WR_BPL_W   = $clog2(WR_BPL_MAX+1);  // (10)
  localparam int BLEN_W     = $clog2(BURST_MAX+1);   // バースト長(1..16)のビット数(5)

  localparam int WBG_W      = 16;                    // WBゲイン(U4.12)
  localparam int WBG_FRAC   = 12;
  localparam int FCS_GAIN_W = 8;
  localparam int GM_KNOTS   = 37;                    // ガンマの折れ点数
  localparam int GM_KW      = 12;                    // 折れ点の値(8.4固定小数点)
  localparam int GM_SEG_W   = 6;                     // 区間番号(0..35)
  localparam int GM_FRAC_W  = 11;                    // 区間内の位置(0..2047)

  localparam int OFIFO_DEPTH = 32;                   // COREの出力FIFO段数
  localparam int OFIFO_CW    = $clog2(OFIFO_DEPTH+3); // 使用数(先読み2段を含む)のビット数

  // --------------------------------------------------------------------------
  // レジスタのアドレス(バイトアドレス)
  // --------------------------------------------------------------------------
  localparam logic [REG_AW-1:0] A_CONTROL       = 12'h000;
  localparam logic [REG_AW-1:0] A_STATUS        = 12'h004;
  localparam logic [REG_AW-1:0] A_IRQ_STATUS    = 12'h008;
  localparam logic [REG_AW-1:0] A_IRQ_ENABLE    = 12'h00C;
  localparam logic [REG_AW-1:0] A_VERSION       = 12'h010;
  localparam logic [REG_AW-1:0] A_HWCFG0        = 12'h014;
  localparam logic [REG_AW-1:0] A_HWCFG1        = 12'h018;
  localparam logic [REG_AW-1:0] A_FRAME_COUNT   = 12'h01C;
  localparam logic [REG_AW-1:0] A_ACTIVE_WIDTH  = 12'h020;
  localparam logic [REG_AW-1:0] A_ACTIVE_HEIGHT = 12'h024;
  localparam logic [REG_AW-1:0] A_BAYER_PHASE   = 12'h028;
  localparam logic [REG_AW-1:0] A_FUNC_EN       = 12'h02C;
  localparam logic [REG_AW-1:0] A_BLC_R_GR      = 12'h030;
  localparam logic [REG_AW-1:0] A_BLC_GB_B      = 12'h034;
  localparam logic [REG_AW-1:0] A_WB_R_GR       = 12'h038;
  localparam logic [REG_AW-1:0] A_WB_GB_B       = 12'h03C;
  localparam logic [REG_AW-1:0] A_FCS_PARAM     = 12'h040;
  localparam logic [REG_AW-1:0] A_TPG_SEL       = 12'h044;
  localparam logic [REG_AW-1:0] A_TPG_COLOR     = 12'h048;
  localparam logic [REG_AW-1:0] A_SRC_ADDR_L    = 12'h050;
  localparam logic [REG_AW-1:0] A_SRC_ADDR_H    = 12'h054;
  localparam logic [REG_AW-1:0] A_SRC_STRIDE    = 12'h058;
  localparam logic [REG_AW-1:0] A_DST_ADDR_L    = 12'h060;
  localparam logic [REG_AW-1:0] A_DST_ADDR_H    = 12'h064;
  localparam logic [REG_AW-1:0] A_DST_STRIDE    = 12'h068;
  localparam logic [REG_AW-1:0] A_AXI_ATTR      = 12'h070;
  localparam logic [REG_AW-1:0] A_GAMMA_KNOT    = 12'h100;  // 0x100〜0x148(1ワードに2点)
  localparam int                GM_WORDS        = (GM_KNOTS+1)/2; // 19ワード

  // CONTROLのビット位置
  localparam int CTL_START        = 0;
  localparam int CTL_REG_UPDATE   = 1;
  localparam int CTL_BYPASS       = 4;
  localparam int CTL_TEST_PATTERN = 5;
  localparam int CTL_AUTO_RESTART = 7;
  localparam int CTL_SW_RESET     = 31;

  // IRQ_STATUS / IRQ_ENABLE のビット位置
  localparam int IRQ_FRAME_DONE   = 0;
  localparam int IRQ_RD_ERR       = 1;
  localparam int IRQ_WR_ERR       = 2;

  // パイプライン各段のレイテンシ(IN_CTRLのクレジット計算に使う)
  localparam int LAT_BLC    = 1;
  localparam int LAT_WB     = 2;
  localparam int LAT_LBUF   = 2;
  localparam int LAT_DMSC   = 2;
  localparam int LAT_FCS    = 3;
  localparam int LAT_GAMMA  = 3;
  localparam int LAT_OFMT   = 1;
  localparam int PIPE_LAT   = LAT_BLC+LAT_WB+LAT_LBUF+LAT_DMSC+LAT_FCS+LAT_GAMMA+LAT_OFMT; // 14
  localparam int CREDIT_WIN = PIPE_LAT+2;            // 発行から使用数に反映されるまで(余裕込み)
  localparam int CREDIT_CW  = $clog2(CREDIT_WIN+1);

  // --------------------------------------------------------------------------
  // AXIの固定値
  // --------------------------------------------------------------------------
  localparam logic [1:0] AXI_BURST_INCR = 2'b01;
  localparam logic [1:0] AXI_RESP_OKAY  = 2'b00;
  localparam logic [MEM_IDW-1:0] MEM_RD_ID = '0;
  localparam logic [MEM_IDW-1:0] MEM_WR_ID = '0;

  // --------------------------------------------------------------------------
  // ガンマの初期値(sRGB、12bit = 8.4固定小数点)。[0]が先頭の折れ点
  // --------------------------------------------------------------------------
  localparam logic [GM_KNOTS-1:0][GM_KW-1:0] GM_SRGB = {
    12'd4080, 12'd3847, 12'd3594, 12'd3315, 12'd3000, 12'd2826, 12'd2636, 12'd2427,
    12'd2191, 12'd2061, 12'd1919, 12'd1762, 12'd1585, 12'd1487, 12'd1381, 12'd1264,
    12'd1131, 12'd1058, 12'd978,  12'd890,  12'd791,  12'd736,  12'd677,  12'd611,
    12'd537,  12'd495,  12'd451,  12'd401,  12'd346,  12'd315,  12'd281,  12'd244,
    12'd203,  12'd154,  12'd103,  12'd51,   12'd0
  };

  // --------------------------------------------------------------------------
  // 設定(制御系 → 映像系)
  // --------------------------------------------------------------------------
  typedef struct packed {
    logic                               reg_update;  // 1: STARTのときに新しい設定を取り込む
    logic                               bypass;      // デモザイクを通さずBayer値をR=G=Bで出す
    logic                               tpg_en;      // テストパターン出力(入力メモリは読まない)
    logic [1:0]                         tpg_sel;     // 0:カラーバー 1:ランプ 2:チェッカー 3:単色
    logic [23:0]                        tpg_color;   // 単色パターンの色 {R,G,B}
    logic [WIDTH_W-1:0]                 width;       // 幅(画素)
    logic [HEIGHT_W-1:0]                height;      // 高さ(ライン)
    logic [1:0]                         phase;       // 0:RGGB 1:GRBG 2:GBRG 3:BGGR
    logic                               blc_en;
    logic                               wb_en;
    logic                               fcs_en;
    logic                               gamma_en;
    logic [3:0][IN_BITS-1:0]            blc;         // [0]R [1]Gr [2]Gb [3]B
    logic [3:0][WBG_W-1:0]              wbg;         // [0]R [1]Gr [2]Gb [3]B (U4.12)
    logic [IN_BITS-1:0]                 fcs_th;      // 彩度抑制を始めるエッジ量
    logic [FCS_GAIN_W-1:0]              fcs_gain;    // 彩度抑制の傾き
    logic [GM_KNOTS-1:0][GM_KW-1:0]     gm_knot;     // ガンマの折れ点
    logic [MEM_AW-1:0]                  src_addr;    // Bayer画像の先頭アドレス(16バイト境界)
    logic [23:0]                        src_stride;  // Bayer画像のライン間隔(バイト, 16の倍数)
    logic [MEM_AW-1:0]                  dst_addr;    // RGB画像の先頭アドレス(16バイト境界)
    logic [23:0]                        dst_stride;  // RGB画像のライン間隔(バイト, 16の倍数)
    logic [3:0]                         arcache;
    logic [3:0]                         awcache;
    logic [2:0]                         arprot;
    logic [2:0]                         awprot;
    logic [3:0]                         arqos;
    logic [3:0]                         awqos;
  } cfg_t;

  localparam int CFG_W = $bits(cfg_t);

  // 映像系へ渡す制御(フレームの設定 + 開始パルス + ソフトリセットパルス)
  typedef struct packed {
    cfg_t                               cfg;
    logic                               start;
    logic                               sw_rst;
  } ctl_t;

  // 映像系から制御系へのイベント(制御系のパルス)。1本のハンドシェイクで順番どおりに届く
  typedef struct packed {
    logic                               frame_done;  // フレームの書き込み完了
    logic                               rd_err;      // 読み出し応答エラー
    logic                               wr_err;      // 書き込み応答エラー
    logic                               srst_done;   // ソフトリセットの後始末が完了
  } evt_t;


  // DMAからCDCへの状態(映像系)
  typedef struct packed {
    logic                               busy;        // レベル: 動作中(ソフトリセットの後始末を含む)
    logic                               rd_err;      // パルス: 読み出し応答エラー
  } rd_evt_t;

  typedef struct packed {
    logic                               busy;        // レベル: 動作中(ソフトリセットの後始末を含む)
    logic                               frame_done;  // パルス: フレームの全応答を受信
    logic                               wr_err;      // パルス: 書き込み応答エラー
  } wr_evt_t;

  // --------------------------------------------------------------------------
  // BRIDGEとDMAの間のvld/busy/dataの中身
  // --------------------------------------------------------------------------
  typedef struct packed {
    logic [3:0]                         qos;
    logic [2:0]                         prot;
    logic [3:0]                         cache;
    logic [7:0]                         len;         // ビート数-1
    logic [MEM_AW-1:0]                  addr;
  } axreq_t;

  typedef struct packed {
    logic [1:0]                         resp;
    logic                               last;
    logic [MEM_DW-1:0]                  data;
  } rbeat_t;

  typedef struct packed {
    logic                               last;
    logic [MEM_BYTES-1:0]               strb;
    logic [MEM_DW-1:0]                  data;
  } wbeat_t;

  // COREの出力ビート(CORE → WR_DMA)
  //   rgb のバイト 3i+0 / 3i+1 / 3i+2 が画素 i の R / G / B(メモリのバイト順と同じ)
  typedef struct packed {
    logic                               eof;         // フレームの最後のビート
    logic                               eol;         // ラインの最後のビート
    logic                               sof;         // フレームの最初のビート
    logic [RGB_W-1:0]                   rgb;
  } obeat_t;

  localparam int AXREQ_W = $bits(axreq_t);   // 59
  localparam int RBEAT_W = $bits(rbeat_t);   // 131
  localparam int WBEAT_W = $bits(wbeat_t);   // 145
  localparam int BRESP_W = 2;

  // AXI4-Liteの要求と応答(AXIL_BRIDGE ⇔ REG)
  typedef struct packed {
    logic                               we;
    logic [REG_DW/8-1:0]                strb;
    logic [REG_AW-1:0]                  addr;
    logic [REG_DW-1:0]                  wdata;
  } regreq_t;

  typedef struct packed {
    logic [1:0]                         resp;
    logic [REG_DW-1:0]                  rdata;
  } regrsp_t;

  localparam int REGREQ_W = $bits(regreq_t); // 49
  localparam int REGRSP_W = $bits(regrsp_t); // 34

  // --------------------------------------------------------------------------
  // CORE内部のパイプライン(止まらずに流れる。vldはステップの有無)
  // --------------------------------------------------------------------------
  // ステップ: 入力ビート / 行末の掃き出し(fcol) / 掃き出しライン(frow)
  typedef struct packed {
    logic                               vld;
    logic                               fcol;        // 行末の掃き出し(列K)
    logic                               frow;        // 掃き出しライン(ラインH)
    logic [HEIGHT_W-1:0]                line;        // 入力ライン番号(掃き出しラインはH)
    logic [COL_W-1:0]                   col;         // 列(ビート)番号
    logic [PPC-1:0][IN_BITS-1:0]        pix;
  } stp_t;

  // 3行 × (PPC+2)画素の窓。win[行][列]、行 0:上 1:中 2:下、列 j は x = oc*PPC-1+j
  typedef struct packed {
    logic                               vld;
    logic                               sof;
    logic                               eol;
    logic                               eof;
    logic [HEIGHT_W-1:0]                y;           // 出力ライン番号
    logic [COL_W-1:0]                   oc;          // 出力列(ビート)番号
    logic [2:0][PPC+1:0][IN_BITS-1:0]   win;
  } win_t;

  // デモザイクの出力
  typedef struct packed {
    logic                               vld;
    logic                               sof;
    logic                               eol;
    logic                               eof;
    logic [HEIGHT_W-1:0]                y;
    logic [COL_W-1:0]                   oc;
    logic [PPC-1:0][2:0][IN_BITS-1:0]   rgb;         // [画素][0:R 1:G 2:B]
    logic [PPC-1:0][IN_BITS-1:0]        edg;         // エッジ量
  } dm_t;

  // 14bit RGB
  typedef struct packed {
    logic                               vld;
    logic                               sof;
    logic                               eol;
    logic                               eof;
    logic [HEIGHT_W-1:0]                y;
    logic [COL_W-1:0]                   oc;
    logic [PPC-1:0][2:0][IN_BITS-1:0]   rgb;
  } fc_t;

  // 8bit RGB
  typedef struct packed {
    logic                               vld;
    logic                               sof;
    logic                               eol;
    logic                               eof;
    logic [HEIGHT_W-1:0]                y;
    logic [COL_W-1:0]                   oc;
    logic [PPC-1:0][2:0][OUT_BITS-1:0]  rgb;
  } gm_t;

  // --------------------------------------------------------------------------
  // 共通関数
  // --------------------------------------------------------------------------
  // 有効幅: [MIN_WIDTH, MAX_WIDTH] に収め、8画素単位に切り捨てる
  function automatic logic [WIDTH_W-1:0] f_width( input logic [WIDTH_W-1:0] w );
    logic [WIDTH_W-1:0] t;
    begin
      t = w;
      if( w<WIDTH_W'(MIN_WIDTH) ) begin
        t = WIDTH_W'(MIN_WIDTH);
      end else if( w>WIDTH_W'(MAX_WIDTH) ) begin
        t = WIDTH_W'(MAX_WIDTH);
      end
      f_width = t&~WIDTH_W'(7);
    end
  endfunction

  // 有効高さ: [MIN_HEIGHT, MAX_HEIGHT] に収め、偶数に切り捨てる
  function automatic logic [HEIGHT_W-1:0] f_height( input logic [HEIGHT_W-1:0] h );
    logic [HEIGHT_W-1:0] t;
    begin
      t = h;
      if( h<HEIGHT_W'(MIN_HEIGHT) ) begin
        t = HEIGHT_W'(MIN_HEIGHT);
      end else if( h>HEIGHT_W'(MAX_HEIGHT) ) begin
        t = HEIGHT_W'(MAX_HEIGHT);
      end
      f_height = t&~HEIGHT_W'(1);
    end
  endfunction

  // 1ラインのCOREビート数(K = 幅/PPC)
  function automatic logic [COL_W-1:0] f_kbeats( input logic [WIDTH_W-1:0] w );
    logic [WIDTH_W-1:0] t;
    begin
      t = f_width(w);
      f_kbeats = COL_W'(t>>LOG2_PPC);
    end
  endfunction

  // 1ラインの読み出しビート数(幅×2バイト/16)
  function automatic logic [RD_BPL_W-1:0] f_rd_bpl( input logic [WIDTH_W-1:0] w );
    logic [WIDTH_W-1:0] t;
    begin
      t = f_width(w);
      f_rd_bpl = RD_BPL_W'(t>>3);
    end
  endfunction

  // 1ラインの書き込みビート数(幅×3バイト/16 の切り上げ)
  function automatic logic [WR_BPL_W-1:0] f_wr_bpl( input logic [WIDTH_W-1:0] w );
    logic [WIDTH_W+1:0] t;
    begin
      t = (WIDTH_W+2)'(f_width(w))*(WIDTH_W+2)'(3);
      f_wr_bpl = WR_BPL_W'((t+(WIDTH_W+2)'(MEM_BYTES-1))>>MEM_SIZE);
    end
  endfunction

  // バースト長: min(BURST_MAX, 残りビート数, 4KB境界までのビート数)
  //   a4k: アドレスの[11:4](4KB内のビート位置)
  function automatic logic [BLEN_W-1:0] f_blen( input logic [7:0] a4k, input logic [WR_BPL_W-1:0] rem );
    logic [8:0] b4k;
    logic [BLEN_W-1:0] n;
    begin
      b4k = 9'd256-{1'b0, a4k};
      n   = BLEN_W'(BURST_MAX);
      if( rem<WR_BPL_W'(n) ) begin
        n = BLEN_W'(rem);
      end
      if( b4k<9'(n) ) begin
        n = BLEN_W'(b4k);
      end
      f_blen = n;
    end
  endfunction

  // COREビートのi番目の画素のx座標の偶奇
  //   col0: ビート番号の最下位ビット、i0: ビート内の画素番号の最下位ビット
  function automatic logic f_xpar( input logic col0, input logic i0 );
    begin
      if( PPC==1 ) begin
        f_xpar = col0;
      end else begin
        f_xpar = i0;
      end
    end
  endfunction

  // Bayerの色位置: 0:R 1:Gr 2:Gb 3:B
  function automatic logic [1:0] f_site( input logic [1:0] phase, input logic ypar, input logic xpar );
    begin
      f_site = {ypar^phase[1], xpar^phase[0]};
    end
  endfunction

  // 設定の初期値(REGのリセット値と同じ)
  function automatic cfg_t f_cfg_default();
    cfg_t c;
    begin
      c = '0;
      c.reg_update = 1'b1;
      c.width      = WIDTH_W'(MAX_WIDTH);
      c.height     = HEIGHT_W'(MAX_HEIGHT);
      c.blc_en     = 1'b1;
      c.wb_en      = 1'b1;
      c.fcs_en     = 1'b1;
      c.gamma_en   = 1'b1;
      for( int i=0; i<4; i++ ) begin
        c.wbg[i] = WBG_W'(1<<WBG_FRAC);
      end
      c.fcs_th     = IN_BITS'(256);
      c.fcs_gain   = FCS_GAIN_W'(16);
      c.gm_knot    = GM_SRGB;
      c.arcache    = 4'b0011;
      c.awcache    = 4'b0011;
      f_cfg_default = c;
    end
  endfunction

endpackage
