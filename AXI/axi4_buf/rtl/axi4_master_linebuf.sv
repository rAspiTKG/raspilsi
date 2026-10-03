//=============================================================================
// axi4_master_linebuf.sv
//-----------------------------------------------------------------------------
//  画像処理向けの AXI4 マスタ + ライン単位 scratchpad SRAM。
//
//  入力側 AXI (Read) で画像を 1 ラインずつ読み、モジュール内の scratchpad SRAM に
//  ライン単位で格納する。溜まったラインを出力側 AXI (Write) へ書き出す。
//
//    cmd (src, dst, stride, width, height)
//         |
//    m_axi_in_*                                                    m_axi_out_*
//    AR / R --> [rd engine] --> [FIFO] --> [gearbox] --+
//                                         (ビート→画素) |
//                                                      v
//                                  scratchpad SRAM (NUM_LINES 本、1 本 = 1 ライン)
//                                                      |
//    AW / W / B <-- [wr engine] <-- [FIFO] <-- [gearbox] <--+
//                                              (画素→ビート)
//
//  parameter で調整できるもの:
//    入力側  : アドレス幅 / データ幅 / ID / 最大バースト長 / AxCACHE 等
//    出力側  : アドレス幅 / データ幅 / ID / 最大バースト長 / AxCACHE 等 (入力側と独立)
//    画素    : 1 画素のビット数 (PIXEL_BITS)、メモリ上の 1 画素のビット数 (PIX_MEM_BITS)
//    SRAM    : ライン数 (NUM_LINES)、1 ラインの最大画素数 (MAX_LINE_PIXELS)、
//              1 ワードの画素数 (PIX_PER_WORD = 1 サイクルに処理する画素数)
//
//  メモリ上の画像フォーマット:
//    - ライン y の先頭アドレス = base + y * stride (バイト)
//    - 1 ラインは画素 0 から順に PIX_MEM_BITS ビットずつ、下位ビット / 下位アドレスから
//      隙間なく並ぶ (little-endian)。1 ライン = ceil(width * PIX_MEM_BITS / 8) バイト
//    - PIX_MEM_BITS > PIXEL_BITS のとき、画素値は PIX_ALIGN_MSB=0 なら下位詰め、
//      1 なら上位詰め。余りのビットは入力では無視し、出力では 0 を書く
//    例) PIXEL_BITS=10, PIX_MEM_BITS=16 : 16bit コンテナに 10bit 画素 (一般的な形式)
//        PIXEL_BITS=10, PIX_MEM_BITS=10 : 隙間なく詰める (メモリ効率優先)
//        PIXEL_BITS=24, PIX_MEM_BITS=24 : RGB888 (3 バイト/画素)
//
//  動作:
//    - コマンドは cmd_valid / cmd_ready で受ける (アイドル時のみ cmd_ready=1)
//    - 入力側は scratchpad に空きラインがあるときだけ、次のラインの AR を出す
//    - 出力側は 1 ライン分が scratchpad に揃ってから読み出し、AXI へ書く
//    - NUM_LINES >= 2 なら、あるラインの書き出しと次のラインの取り込みが並行する
//    - 出力の最終ビートは WSTRB で有効バイトだけを書く (ライン外のメモリは壊さない)
//    - 全ラインの B を受けたら done を 1 サイクル。done_err / err_flags も同じサイクル
//
//  制約:
//    - cmd_src_addr / cmd_src_stride は入力側バス幅 (IN_DATA_WIDTH/8 バイト) の倍数、
//      cmd_dst_addr / cmd_dst_stride は出力側バス幅の倍数であること
//      (違反は err_flags[2] で返し、転送しない)
//    - cmd_dst_stride は 1 ラインのバイト数以上であること (ライン同士が重ならない)
//    - 入力 AXI / 出力 AXI / SRAM は同一クロック (aclk)
//    - アウトスタンディングは Read / Write 各 1
//
//  参考: AMBA AXI Protocol Specification (Arm IHI 0022)
//        https://developer.arm.com/documentation/ihi0022/latest/
//=============================================================================
`timescale 1ns / 1ps

module axi4_master_linebuf #(
  //---------------------------------------------------------------------------
  // 入力側 AXI (Read)
  //---------------------------------------------------------------------------
  parameter int unsigned IN_ADDR_WIDTH   = 32
 ,parameter int unsigned IN_DATA_WIDTH   = 64
 ,parameter int unsigned IN_ID_WIDTH     = 4
 ,parameter int unsigned IN_AXI_ID       = 0
 ,parameter int unsigned IN_MAX_BURST    = 16
 ,parameter int unsigned IN_FIFO_DEPTH   = 32
 ,parameter logic [3:0]  IN_ARCACHE      = 4'b0011
 ,parameter logic [2:0]  IN_ARPROT       = 3'b000
 ,parameter logic [3:0]  IN_ARQOS        = 4'd0
 ,parameter logic [3:0]  IN_ARREGION     = 4'd0
  //---------------------------------------------------------------------------
  // 出力側 AXI (Write)
  //---------------------------------------------------------------------------
 ,parameter int unsigned OUT_ADDR_WIDTH  = 32
 ,parameter int unsigned OUT_DATA_WIDTH  = 64
 ,parameter int unsigned OUT_ID_WIDTH    = 4
 ,parameter int unsigned OUT_AXI_ID      = 0
 ,parameter int unsigned OUT_MAX_BURST   = 16
 ,parameter int unsigned OUT_FIFO_DEPTH  = 32
 ,parameter logic [3:0]  OUT_AWCACHE     = 4'b0011
 ,parameter logic [2:0]  OUT_AWPROT      = 3'b000
 ,parameter logic [3:0]  OUT_AWQOS       = 4'd0
 ,parameter logic [3:0]  OUT_AWREGION    = 4'd0
  //---------------------------------------------------------------------------
  // 画素 / scratchpad SRAM
  //---------------------------------------------------------------------------
 ,parameter int unsigned PIXEL_BITS      = 8
 ,parameter int unsigned PIX_MEM_BITS    = ((PIXEL_BITS + 7) / 8) * 8
 ,parameter bit          PIX_ALIGN_MSB   = 1'b0
 ,parameter int unsigned PIX_PER_WORD    = 1
 ,parameter int unsigned MAX_LINE_PIXELS = 1920
 ,parameter int unsigned NUM_LINES       = 4
  //---------------------------------------------------------------------------
  // コマンド
  //---------------------------------------------------------------------------
 ,parameter int unsigned HEIGHT_WIDTH    = 16
 ,parameter int unsigned STRIDE_WIDTH    = 24
) (
  //---------------------------------------------------------------------------
  // Global
  //---------------------------------------------------------------------------
  input  logic                                   aclk
 ,input  logic                                   aresetn
  //---------------------------------------------------------------------------
  // コマンド
  //   cmd_width  : 1 ラインの画素数 (1..MAX_LINE_PIXELS)
  //   cmd_height : ライン数
  //   stride     : ライン先頭アドレスの間隔 [バイト]
  //---------------------------------------------------------------------------
 ,input  logic                                   cmd_valid
 ,output logic                                   cmd_ready
 ,input  logic [IN_ADDR_WIDTH-1:0]               cmd_src_addr
 ,input  logic [OUT_ADDR_WIDTH-1:0]              cmd_dst_addr
 ,input  logic [STRIDE_WIDTH-1:0]                cmd_src_stride
 ,input  logic [STRIDE_WIDTH-1:0]                cmd_dst_stride
 ,input  logic [$clog2(MAX_LINE_PIXELS+1)-1:0]   cmd_width
 ,input  logic [HEIGHT_WIDTH-1:0]                cmd_height
  //---------------------------------------------------------------------------
  // ステータス
  //   done          : 完了で 1 サイクル。done_err / err_flags は同じサイクルで見る
  //   err_flags[0]  : Read 側のエラー (RRESP != OKAY / RID 不一致 / RLAST 位置ずれ)
  //   err_flags[1]  : Write 側のエラー (BRESP != OKAY / BID 不一致)
  //   err_flags[2]  : コマンドの誤り (幅が MAX_LINE_PIXELS 超 / アドレス・stride の非アライン)
  //   line_in_done  : 1 ラインを scratchpad に格納し終えたサイクルに 1
  //   line_out_done : 1 ラインを出力側へ書き終えた (最後の B を受けた) 次のサイクルに 1
  //   sp_level      : scratchpad に格納済みで、まだ読み出し終わっていないライン数
  //---------------------------------------------------------------------------
 ,output logic                                   busy
 ,output logic                                   done
 ,output logic                                   done_err
 ,output logic [2:0]                             err_flags
 ,output logic                                   line_in_done
 ,output logic                                   line_out_done
 ,output logic [$clog2(NUM_LINES+1)-1:0]         sp_level
  //---------------------------------------------------------------------------
  // 入力側 AXI4 master : Read address channel
  //---------------------------------------------------------------------------
 ,output logic [IN_ID_WIDTH-1:0]                 m_axi_in_arid
 ,output logic [IN_ADDR_WIDTH-1:0]               m_axi_in_araddr
 ,output logic [7:0]                             m_axi_in_arlen
 ,output logic [2:0]                             m_axi_in_arsize
 ,output logic [1:0]                             m_axi_in_arburst
 ,output logic                                   m_axi_in_arlock
 ,output logic [3:0]                             m_axi_in_arcache
 ,output logic [2:0]                             m_axi_in_arprot
 ,output logic [3:0]                             m_axi_in_arqos
 ,output logic [3:0]                             m_axi_in_arregion
 ,output logic                                   m_axi_in_arvalid
 ,input  logic                                   m_axi_in_arready
  //---------------------------------------------------------------------------
  // 入力側 AXI4 master : Read data channel
  //---------------------------------------------------------------------------
 ,input  logic [IN_ID_WIDTH-1:0]                 m_axi_in_rid
 ,input  logic [IN_DATA_WIDTH-1:0]               m_axi_in_rdata
 ,input  logic [1:0]                             m_axi_in_rresp
 ,input  logic                                   m_axi_in_rlast
 ,input  logic                                   m_axi_in_rvalid
 ,output logic                                   m_axi_in_rready
  //---------------------------------------------------------------------------
  // 出力側 AXI4 master : Write address channel
  //---------------------------------------------------------------------------
 ,output logic [OUT_ID_WIDTH-1:0]                m_axi_out_awid
 ,output logic [OUT_ADDR_WIDTH-1:0]              m_axi_out_awaddr
 ,output logic [7:0]                             m_axi_out_awlen
 ,output logic [2:0]                             m_axi_out_awsize
 ,output logic [1:0]                             m_axi_out_awburst
 ,output logic                                   m_axi_out_awlock
 ,output logic [3:0]                             m_axi_out_awcache
 ,output logic [2:0]                             m_axi_out_awprot
 ,output logic [3:0]                             m_axi_out_awqos
 ,output logic [3:0]                             m_axi_out_awregion
 ,output logic                                   m_axi_out_awvalid
 ,input  logic                                   m_axi_out_awready
  //---------------------------------------------------------------------------
  // 出力側 AXI4 master : Write data channel
  //---------------------------------------------------------------------------
 ,output logic [OUT_DATA_WIDTH-1:0]              m_axi_out_wdata
 ,output logic [(OUT_DATA_WIDTH/8)-1:0]          m_axi_out_wstrb
 ,output logic                                   m_axi_out_wlast
 ,output logic                                   m_axi_out_wvalid
 ,input  logic                                   m_axi_out_wready
  //---------------------------------------------------------------------------
  // 出力側 AXI4 master : Write response channel
  //---------------------------------------------------------------------------
 ,input  logic [OUT_ID_WIDTH-1:0]                m_axi_out_bid
 ,input  logic [1:0]                             m_axi_out_bresp
 ,input  logic                                   m_axi_out_bvalid
 ,output logic                                   m_axi_out_bready
);

  //---------------------------------------------------------------------------
  // Local parameters
  //---------------------------------------------------------------------------
  localparam int unsigned IN_BYTES       = IN_DATA_WIDTH / 8;
  localparam int unsigned OUT_BYTES      = OUT_DATA_WIDTH / 8;
  localparam int unsigned IN_LSB         = $clog2(IN_BYTES);
  localparam int unsigned OUT_LSB        = $clog2(OUT_BYTES);

  localparam int unsigned WORD_BITS      = PIX_PER_WORD * PIXEL_BITS;     // SRAM 1 ワード
  localparam int unsigned MEMW_BITS      = PIX_PER_WORD * PIX_MEM_BITS;   // メモリ上での 1 ワード分
  localparam int unsigned PIX_OFS        = PIX_ALIGN_MSB ? (PIX_MEM_BITS - PIXEL_BITS) : 0;
  localparam int unsigned LINE_WORDS     = (MAX_LINE_PIXELS + PIX_PER_WORD - 1) / PIX_PER_WORD;
  localparam int unsigned WADDR_W        = (LINE_WORDS<2) ? 1 : $clog2(LINE_WORDS);
  localparam int unsigned SLOT_W         = (NUM_LINES<2) ? 1 : $clog2(NUM_LINES);
  localparam int unsigned LVL_W          = $clog2(NUM_LINES+1);
  localparam int unsigned XW             = $clog2(MAX_LINE_PIXELS+1);
  localparam int unsigned PIXC_W         = $clog2(MAX_LINE_PIXELS+PIX_PER_WORD+1);

  localparam int unsigned MAX_LINE_BITS  = MAX_LINE_PIXELS * PIX_MEM_BITS;
  localparam int unsigned MAX_LINE_BYTES = (MAX_LINE_BITS + 7) / 8;
  localparam int unsigned LBIT_W         = $clog2(MAX_LINE_BITS+1);
  localparam int unsigned MAX_IN_BEATS   = (MAX_LINE_BYTES + IN_BYTES - 1) / IN_BYTES;
  localparam int unsigned MAX_OUT_BEATS  = (MAX_LINE_BYTES + OUT_BYTES - 1) / OUT_BYTES;
  localparam int unsigned IN_LEN_W       = $clog2(MAX_IN_BEATS+1);
  localparam int unsigned OUT_LEN_W      = $clog2(MAX_OUT_BEATS+1);
  localparam int unsigned IN_CNT_W       = $clog2(IN_FIFO_DEPTH+1);
  localparam int unsigned OUT_CNT_W      = $clog2(OUT_FIFO_DEPTH+1);

  // scratchpad の読み出しデータを受ける小さな FIFO (SRAM の読み出しレイテンシ吸収用)
  localparam int unsigned RDF_DEPTH      = 4;
  localparam int unsigned RDF_CNT_W      = $clog2(RDF_DEPTH+1);

  typedef enum logic [2:0] {
    F_IDLE  = 3'd0
   ,F_CALC1 = 3'd1
   ,F_CALC2 = 3'd2
   ,F_RUN   = 3'd3
   ,F_DONE  = 3'd4
  } fstate_e;

  typedef enum logic [0:0] {
    R_IDLE = 1'b0
   ,R_READ = 1'b1
  } rstate_e;

  //---------------------------------------------------------------------------
  // フレーム制御のレジスタ
  //---------------------------------------------------------------------------
  fstate_e                   fstate;
  logic                      run;
  logic [XW-1:0]             width_q;         // 1 ラインの画素数
  logic [STRIDE_WIDTH-1:0]   src_stride_q;
  logic [STRIDE_WIDTH-1:0]   dst_stride_q;
  logic [LBIT_W-1:0]         line_bits_q;     // 1 ラインのビット数
  logic [IN_LEN_W-1:0]       in_beats_q;      // 入力側 1 ラインのビート数
  logic [OUT_LEN_W-1:0]      out_beats_q;     // 出力側 1 ラインのビート数
  logic [OUT_BYTES-1:0]      out_last_strb_q; // 出力側 最終ビートの WSTRB
  logic [IN_ADDR_WIDTH-1:0]  in_line_addr;    // 次に読むラインの先頭アドレス
  logic [OUT_ADDR_WIDTH-1:0] out_line_addr;   // 次に書くラインの先頭アドレス
  logic [HEIGHT_WIDTH-1:0]   in_lines_left;   // Read コマンド未発行のライン数
  logic [HEIGHT_WIDTH-1:0]   out_lines_left;  // Write コマンド未発行のライン数
  logic [HEIGHT_WIDTH-1:0]   out_done_left;   // Write 未完了のライン数
  logic                      err_rd;
  logic                      err_wr;
  logic                      err_cfg;

  assign run = (fstate==F_RUN);

  //---------------------------------------------------------------------------
  // コマンドの検査
  //---------------------------------------------------------------------------
  logic cmd_empty;
  logic cmd_bad;
  logic cmd_width_over;
  logic cmd_src_addr_bad;      // 入力側アドレスがバス幅の倍数でない
  logic cmd_dst_addr_bad;      // 出力側アドレスがバス幅の倍数でない
  logic cmd_src_stride_bad;    // 入力側 stride がバス幅の倍数でない
  logic cmd_dst_stride_bad;    // 出力側 stride がバス幅の倍数でない

  // cmd_width のビット幅で MAX_LINE_PIXELS を超える値を表せるときだけ比較する
  generate
    if( ((1<<XW)-1)>MAX_LINE_PIXELS ) begin : g_width_chk
      assign cmd_width_over = (32'(cmd_width)>32'(MAX_LINE_PIXELS));
    end else begin : g_width_nochk
      assign cmd_width_over = 1'b0;
    end
  endgenerate

  assign cmd_src_addr_bad   = ((cmd_src_addr&IN_ADDR_WIDTH'(IN_BYTES-1))!={IN_ADDR_WIDTH{1'b0}});
  assign cmd_dst_addr_bad   = ((cmd_dst_addr&OUT_ADDR_WIDTH'(OUT_BYTES-1))!={OUT_ADDR_WIDTH{1'b0}});
  assign cmd_src_stride_bad = ((cmd_src_stride&STRIDE_WIDTH'(IN_BYTES-1))!={STRIDE_WIDTH{1'b0}});
  assign cmd_dst_stride_bad = ((cmd_dst_stride&STRIDE_WIDTH'(OUT_BYTES-1))!={STRIDE_WIDTH{1'b0}});

  assign cmd_empty = (cmd_width=={XW{1'b0}})||(cmd_height=={HEIGHT_WIDTH{1'b0}});
  assign cmd_bad   = cmd_width_over||cmd_src_addr_bad||cmd_dst_addr_bad||cmd_src_stride_bad||cmd_dst_stride_bad;

  //---------------------------------------------------------------------------
  // 1 ラインあたりのバイト数 / ビート数 (F_CALC2 で確定)
  //---------------------------------------------------------------------------
  logic [31:0] line_bytes32;
  logic [31:0] in_beats32;
  logic [31:0] out_beats32;
  logic [31:0] last_bytes32;    // 出力側 最終ビートの有効バイト数 (1..OUT_BYTES)

  assign line_bytes32 = (32'(line_bits_q) + 32'd7) >> 3;
  assign in_beats32   = (line_bytes32 + 32'(IN_BYTES-1)) >> IN_LSB;
  assign out_beats32  = (line_bytes32 + 32'(OUT_BYTES-1)) >> OUT_LSB;
  assign last_bytes32 = line_bytes32 - ((out_beats32 - 32'd1) << OUT_LSB);

  //---------------------------------------------------------------------------
  // エンジンとの接続信号
  //---------------------------------------------------------------------------
  logic                      rd_cmd_valid;
  logic                      rd_cmd_ready;
  logic                      rd_cmd_fire;
  logic                      rd_done;
  logic                      rd_done_err;
  logic                      rd_busy;
  logic [IN_DATA_WIDTH-1:0]  rd_m_data;
  logic                      rd_m_last;
  logic                      rd_m_valid;
  logic                      rd_m_ready;
  logic [IN_CNT_W-1:0]       rd_m_space;

  logic                      wr_cmd_valid;
  logic                      wr_cmd_ready;
  logic                      wr_cmd_fire;
  logic                      wr_done;
  logic                      wr_done_err;
  logic                      wr_busy;
  logic                      wr_s_ready;

  // 入力側 FIFO ({last, data})
  logic [IN_DATA_WIDTH:0]    if_rd_data;
  logic                      if_rd_valid;
  logic                      if_rd_ready;
  logic [IN_CNT_W-1:0]       if_level;

  // 出力側 FIFO ({strb, data})
  logic [OUT_DATA_WIDTH+OUT_BYTES-1:0] of_wr_data;
  logic                      of_wr_valid;
  logic                      of_wr_ready;
  logic [OUT_DATA_WIDTH+OUT_BYTES-1:0] of_rd_data;
  logic                      of_rd_valid;
  logic [OUT_CNT_W-1:0]      of_level;

  //---------------------------------------------------------------------------
  // scratchpad の管理
  //   slots_free   : まだ予約されていないライン数 (Read コマンド発行時に 1 つ予約)
  //   lines_ready  : 格納が終わり、読み出し開始待ちのライン数
  //   lines_stored : 格納が終わり、まだ読み出し終わっていないライン数 (sp_level に出す)
  //---------------------------------------------------------------------------
  logic [LVL_W-1:0]          slots_free;
  logic [LVL_W-1:0]          lines_ready;
  logic [LVL_W-1:0]          lines_stored;
  logic [SLOT_W-1:0]         wr_slot;
  logic [SLOT_W-1:0]         rd_slot;

  //---------------------------------------------------------------------------
  // 入力側 : ビート → 画素 → scratchpad
  //---------------------------------------------------------------------------
  logic [MEMW_BITS-1:0]      gbi_out_data;
  logic                      gbi_out_valid;
  logic                      gbi_out_last;
  logic                      gbi_clear;
  logic [WORD_BITS-1:0]      sp_wr_data;
  logic [WADDR_W-1:0]        wr_word;         // ライン内のワード位置
  logic [PIXC_W-1:0]         wr_pix;          // ライン内で格納済みの画素数
  logic [31:0]               wr_rem32;        // このワードを含む残り画素数
  logic                      in_word_fire;
  logic                      in_last_word;
  logic                      line_in_fire;

  assign wr_rem32     = 32'(width_q) - 32'(wr_pix);
  assign in_word_fire = gbi_out_valid;
  assign in_last_word = (wr_rem32<=32'(PIX_PER_WORD));
  assign line_in_fire = in_word_fire&&in_last_word;
  assign gbi_clear    = line_in_fire;

  //---------------------------------------------------------------------------
  // 出力側 : scratchpad → 画素 → ビート
  //---------------------------------------------------------------------------
  rstate_e                   rstate;
  logic [WADDR_W-1:0]        rd_word;
  logic [PIXC_W-1:0]         rd_pix;
  logic [31:0]               rd_rem32;
  logic                      rd_take;         // 読み出すラインを 1 本確保
  logic                      rd_can;
  logic                      rd_issue;        // SRAM 読み出しを 1 ワード発行
  logic                      rd_last_word;
  logic                      rd_last_q;       // 発行した読み出しがライン最終ワード
  logic                      sp_rd_valid;
  logic [WORD_BITS-1:0]      sp_rd_data;

  logic [WORD_BITS:0]        rdf_rd_data;     // {last, word}
  logic                      rdf_rd_valid;
  logic                      rdf_rd_ready;
  logic                      rdf_wr_ready;
  logic [RDF_CNT_W-1:0]      rdf_level;

  logic [MEMW_BITS-1:0]      gbo_in_data;
  logic [OUT_DATA_WIDTH-1:0] gbo_out_data;
  logic                      gbo_out_valid;
  logic                      gbo_out_last;
  logic                      gbo_clear;
  logic [OUT_LEN_W-1:0]      pk_beat;         // ライン内で FIFO に積んだビート数
  logic                      pk_fire;
  logic                      pk_last;

  assign rd_rem32     = 32'(width_q) - 32'(rd_pix);
  assign rd_take      = run&&(rstate==R_IDLE)&&(lines_ready!={LVL_W{1'b0}});
  assign rd_can       = ((32'(rdf_level) + 32'(sp_rd_valid))<32'(RDF_DEPTH));
  assign rd_issue     = (rstate==R_READ)&&rd_can;
  assign rd_last_word = (rd_rem32<=32'(PIX_PER_WORD));

  assign pk_fire      = gbo_out_valid&&of_wr_ready;
  assign pk_last      = (32'(pk_beat)==(32'(out_beats_q) - 32'd1));
  assign gbo_clear    = pk_fire&&pk_last;
  assign of_wr_valid  = gbo_out_valid;
  assign of_wr_data   = {(pk_last ? out_last_strb_q : {OUT_BYTES{1'b1}}), gbo_out_data};

  //---------------------------------------------------------------------------
  // 画素の取り出し / 詰め直し (1 ワード = PIX_PER_WORD 画素)
  //---------------------------------------------------------------------------
  genvar gp;
  generate
    for( gp=0; gp<PIX_PER_WORD; gp=gp+1 ) begin : g_pix
      logic [PIXEL_BITS-1:0]   pix_in;
      logic [PIX_MEM_BITS-1:0] pix_out;

      // 入力: コンテナから画素を取り出す。ライン幅を超えた位置は 0 にする
      assign pix_in = gbi_out_data[(gp*PIX_MEM_BITS)+PIX_OFS +: PIXEL_BITS];
      assign sp_wr_data[gp*PIXEL_BITS +: PIXEL_BITS] = (32'(gp)<wr_rem32) ? pix_in : {PIXEL_BITS{1'b0}};

      // 出力: 画素をコンテナに入れ直す (余りビットは 0)
      assign pix_out = PIX_MEM_BITS'(rdf_rd_data[gp*PIXEL_BITS +: PIXEL_BITS]) << PIX_OFS;
      assign gbo_in_data[gp*PIX_MEM_BITS +: PIX_MEM_BITS] = pix_out;
    end
  endgenerate

  //---------------------------------------------------------------------------
  // コマンド発行
  //   Read  : 残りラインがあり、scratchpad に空きラインがあるとき
  //   Write : 残りラインがあるとき (エンジンはデータが揃うまで AW を出さない)
  //---------------------------------------------------------------------------
  assign rd_cmd_valid = run&&(in_lines_left!={HEIGHT_WIDTH{1'b0}})&&(slots_free!={LVL_W{1'b0}});
  assign rd_cmd_fire  = rd_cmd_valid&&rd_cmd_ready;
  assign wr_cmd_valid = run&&(out_lines_left!={HEIGHT_WIDTH{1'b0}});
  assign wr_cmd_fire  = wr_cmd_valid&&wr_cmd_ready;

  //---------------------------------------------------------------------------
  // ステータス出力
  //---------------------------------------------------------------------------
  assign cmd_ready     = (fstate==F_IDLE);
  assign busy          = (fstate!=F_IDLE);
  assign done          = (fstate==F_DONE);
  assign err_flags     = {err_cfg, err_wr, err_rd};
  assign done_err      = err_cfg||err_wr||err_rd;
  assign line_in_done  = line_in_fire;
  assign line_out_done = run&&wr_done;
  assign sp_level      = lines_stored;

  //---------------------------------------------------------------------------
  // フレーム制御 FSM
  //---------------------------------------------------------------------------
  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      fstate          <= F_IDLE;
      width_q         <= {XW{1'b0}};
      src_stride_q    <= {STRIDE_WIDTH{1'b0}};
      dst_stride_q    <= {STRIDE_WIDTH{1'b0}};
      line_bits_q     <= {LBIT_W{1'b0}};
      in_beats_q      <= {IN_LEN_W{1'b0}};
      out_beats_q     <= {OUT_LEN_W{1'b0}};
      out_last_strb_q <= {OUT_BYTES{1'b0}};
      in_line_addr    <= {IN_ADDR_WIDTH{1'b0}};
      out_line_addr   <= {OUT_ADDR_WIDTH{1'b0}};
      in_lines_left   <= {HEIGHT_WIDTH{1'b0}};
      out_lines_left  <= {HEIGHT_WIDTH{1'b0}};
      out_done_left   <= {HEIGHT_WIDTH{1'b0}};
      err_rd          <= 1'b0;
      err_wr          <= 1'b0;
      err_cfg         <= 1'b0;
    end else begin
      case( fstate )
        F_IDLE : begin
          if( cmd_valid ) begin
            width_q        <= cmd_width;
            src_stride_q   <= cmd_src_stride;
            dst_stride_q   <= cmd_dst_stride;
            in_line_addr   <= cmd_src_addr;
            out_line_addr  <= cmd_dst_addr;
            in_lines_left  <= cmd_height;
            out_lines_left <= cmd_height;
            out_done_left  <= cmd_height;
            err_rd         <= 1'b0;
            err_wr         <= 1'b0;
            if( cmd_empty ) begin
              // 0 画素 / 0 ラインは何もせず完了
              err_cfg <= 1'b0;
              fstate  <= F_DONE;
            end else if( cmd_bad ) begin
              err_cfg <= 1'b1;
              fstate  <= F_DONE;
            end else begin
              err_cfg <= 1'b0;
              fstate  <= F_CALC1;
            end
          end
        end
        F_CALC1 : begin
          line_bits_q <= LBIT_W'(32'(width_q) * 32'(PIX_MEM_BITS));
          fstate      <= F_CALC2;
        end
        F_CALC2 : begin
          in_beats_q  <= IN_LEN_W'(in_beats32);
          out_beats_q <= OUT_LEN_W'(out_beats32);
          for( int unsigned i=0; i<OUT_BYTES; i++ ) begin
            out_last_strb_q[i] <= (32'(i)<last_bytes32);
          end
          fstate <= F_RUN;
        end
        F_RUN : begin
          if( rd_cmd_fire ) begin
            in_lines_left <= in_lines_left - HEIGHT_WIDTH'(1);
            in_line_addr  <= in_line_addr + IN_ADDR_WIDTH'(src_stride_q);
          end
          if( wr_cmd_fire ) begin
            out_lines_left <= out_lines_left - HEIGHT_WIDTH'(1);
            out_line_addr  <= out_line_addr + OUT_ADDR_WIDTH'(dst_stride_q);
          end
          if( rd_done&&rd_done_err ) begin
            err_rd <= 1'b1;
          end
          if( wr_done ) begin
            if( wr_done_err ) begin
              err_wr <= 1'b1;
            end
            out_done_left <= out_done_left - HEIGHT_WIDTH'(1);
            if( out_done_left==HEIGHT_WIDTH'(1) ) begin
              fstate <= F_DONE;
            end
          end
        end
        F_DONE : begin
          fstate <= F_IDLE;
        end
        default : begin
          fstate <= F_IDLE;
        end
      endcase
    end
  end

  //---------------------------------------------------------------------------
  // scratchpad のライン管理
  //---------------------------------------------------------------------------
  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      slots_free   <= LVL_W'(NUM_LINES);
      lines_ready  <= {LVL_W{1'b0}};
      lines_stored <= {LVL_W{1'b0}};
      wr_slot      <= {SLOT_W{1'b0}};
      rd_slot      <= {SLOT_W{1'b0}};
    end else begin
      // 空きライン数: Read コマンド発行で予約 (-1)、読み出し完了で解放 (+1)
      case( {rd_cmd_fire, (rd_issue&&rd_last_word)} )
        2'b10 : begin
          slots_free <= slots_free - LVL_W'(1);
        end
        2'b01 : begin
          slots_free <= slots_free + LVL_W'(1);
        end
        default : begin
          slots_free <= slots_free;
        end
      endcase
      // 読み出し待ちライン数: 格納完了で +1、読み出し開始で -1
      case( {line_in_fire, rd_take} )
        2'b10 : begin
          lines_ready <= lines_ready + LVL_W'(1);
        end
        2'b01 : begin
          lines_ready <= lines_ready - LVL_W'(1);
        end
        default : begin
          lines_ready <= lines_ready;
        end
      endcase
      // 格納済みライン数 (ステータス用): 格納完了で +1、読み出し完了で -1
      case( {line_in_fire, (rd_issue&&rd_last_word)} )
        2'b10 : begin
          lines_stored <= lines_stored + LVL_W'(1);
        end
        2'b01 : begin
          lines_stored <= lines_stored - LVL_W'(1);
        end
        default : begin
          lines_stored <= lines_stored;
        end
      endcase
      // 書き込みライン位置 (リング)
      if( line_in_fire ) begin
        if( wr_slot==SLOT_W'(NUM_LINES-1) ) begin
          wr_slot <= {SLOT_W{1'b0}};
        end else begin
          wr_slot <= wr_slot + SLOT_W'(1);
        end
      end
      // 読み出しライン位置 (リング)
      if( rd_issue&&rd_last_word ) begin
        if( rd_slot==SLOT_W'(NUM_LINES-1) ) begin
          rd_slot <= {SLOT_W{1'b0}};
        end else begin
          rd_slot <= rd_slot + SLOT_W'(1);
        end
      end
    end
  end

  //---------------------------------------------------------------------------
  // 入力側 : scratchpad への書き込み位置
  //---------------------------------------------------------------------------
  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      wr_word <= {WADDR_W{1'b0}};
      wr_pix  <= {PIXC_W{1'b0}};
    end else begin
      if( in_word_fire ) begin
        if( in_last_word ) begin
          wr_word <= {WADDR_W{1'b0}};
          wr_pix  <= {PIXC_W{1'b0}};
        end else begin
          wr_word <= wr_word + WADDR_W'(1);
          wr_pix  <= wr_pix + PIXC_W'(PIX_PER_WORD);
        end
      end
    end
  end

  //---------------------------------------------------------------------------
  // 出力側 : scratchpad からの読み出し
  //   SRAM の読み出しデータは 1 サイクル後に出るので、小さな FIFO (rdf) で受ける。
  //   「FIFO の格納数 + 読み出し中の 1 ワード」が深さ未満のときだけ次を読む
  //---------------------------------------------------------------------------
  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      rstate    <= R_IDLE;
      rd_word   <= {WADDR_W{1'b0}};
      rd_pix    <= {PIXC_W{1'b0}};
      rd_last_q <= 1'b0;
    end else begin
      case( rstate )
        R_IDLE : begin
          if( rd_take ) begin
            rd_word <= {WADDR_W{1'b0}};
            rd_pix  <= {PIXC_W{1'b0}};
            rstate  <= R_READ;
          end
        end
        R_READ : begin
          if( rd_issue ) begin
            rd_last_q <= rd_last_word;
            if( rd_last_word ) begin
              rstate <= R_IDLE;
            end else begin
              rd_word <= rd_word + WADDR_W'(1);
              rd_pix  <= rd_pix + PIXC_W'(PIX_PER_WORD);
            end
          end
        end
        default : begin
          rstate <= R_IDLE;
        end
      endcase
    end
  end

  //---------------------------------------------------------------------------
  // 出力側 : ライン内のビート数
  //---------------------------------------------------------------------------
  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      pk_beat <= {OUT_LEN_W{1'b0}};
    end else begin
      if( pk_fire ) begin
        if( pk_last ) begin
          pk_beat <= {OUT_LEN_W{1'b0}};
        end else begin
          pk_beat <= pk_beat + OUT_LEN_W'(1);
        end
      end
    end
  end

  //---------------------------------------------------------------------------
  // 入力側 Read エンジン
  //---------------------------------------------------------------------------
  assign rd_m_space = IN_CNT_W'(IN_FIFO_DEPTH) - if_level;

  axi4_lb_rd_engine #(
    .ADDR_WIDTH(IN_ADDR_WIDTH)
   ,.DATA_WIDTH(IN_DATA_WIDTH)
   ,.ID_WIDTH(IN_ID_WIDTH)
   ,.AXI_ID(IN_AXI_ID)
   ,.LEN_WIDTH(IN_LEN_W)
   ,.CNT_WIDTH(IN_CNT_W)
   ,.MAX_BURST(IN_MAX_BURST)
   ,.AXCACHE(IN_ARCACHE)
   ,.AXPROT(IN_ARPROT)
   ,.AXQOS(IN_ARQOS)
   ,.AXREGION(IN_ARREGION)
  ) u_rd_engine (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.cmd_valid(rd_cmd_valid)
   ,.cmd_ready(rd_cmd_ready)
   ,.cmd_addr(in_line_addr)
   ,.cmd_len(in_beats_q)
   ,.busy(rd_busy)
   ,.done(rd_done)
   ,.done_err(rd_done_err)
   ,.m_data(rd_m_data)
   ,.m_last(rd_m_last)
   ,.m_valid(rd_m_valid)
   ,.m_ready(rd_m_ready)
   ,.m_space(rd_m_space)
   ,.m_axi_arid(m_axi_in_arid)
   ,.m_axi_araddr(m_axi_in_araddr)
   ,.m_axi_arlen(m_axi_in_arlen)
   ,.m_axi_arsize(m_axi_in_arsize)
   ,.m_axi_arburst(m_axi_in_arburst)
   ,.m_axi_arlock(m_axi_in_arlock)
   ,.m_axi_arcache(m_axi_in_arcache)
   ,.m_axi_arprot(m_axi_in_arprot)
   ,.m_axi_arqos(m_axi_in_arqos)
   ,.m_axi_arregion(m_axi_in_arregion)
   ,.m_axi_arvalid(m_axi_in_arvalid)
   ,.m_axi_arready(m_axi_in_arready)
   ,.m_axi_rid(m_axi_in_rid)
   ,.m_axi_rdata(m_axi_in_rdata)
   ,.m_axi_rresp(m_axi_in_rresp)
   ,.m_axi_rlast(m_axi_in_rlast)
   ,.m_axi_rvalid(m_axi_in_rvalid)
   ,.m_axi_rready(m_axi_in_rready)
  );

  //---------------------------------------------------------------------------
  // 入力側 FIFO ({ライン最終ビート, データ})
  //---------------------------------------------------------------------------
  axi4_lb_fifo #(
    .WIDTH(IN_DATA_WIDTH+1)
   ,.DEPTH(IN_FIFO_DEPTH)
  ) u_in_fifo (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.wr_data({rd_m_last, rd_m_data})
   ,.wr_valid(rd_m_valid)
   ,.wr_ready(rd_m_ready)
   ,.rd_data(if_rd_data)
   ,.rd_valid(if_rd_valid)
   ,.rd_ready(if_rd_ready)
   ,.level(if_level)
  );

  //---------------------------------------------------------------------------
  // 入力側 gearbox : IN_DATA_WIDTH ビット → 1 ワード分 (PIX_PER_WORD 画素)
  //   ライン最終ワードを取り出したら clear して、ビートの余りビットを捨てる
  //---------------------------------------------------------------------------
  axi4_lb_gearbox #(
    .IN_BITS(IN_DATA_WIDTH)
   ,.OUT_BITS(MEMW_BITS)
  ) u_gb_in (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.clear(gbi_clear)
   ,.in_data(if_rd_data[IN_DATA_WIDTH-1:0])
   ,.in_last(if_rd_data[IN_DATA_WIDTH])
   ,.in_valid(if_rd_valid)
   ,.in_ready(if_rd_ready)
   ,.out_data(gbi_out_data)
   ,.out_last(gbi_out_last)
   ,.out_valid(gbi_out_valid)
   ,.out_ready(1'b1)
  );

  //---------------------------------------------------------------------------
  // scratchpad SRAM
  //---------------------------------------------------------------------------
  axi4_lb_scratchpad #(
    .NUM_LINES(NUM_LINES)
   ,.LINE_WORDS(LINE_WORDS)
   ,.WORD_BITS(WORD_BITS)
   ,.SLOT_W(SLOT_W)
   ,.ADDR_W(WADDR_W)
  ) u_scratchpad (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.wr_en(in_word_fire)
   ,.wr_slot(wr_slot)
   ,.wr_addr(wr_word)
   ,.wr_data(sp_wr_data)
   ,.rd_en(rd_issue)
   ,.rd_slot(rd_slot)
   ,.rd_addr(rd_word)
   ,.rd_valid(sp_rd_valid)
   ,.rd_data(sp_rd_data)
  );

  //---------------------------------------------------------------------------
  // scratchpad 読み出しデータ FIFO ({ライン最終ワード, ワード})
  //---------------------------------------------------------------------------
  axi4_lb_fifo #(
    .WIDTH(WORD_BITS+1)
   ,.DEPTH(RDF_DEPTH)
  ) u_rd_fifo (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.wr_data({rd_last_q, sp_rd_data})
   ,.wr_valid(sp_rd_valid)
   ,.wr_ready(rdf_wr_ready)
   ,.rd_data(rdf_rd_data)
   ,.rd_valid(rdf_rd_valid)
   ,.rd_ready(rdf_rd_ready)
   ,.level(rdf_level)
  );

  //---------------------------------------------------------------------------
  // 出力側 gearbox : 1 ワード分 (PIX_PER_WORD 画素) → OUT_DATA_WIDTH ビット
  //   ライン最終ビートを FIFO に積んだら clear して、余りビットを捨てる
  //---------------------------------------------------------------------------
  axi4_lb_gearbox #(
    .IN_BITS(MEMW_BITS)
   ,.OUT_BITS(OUT_DATA_WIDTH)
  ) u_gb_out (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.clear(gbo_clear)
   ,.in_data(gbo_in_data)
   ,.in_last(rdf_rd_data[WORD_BITS])
   ,.in_valid(rdf_rd_valid)
   ,.in_ready(rdf_rd_ready)
   ,.out_data(gbo_out_data)
   ,.out_last(gbo_out_last)
   ,.out_valid(gbo_out_valid)
   ,.out_ready(of_wr_ready)
  );

  //---------------------------------------------------------------------------
  // 出力側 FIFO ({WSTRB, データ})
  //---------------------------------------------------------------------------
  axi4_lb_fifo #(
    .WIDTH(OUT_DATA_WIDTH+OUT_BYTES)
   ,.DEPTH(OUT_FIFO_DEPTH)
  ) u_out_fifo (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.wr_data(of_wr_data)
   ,.wr_valid(of_wr_valid)
   ,.wr_ready(of_wr_ready)
   ,.rd_data(of_rd_data)
   ,.rd_valid(of_rd_valid)
   ,.rd_ready(wr_s_ready)
   ,.level(of_level)
  );

  //---------------------------------------------------------------------------
  // 出力側 Write エンジン
  //---------------------------------------------------------------------------
  axi4_lb_wr_engine #(
    .ADDR_WIDTH(OUT_ADDR_WIDTH)
   ,.DATA_WIDTH(OUT_DATA_WIDTH)
   ,.ID_WIDTH(OUT_ID_WIDTH)
   ,.AXI_ID(OUT_AXI_ID)
   ,.LEN_WIDTH(OUT_LEN_W)
   ,.CNT_WIDTH(OUT_CNT_W)
   ,.MAX_BURST(OUT_MAX_BURST)
   ,.AXCACHE(OUT_AWCACHE)
   ,.AXPROT(OUT_AWPROT)
   ,.AXQOS(OUT_AWQOS)
   ,.AXREGION(OUT_AWREGION)
  ) u_wr_engine (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.cmd_valid(wr_cmd_valid)
   ,.cmd_ready(wr_cmd_ready)
   ,.cmd_addr(out_line_addr)
   ,.cmd_len(out_beats_q)
   ,.busy(wr_busy)
   ,.done(wr_done)
   ,.done_err(wr_done_err)
   ,.s_data(of_rd_data[OUT_DATA_WIDTH-1:0])
   ,.s_strb(of_rd_data[OUT_DATA_WIDTH +: OUT_BYTES])
   ,.s_valid(of_rd_valid)
   ,.s_ready(wr_s_ready)
   ,.s_count(of_level)
   ,.m_axi_awid(m_axi_out_awid)
   ,.m_axi_awaddr(m_axi_out_awaddr)
   ,.m_axi_awlen(m_axi_out_awlen)
   ,.m_axi_awsize(m_axi_out_awsize)
   ,.m_axi_awburst(m_axi_out_awburst)
   ,.m_axi_awlock(m_axi_out_awlock)
   ,.m_axi_awcache(m_axi_out_awcache)
   ,.m_axi_awprot(m_axi_out_awprot)
   ,.m_axi_awqos(m_axi_out_awqos)
   ,.m_axi_awregion(m_axi_out_awregion)
   ,.m_axi_awvalid(m_axi_out_awvalid)
   ,.m_axi_awready(m_axi_out_awready)
   ,.m_axi_wdata(m_axi_out_wdata)
   ,.m_axi_wstrb(m_axi_out_wstrb)
   ,.m_axi_wlast(m_axi_out_wlast)
   ,.m_axi_wvalid(m_axi_out_wvalid)
   ,.m_axi_wready(m_axi_out_wready)
   ,.m_axi_bid(m_axi_out_bid)
   ,.m_axi_bresp(m_axi_out_bresp)
   ,.m_axi_bvalid(m_axi_out_bvalid)
   ,.m_axi_bready(m_axi_out_bready)
  );

  //---------------------------------------------------------------------------
  // 未使用信号
  //   gbi_out_data はコンテナの余りビット (PIX_MEM_BITS > PIXEL_BITS のとき) を使わない
  //---------------------------------------------------------------------------
  logic unused_ok;
  assign unused_ok = &{1'b0, gbi_out_data, gbi_out_last, gbo_out_last, rdf_wr_ready, rd_busy, wr_busy, in_beats32[31:IN_LEN_W], out_beats32[31:OUT_LEN_W]};

  //---------------------------------------------------------------------------
  // パラメータチェック (エラボレーション時。IEEE 1800 20.11)
  //   対応していない合成ツールでは +define+AXI4_LB_NO_ELAB_CHECK で外す
  //---------------------------------------------------------------------------
`ifndef AXI4_LB_NO_ELAB_CHECK
  generate
    if( (IN_DATA_WIDTH<8)||(IN_DATA_WIDTH>1024)||((IN_DATA_WIDTH&(IN_DATA_WIDTH-1))!=0) ) begin : g_chk_in_data
      $error("axi4_master_linebuf : IN_DATA_WIDTH must be 8,16,32,...,1024 (IN_DATA_WIDTH=%0d)", IN_DATA_WIDTH);
    end
    if( (OUT_DATA_WIDTH<8)||(OUT_DATA_WIDTH>1024)||((OUT_DATA_WIDTH&(OUT_DATA_WIDTH-1))!=0) ) begin : g_chk_out_data
      $error("axi4_master_linebuf : OUT_DATA_WIDTH must be 8,16,32,...,1024 (OUT_DATA_WIDTH=%0d)", OUT_DATA_WIDTH);
    end
    if( PIXEL_BITS<1 ) begin : g_chk_pixel_bits
      $error("axi4_master_linebuf : PIXEL_BITS must be >= 1 (PIXEL_BITS=%0d)", PIXEL_BITS);
    end
    if( PIX_MEM_BITS<PIXEL_BITS ) begin : g_chk_pix_mem_bits
      $error("axi4_master_linebuf : PIX_MEM_BITS (%0d) must be >= PIXEL_BITS (%0d)", PIX_MEM_BITS, PIXEL_BITS);
    end
    if( PIX_PER_WORD<1 ) begin : g_chk_pix_per_word
      $error("axi4_master_linebuf : PIX_PER_WORD must be >= 1 (PIX_PER_WORD=%0d)", PIX_PER_WORD);
    end
    if( MAX_LINE_PIXELS<1 ) begin : g_chk_max_line_pixels
      $error("axi4_master_linebuf : MAX_LINE_PIXELS must be >= 1 (MAX_LINE_PIXELS=%0d)", MAX_LINE_PIXELS);
    end
    if( NUM_LINES<1 ) begin : g_chk_num_lines
      $error("axi4_master_linebuf : NUM_LINES must be >= 1 (NUM_LINES=%0d)", NUM_LINES);
    end
    if( IN_FIFO_DEPTH<IN_MAX_BURST ) begin : g_chk_in_fifo
      $error("axi4_master_linebuf : IN_FIFO_DEPTH (%0d) must be >= IN_MAX_BURST (%0d)", IN_FIFO_DEPTH, IN_MAX_BURST);
    end
    if( OUT_FIFO_DEPTH<OUT_MAX_BURST ) begin : g_chk_out_fifo
      $error("axi4_master_linebuf : OUT_FIFO_DEPTH (%0d) must be >= OUT_MAX_BURST (%0d)", OUT_FIFO_DEPTH, OUT_MAX_BURST);
    end
    if( (IN_ID_WIDTH<32)&&((IN_AXI_ID>>IN_ID_WIDTH)!=0) ) begin : g_chk_in_id
      $error("axi4_master_linebuf : IN_AXI_ID (%0d) does not fit in IN_ID_WIDTH (%0d)", IN_AXI_ID, IN_ID_WIDTH);
    end
    if( (OUT_ID_WIDTH<32)&&((OUT_AXI_ID>>OUT_ID_WIDTH)!=0) ) begin : g_chk_out_id
      $error("axi4_master_linebuf : OUT_AXI_ID (%0d) does not fit in OUT_ID_WIDTH (%0d)", OUT_AXI_ID, OUT_ID_WIDTH);
    end
    if( (HEIGHT_WIDTH<1)||(STRIDE_WIDTH<1) ) begin : g_chk_cmd_width
      $error("axi4_master_linebuf : HEIGHT_WIDTH / STRIDE_WIDTH must be >= 1");
    end
    if( (STRIDE_WIDTH>IN_ADDR_WIDTH)||(STRIDE_WIDTH>OUT_ADDR_WIDTH) ) begin : g_chk_stride_width
      $error("axi4_master_linebuf : STRIDE_WIDTH (%0d) must be <= IN_ADDR_WIDTH (%0d) and OUT_ADDR_WIDTH (%0d)", STRIDE_WIDTH, IN_ADDR_WIDTH, OUT_ADDR_WIDTH);
    end
  endgenerate
`endif

endmodule
