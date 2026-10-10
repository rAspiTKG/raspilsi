//=============================================================================
// axil_master_mem.sv
//-----------------------------------------------------------------------------
//  AXI4-Lite マスタ (Manager) + 内部メモリ (汎用レジスタ)。
//  内部メモリと AXI4-Lite の間で、コマンド 1 つにつき連続したワードをまとめて転送する。
//  書き込みコマンドと読み出しコマンドは別々に受け付け、同時に実行できる。
//
//      mem_w_* (ローカル書き込み) --> [内部メモリ 1R1W] --> mem_r_* (ローカル読み出し)
//                                     |  ^
//            書き込みコマンドが読む    v  |  読み出しコマンドが書く
//      wcmd_* / wr_* --> [書き込みシーケンサ] --> [axil_master_engine] --> AW / W / B
//      rcmd_* / rd_* --> [読み出しシーケンサ] --> [axil_master_engine] --> AR / R
//
//    書き込みコマンド : 内部メモリ [wcmd_mem_addr から wcmd_len ワード] を AXI へ書く
//    読み出しコマンド : AXI から rcmd_len ワード読み、内部メモリ [rcmd_mem_addr から] に入れる
//
//  parameter で調整できるもの:
//    ADDR_WIDTH         : AWADDR / ARADDR のビット幅 (DATA_WIDTH/8 のビット数 .. 64)
//    DATA_WIDTH         : WDATA / RDATA のビット幅 (AXI4-Lite なので 32 / 64)
//    MEM_DEPTH          : 内部メモリのワード数 (1 ワード = DATA_WIDTH ビット)
//    MAX_WR_OUTSTANDING : 応答を待たずに出せる書き込みの数
//    MAX_RD_OUTSTANDING : 応答を待たずに出せる読み出しの数
//    STOP_ON_ERROR      : 1 = エラー応答を受けたら、それ以降のトランザクションを出さない / 0 = 最後まで続ける
//
//  コマンド (書き込み wcmd_* / 読み出し rcmd_*。それぞれアイドル時のみ ready=1):
//    *_addr     : AXI の先頭アドレス (DATA_WIDTH/8 バイトの倍数)
//    *_incr     : 1 = 1 トランザクションごとにアドレスを DATA_WIDTH/8 進める / 0 = 同じアドレスに繰り返す
//    *_mem_addr : 内部メモリの先頭ワード番号
//    *_len      : トランザクション数 (0 なら何もせず完了)
//    wcmd_strb  : WSTRB (全トランザクションで共通)
//    *_prot     : AWPROT / ARPROT (全トランザクションで共通)
//
//  ステータス (書き込み wr_* / 読み出し rd_*):
//    *_done       : 完了で 1 サイクル。以下は done と同じサイクルで見る (次のコマンド受付まで保持)
//    *_done_err   : *_err_flags のどれかが 1
//    *_err_flags  : [0] SLVERR を受けた / [1] DECERR を受けた / [2] コマンドの誤り (トランザクションは出さない) /
//                   [3] EXOKAY を受けた (AXI4-Lite のスレーブは返してはいけない応答)
//    *_err_index  : 最初にエラー応答を受けたトランザクションの番号 (0 始まり)。*_err_flags の [0] [1] [3] のとき有効
//    *_done_count : 応答を受けたトランザクションの数 (= バスで完了した数)
//
//  エラー時の動作:
//    - STOP_ON_ERROR=1 : エラー応答を受けたサイクルから、新しいトランザクションを出さない。
//                        すでに出していたもの (最大 MAX_*_OUTSTANDING-1 個) は応答を待って完了させる
//                        (done_count は err_index+1 .. err_index+MAX_*_OUTSTANDING)
//    - STOP_ON_ERROR=0 : 最後まで出し、done のときに err_flags で通知する
//    - エラー応答の読み出しデータは内部メモリに書かない (元の値のまま)
//
//  内部メモリのローカルポート:
//    - 書き込み (mem_w_*) は内部メモリの書き込みポートを読み出しコマンドと共有するので、
//      読み出しコマンドの実行中 (rd_busy=1) は mem_w_ready=0
//    - 読み出し (mem_r_*) は読み出しポートを書き込みコマンドと共有するので、
//      書き込みコマンドの実行中 (wr_busy=1) は mem_r_ready=0。受け付けた次のサイクルに mem_r_rvalid=1 とデータ
//    - MEM_DEPTH 以上のアドレスは、書き込みを無視し、読み出しは 0 を返す
//    - 実行中のコマンドが使っている領域をローカルポートで触ったとき、同時に実行している
//      書き込み / 読み出しコマンドの内部メモリの領域が重なっているときの値は不定
//
//  転送速度: AWREADY / WREADY / ARREADY が毎サイクル 1 で、MAX_*_OUTSTANDING がスレーブの応答の待ち L
//            (AW と W / AR を受けた次のサイクルに応答を出すなら 0) に対して L + 3 以上なら、
//            書き込み / 読み出しとも 1 サイクルに 1 トランザクション (読み書きは同時に動く)。
//            L = 0 で MAX_*_OUTSTANDING が 3 以上なら、受付から done まで 書き込み 7 + (len-1) /
//            読み出し 5 + (len-1) サイクル (README の「転送速度」を参照)。
//
//  参考: AMBA AXI Protocol Specification (Arm IHI 0022)
//=============================================================================
`timescale 1ns / 1ps

module axil_master_mem #(
  parameter int unsigned ADDR_WIDTH         = 32
 ,parameter int unsigned DATA_WIDTH         = 32
 ,parameter int unsigned MEM_DEPTH          = 16
 ,parameter int unsigned MAX_WR_OUTSTANDING = 4
 ,parameter int unsigned MAX_RD_OUTSTANDING = 4
 ,parameter bit          STOP_ON_ERROR      = 1'b1
) (
  //---------------------------------------------------------------------------
  // Global
  //---------------------------------------------------------------------------
  input  logic                                                 aclk
 ,input  logic                                                 aresetn
  //---------------------------------------------------------------------------
  // 書き込みコマンド (内部メモリ -> AXI)
  //---------------------------------------------------------------------------
 ,input  logic                                                 wcmd_valid
 ,output logic                                                 wcmd_ready
 ,input  logic [ADDR_WIDTH-1:0]                                wcmd_addr
 ,input  logic                                                 wcmd_incr
 ,input  logic [((MEM_DEPTH<2) ? 1 : $clog2(MEM_DEPTH))-1:0]   wcmd_mem_addr
 ,input  logic [((MEM_DEPTH<1) ? 1 : $clog2(MEM_DEPTH+1))-1:0] wcmd_len
 ,input  logic [(DATA_WIDTH/8)-1:0]                            wcmd_strb
 ,input  logic [2:0]                                           wcmd_prot
  //---------------------------------------------------------------------------
  // 書き込みのステータス
  //---------------------------------------------------------------------------
 ,output logic                                                 wr_busy
 ,output logic                                                 wr_done
 ,output logic                                                 wr_done_err
 ,output logic [3:0]                                           wr_err_flags
 ,output logic [((MEM_DEPTH<1) ? 1 : $clog2(MEM_DEPTH+1))-1:0] wr_err_index
 ,output logic [((MEM_DEPTH<1) ? 1 : $clog2(MEM_DEPTH+1))-1:0] wr_done_count
  //---------------------------------------------------------------------------
  // 読み出しコマンド (AXI -> 内部メモリ)
  //---------------------------------------------------------------------------
 ,input  logic                                                 rcmd_valid
 ,output logic                                                 rcmd_ready
 ,input  logic [ADDR_WIDTH-1:0]                                rcmd_addr
 ,input  logic                                                 rcmd_incr
 ,input  logic [((MEM_DEPTH<2) ? 1 : $clog2(MEM_DEPTH))-1:0]   rcmd_mem_addr
 ,input  logic [((MEM_DEPTH<1) ? 1 : $clog2(MEM_DEPTH+1))-1:0] rcmd_len
 ,input  logic [2:0]                                           rcmd_prot
  //---------------------------------------------------------------------------
  // 読み出しのステータス
  //---------------------------------------------------------------------------
 ,output logic                                                 rd_busy
 ,output logic                                                 rd_done
 ,output logic                                                 rd_done_err
 ,output logic [3:0]                                           rd_err_flags
 ,output logic [((MEM_DEPTH<1) ? 1 : $clog2(MEM_DEPTH+1))-1:0] rd_err_index
 ,output logic [((MEM_DEPTH<1) ? 1 : $clog2(MEM_DEPTH+1))-1:0] rd_done_count
  //---------------------------------------------------------------------------
  // 内部メモリのローカルポート (書き込み / 読み出しは別々)
  //---------------------------------------------------------------------------
 ,input  logic                                                 mem_w_valid
 ,output logic                                                 mem_w_ready
 ,input  logic [((MEM_DEPTH<2) ? 1 : $clog2(MEM_DEPTH))-1:0]   mem_w_addr
 ,input  logic [DATA_WIDTH-1:0]                                mem_w_data
 ,input  logic                                                 mem_r_valid
 ,output logic                                                 mem_r_ready
 ,input  logic [((MEM_DEPTH<2) ? 1 : $clog2(MEM_DEPTH))-1:0]   mem_r_addr
 ,output logic                                                 mem_r_rvalid
 ,output logic [DATA_WIDTH-1:0]                                mem_r_rdata
  //---------------------------------------------------------------------------
  // AXI5 の AWAKEUP 用 (AXI4-Lite だけで使うなら未接続でよい)
  //---------------------------------------------------------------------------
 ,output logic                                                 axi_wakeup
  //---------------------------------------------------------------------------
  // AXI4-Lite master
  //---------------------------------------------------------------------------
 ,output logic [ADDR_WIDTH-1:0]                                m_axi_awaddr
 ,output logic [2:0]                                           m_axi_awprot
 ,output logic                                                 m_axi_awvalid
 ,input  logic                                                 m_axi_awready
 ,output logic [DATA_WIDTH-1:0]                                m_axi_wdata
 ,output logic [(DATA_WIDTH/8)-1:0]                            m_axi_wstrb
 ,output logic                                                 m_axi_wvalid
 ,input  logic                                                 m_axi_wready
 ,input  logic [1:0]                                           m_axi_bresp
 ,input  logic                                                 m_axi_bvalid
 ,output logic                                                 m_axi_bready
 ,output logic [ADDR_WIDTH-1:0]                                m_axi_araddr
 ,output logic [2:0]                                           m_axi_arprot
 ,output logic                                                 m_axi_arvalid
 ,input  logic                                                 m_axi_arready
 ,input  logic [DATA_WIDTH-1:0]                                m_axi_rdata
 ,input  logic [1:0]                                           m_axi_rresp
 ,input  logic                                                 m_axi_rvalid
 ,output logic                                                 m_axi_rready
);

  //---------------------------------------------------------------------------
  // Local parameters
  //---------------------------------------------------------------------------
  localparam int unsigned STRB_W   = DATA_WIDTH / 8;
  localparam int unsigned STRB_LSB = $clog2(STRB_W);
  localparam int unsigned MEM_AW   = (MEM_DEPTH<2) ? 1 : $clog2(MEM_DEPTH);
  // (MEM_DEPTH が 0 のときもビット幅を 1 にして、下のパラメータチェックでエラーにする)
  localparam int unsigned LEN_W    = (MEM_DEPTH<1) ? 1 : $clog2(MEM_DEPTH+1);

  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_EXOKAY = 2'b01;
  localparam logic [1:0] RESP_SLVERR = 2'b10;
  localparam logic [1:0] RESP_DECERR = 2'b11;

  typedef enum logic [1:0] {
    S_IDLE = 2'd0
   ,S_RUN  = 2'd1
   ,S_DONE = 2'd2
  } seq_e;

  //---------------------------------------------------------------------------
  // エンジンとの接続信号
  //---------------------------------------------------------------------------
  logic                  wreq_valid;
  logic                  wreq_ready;
  logic                  wreq_fire;
  logic [DATA_WIDTH-1:0] wreq_data;
  logic                  wrsp_valid;
  logic [1:0]            wrsp_resp;
  logic                  rreq_valid;
  logic                  rreq_ready;
  logic                  rreq_fire;
  logic                  rrsp_valid;
  logic [DATA_WIDTH-1:0] rrsp_data;
  logic [1:0]            rrsp_resp;
  logic                  eng_wr_busy;
  logic                  eng_rd_busy;

  //---------------------------------------------------------------------------
  // 内部メモリとの接続信号
  //---------------------------------------------------------------------------
  logic                  sram_we;
  logic [MEM_AW-1:0]     sram_waddr;
  logic [DATA_WIDTH-1:0] sram_wdata;
  logic                  sram_re;
  logic [MEM_AW-1:0]     sram_raddr;
  logic [DATA_WIDTH-1:0] sram_rdata;

  //---------------------------------------------------------------------------
  // コマンドの検査
  //   empty : 0 ワード (何もせず完了)
  //   bad   : メモリ範囲が MEM_DEPTH を超える / アドレスが非アライン /
  //           インクリメントでアドレスが ADDR_WIDTH の範囲を超える
  //---------------------------------------------------------------------------
  logic wcmd_empty;
  logic wcmd_bad;
  logic rcmd_empty;
  logic rcmd_bad;

  assign wcmd_empty = (wcmd_len=={LEN_W{1'b0}});
  assign wcmd_bad   = ((32'(wcmd_mem_addr) + 32'(wcmd_len))>32'(MEM_DEPTH))
                    ||((wcmd_addr&ADDR_WIDTH'(STRB_W-1))!={ADDR_WIDTH{1'b0}})
                    ||(wcmd_incr&&((66'(wcmd_addr) + (66'(wcmd_len) << STRB_LSB))>(66'd1 << ADDR_WIDTH)));
  assign rcmd_empty = (rcmd_len=={LEN_W{1'b0}});
  assign rcmd_bad   = ((32'(rcmd_mem_addr) + 32'(rcmd_len))>32'(MEM_DEPTH))
                    ||((rcmd_addr&ADDR_WIDTH'(STRB_W-1))!={ADDR_WIDTH{1'b0}})
                    ||(rcmd_incr&&((66'(rcmd_addr) + (66'(rcmd_len) << STRB_LSB))>(66'd1 << ADDR_WIDTH)));

  //===========================================================================
  // 書き込みシーケンサ (内部メモリ -> AXI)
  //   内部メモリから 1 ワードずつ読み、2 段の FIFO に入れてからエンジンへ渡す。
  //   FIFO に空きがある分だけ先に読むので、エンジンが毎サイクル受ければ 1 サイクルに 1 ワード流れる
  //===========================================================================
  seq_e                  wstate;
  logic [ADDR_WIDTH-1:0] w_addr_q;       // 次に出すトランザクションの AXI アドレス
  logic                  w_incr_q;
  logic [STRB_W-1:0]     w_strb_q;
  logic [2:0]            w_prot_q;
  logic [LEN_W-1:0]      w_len_q;
  logic [MEM_AW-1:0]     w_fetch_ptr;    // 次に読む内部メモリのワード
  logic [LEN_W-1:0]      w_fetch_left;   // まだ読んでいないワード数
  logic                  w_fetch_pend;   // 前のサイクルに読んだ (このサイクルに rdata が有効)
  logic [LEN_W-1:0]      w_issued;       // エンジンに渡した数
  logic [LEN_W-1:0]      w_rsp_cnt;      // 応答を受けた数
  logic                  w_stop_q;
  logic                  w_err_slv;
  logic                  w_err_dec;
  logic                  w_err_cfg;
  logic                  w_err_exo;
  logic [LEN_W-1:0]      w_err_index_q;
  // 送信データの FIFO (2 段)
  logic [DATA_WIDTH-1:0] wf_data [0:1];
  logic                  wf_wp;
  logic                  wf_rp;
  logic [1:0]            wf_cnt;
  logic [1:0]            wf_cnt_nxt;

  logic                  w_rsp_err;
  logic                  w_stop;         // このサイクルから新しいトランザクションを出さない
  logic                  w_fetch;
  logic                  w_finish;       // このサイクルの応答で完了する

  assign w_rsp_err = wrsp_valid&&(wrsp_resp!=RESP_OKAY);
  assign w_stop    = w_stop_q||(STOP_ON_ERROR&&w_rsp_err);

  // FIFO の個数 (このサイクルの書き込み / 取り出しを反映した後)
  assign wf_cnt_nxt = wf_cnt + {1'b0, w_fetch_pend} - {1'b0, wreq_fire};

  // 次のサイクルに読み出しデータを入れる場所があるときだけ読む
  assign w_fetch    = (wstate==S_RUN)&&(w_fetch_left!={LEN_W{1'b0}})&&!w_stop&&(wf_cnt_nxt<2'd2);

  assign wreq_valid = (wstate==S_RUN)&&(wf_cnt!=2'd0)&&!w_stop;
  assign wreq_fire  = wreq_valid&&wreq_ready;
  assign wreq_data  = wf_data[wf_rp];

  // 最後の応答 (全て出し終えた、または中止した) で完了
  assign w_finish   = (wstate==S_RUN)&&wrsp_valid&&((w_rsp_cnt + LEN_W'(1))==w_issued)&&((w_issued==w_len_q)||w_stop);

  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      wstate        <= S_IDLE;
      w_addr_q      <= {ADDR_WIDTH{1'b0}};
      w_incr_q      <= 1'b0;
      w_strb_q      <= {STRB_W{1'b0}};
      w_prot_q      <= 3'b000;
      w_len_q       <= {LEN_W{1'b0}};
      w_fetch_ptr   <= {MEM_AW{1'b0}};
      w_fetch_left  <= {LEN_W{1'b0}};
      w_fetch_pend  <= 1'b0;
      w_issued      <= {LEN_W{1'b0}};
      w_rsp_cnt     <= {LEN_W{1'b0}};
      w_stop_q      <= 1'b0;
      w_err_slv     <= 1'b0;
      w_err_dec     <= 1'b0;
      w_err_cfg     <= 1'b0;
      w_err_exo     <= 1'b0;
      w_err_index_q <= {LEN_W{1'b0}};
      wf_data[0]    <= {DATA_WIDTH{1'b0}};
      wf_data[1]    <= {DATA_WIDTH{1'b0}};
      wf_wp         <= 1'b0;
      wf_rp         <= 1'b0;
      wf_cnt        <= 2'd0;
    end else begin
      w_fetch_pend <= w_fetch;
      case( wstate )
        S_IDLE : begin
          if( wcmd_valid ) begin
            w_addr_q      <= wcmd_addr;
            w_incr_q      <= wcmd_incr;
            w_strb_q      <= wcmd_strb;
            w_prot_q      <= wcmd_prot;
            w_len_q       <= wcmd_len;
            w_fetch_ptr   <= wcmd_mem_addr;
            w_fetch_left  <= wcmd_len;
            w_issued      <= {LEN_W{1'b0}};
            w_rsp_cnt     <= {LEN_W{1'b0}};
            w_stop_q      <= 1'b0;
            w_err_slv     <= 1'b0;
            w_err_dec     <= 1'b0;
            w_err_exo     <= 1'b0;
            w_err_index_q <= {LEN_W{1'b0}};
            wf_wp         <= 1'b0;
            wf_rp         <= 1'b0;
            wf_cnt        <= 2'd0;
            if( wcmd_empty ) begin
              w_err_cfg <= 1'b0;
              wstate    <= S_DONE;
            end else if( wcmd_bad ) begin
              w_err_cfg <= 1'b1;
              wstate    <= S_DONE;
            end else begin
              w_err_cfg <= 1'b0;
              wstate    <= S_RUN;
            end
          end
        end
        S_RUN : begin
          // 内部メモリの読み出し
          if( w_fetch ) begin
            w_fetch_ptr  <= w_fetch_ptr + MEM_AW'(1);
            w_fetch_left <= w_fetch_left - LEN_W'(1);
          end
          // FIFO
          if( w_fetch_pend ) begin
            wf_data[wf_wp] <= sram_rdata;
            wf_wp          <= !wf_wp;
          end
          if( wreq_fire ) begin
            wf_rp    <= !wf_rp;
            w_issued <= w_issued + LEN_W'(1);
            if( w_incr_q ) begin
              w_addr_q <= w_addr_q + ADDR_WIDTH'(STRB_W);
            end
          end
          wf_cnt <= wf_cnt_nxt;
          // 応答
          if( wrsp_valid ) begin
            w_rsp_cnt <= w_rsp_cnt + LEN_W'(1);
            if( w_rsp_err&&!w_err_slv&&!w_err_dec&&!w_err_exo ) begin
              w_err_index_q <= w_rsp_cnt;
            end
            if( wrsp_resp==RESP_SLVERR ) begin
              w_err_slv <= 1'b1;
            end
            if( wrsp_resp==RESP_DECERR ) begin
              w_err_dec <= 1'b1;
            end
            if( wrsp_resp==RESP_EXOKAY ) begin
              w_err_exo <= 1'b1;
            end
          end
          if( w_stop ) begin
            w_stop_q <= 1'b1;
          end
          if( w_finish ) begin
            wstate <= S_DONE;
          end
        end
        S_DONE : begin
          wstate <= S_IDLE;
        end
        default : begin
          wstate <= S_IDLE;
        end
      endcase
    end
  end

  assign wcmd_ready    = (wstate==S_IDLE);
  assign wr_busy       = (wstate!=S_IDLE);
  assign wr_done       = (wstate==S_DONE);
  assign wr_err_flags  = {w_err_exo, w_err_cfg, w_err_dec, w_err_slv};
  assign wr_done_err   = w_err_exo||w_err_cfg||w_err_dec||w_err_slv;
  assign wr_err_index  = w_err_index_q;
  assign wr_done_count = w_rsp_cnt;

  //===========================================================================
  // 読み出しシーケンサ (AXI -> 内部メモリ)
  //   要求を出し続け、応答が来るたびに内部メモリへ書く
  //===========================================================================
  seq_e                  rstate;
  logic [ADDR_WIDTH-1:0] r_addr_q;
  logic                  r_incr_q;
  logic [2:0]            r_prot_q;
  logic [LEN_W-1:0]      r_len_q;
  logic [MEM_AW-1:0]     r_rsp_ptr;      // 次の応答を書く内部メモリのワード
  logic [LEN_W-1:0]      r_issued;
  logic [LEN_W-1:0]      r_rsp_cnt;
  logic                  r_stop_q;
  logic                  r_err_slv;
  logic                  r_err_dec;
  logic                  r_err_cfg;
  logic                  r_err_exo;
  logic [LEN_W-1:0]      r_err_index_q;

  logic                  r_rsp_err;
  logic                  r_stop;
  logic                  r_finish;
  logic                  r_seq_wr;       // 応答のデータを内部メモリへ書く

  assign r_rsp_err  = rrsp_valid&&(rrsp_resp!=RESP_OKAY);
  assign r_stop     = r_stop_q||(STOP_ON_ERROR&&r_rsp_err);

  assign rreq_valid = (rstate==S_RUN)&&(r_issued!=r_len_q)&&!r_stop;
  assign rreq_fire  = rreq_valid&&rreq_ready;

  assign r_finish   = (rstate==S_RUN)&&rrsp_valid&&((r_rsp_cnt + LEN_W'(1))==r_issued)&&((r_issued==r_len_q)||r_stop);
  assign r_seq_wr   = (rstate==S_RUN)&&rrsp_valid&&(rrsp_resp==RESP_OKAY);

  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      rstate        <= S_IDLE;
      r_addr_q      <= {ADDR_WIDTH{1'b0}};
      r_incr_q      <= 1'b0;
      r_prot_q      <= 3'b000;
      r_len_q       <= {LEN_W{1'b0}};
      r_rsp_ptr     <= {MEM_AW{1'b0}};
      r_issued      <= {LEN_W{1'b0}};
      r_rsp_cnt     <= {LEN_W{1'b0}};
      r_stop_q      <= 1'b0;
      r_err_slv     <= 1'b0;
      r_err_dec     <= 1'b0;
      r_err_cfg     <= 1'b0;
      r_err_exo     <= 1'b0;
      r_err_index_q <= {LEN_W{1'b0}};
    end else begin
      case( rstate )
        S_IDLE : begin
          if( rcmd_valid ) begin
            r_addr_q      <= rcmd_addr;
            r_incr_q      <= rcmd_incr;
            r_prot_q      <= rcmd_prot;
            r_len_q       <= rcmd_len;
            r_rsp_ptr     <= rcmd_mem_addr;
            r_issued      <= {LEN_W{1'b0}};
            r_rsp_cnt     <= {LEN_W{1'b0}};
            r_stop_q      <= 1'b0;
            r_err_slv     <= 1'b0;
            r_err_dec     <= 1'b0;
            r_err_exo     <= 1'b0;
            r_err_index_q <= {LEN_W{1'b0}};
            if( rcmd_empty ) begin
              r_err_cfg <= 1'b0;
              rstate    <= S_DONE;
            end else if( rcmd_bad ) begin
              r_err_cfg <= 1'b1;
              rstate    <= S_DONE;
            end else begin
              r_err_cfg <= 1'b0;
              rstate    <= S_RUN;
            end
          end
        end
        S_RUN : begin
          if( rreq_fire ) begin
            r_issued <= r_issued + LEN_W'(1);
            if( r_incr_q ) begin
              r_addr_q <= r_addr_q + ADDR_WIDTH'(STRB_W);
            end
          end
          if( rrsp_valid ) begin
            r_rsp_cnt <= r_rsp_cnt + LEN_W'(1);
            r_rsp_ptr <= r_rsp_ptr + MEM_AW'(1);
            if( r_rsp_err&&!r_err_slv&&!r_err_dec&&!r_err_exo ) begin
              r_err_index_q <= r_rsp_cnt;
            end
            if( rrsp_resp==RESP_SLVERR ) begin
              r_err_slv <= 1'b1;
            end
            if( rrsp_resp==RESP_DECERR ) begin
              r_err_dec <= 1'b1;
            end
            if( rrsp_resp==RESP_EXOKAY ) begin
              r_err_exo <= 1'b1;
            end
          end
          if( r_stop ) begin
            r_stop_q <= 1'b1;
          end
          if( r_finish ) begin
            rstate <= S_DONE;
          end
        end
        S_DONE : begin
          rstate <= S_IDLE;
        end
        default : begin
          rstate <= S_IDLE;
        end
      endcase
    end
  end

  assign rcmd_ready    = (rstate==S_IDLE);
  assign rd_busy       = (rstate!=S_IDLE);
  assign rd_done       = (rstate==S_DONE);
  assign rd_err_flags  = {r_err_exo, r_err_cfg, r_err_dec, r_err_slv};
  assign rd_done_err   = r_err_exo||r_err_cfg||r_err_dec||r_err_slv;
  assign rd_err_index  = r_err_index_q;
  assign rd_done_count = r_rsp_cnt;

  //===========================================================================
  // 内部メモリ (1R1W)
  //   書き込みポート : 読み出しコマンドの応答 / ローカル書き込み (読み出しコマンドがアイドルのときだけ)
  //   読み出しポート : 書き込みコマンドの送信データ / ローカル読み出し (書き込みコマンドがアイドルのときだけ)
  //===========================================================================
  logic mem_w_fire;
  logic mem_r_fire;
  logic lw_ok;            // ローカル書き込みのアドレスが範囲内
  logic lr_ok;            // ローカル読み出しのアドレスが範囲内

  assign mem_w_ready = (rstate==S_IDLE);
  assign mem_r_ready = (wstate==S_IDLE);
  assign mem_w_fire  = mem_w_valid&&mem_w_ready;
  assign mem_r_fire  = mem_r_valid&&mem_r_ready;

  assign sram_we     = r_seq_wr||(mem_w_fire&&lw_ok);
  assign sram_waddr  = r_seq_wr ? r_rsp_ptr : mem_w_addr;
  assign sram_wdata  = r_seq_wr ? rrsp_data : mem_w_data;
  assign sram_re     = w_fetch||(mem_r_fire&&lr_ok);
  assign sram_raddr  = w_fetch ? w_fetch_ptr : mem_r_addr;

  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      mem_r_rvalid <= 1'b0;
    end else begin
      mem_r_rvalid <= mem_r_fire;
    end
  end

  // ローカルポートのアドレスのビット幅で MEM_DEPTH 以上の値を表せるときだけ、範囲を確認する
  generate
    if( (1<<MEM_AW)>MEM_DEPTH ) begin : g_loc_chk
      logic lr_ok_q;

      assign lw_ok       = (32'(mem_w_addr)<32'(MEM_DEPTH));
      assign lr_ok       = (32'(mem_r_addr)<32'(MEM_DEPTH));
      assign mem_r_rdata = lr_ok_q ? sram_rdata : {DATA_WIDTH{1'b0}};

      always @(posedge aclk or negedge aresetn) begin
        if( !aresetn ) begin
          lr_ok_q <= 1'b0;
        end else begin
          lr_ok_q <= lr_ok;
        end
      end
    end else begin : g_loc_nochk
      assign lw_ok       = 1'b1;
      assign lr_ok       = 1'b1;
      assign mem_r_rdata = sram_rdata;
    end
  endgenerate

  axil_master_sram_2p #(
    .DEPTH(MEM_DEPTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.ADDR_WIDTH(MEM_AW)
  ) u_mem (
    .clk(aclk)
   ,.we(sram_we)
   ,.waddr(sram_waddr)
   ,.wdata(sram_wdata)
   ,.re(sram_re)
   ,.raddr(sram_raddr)
   ,.rdata(sram_rdata)
  );

  //===========================================================================
  // AXI4-Lite 転送エンジン
  //===========================================================================
  axil_master_engine #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.MAX_WR_OUTSTANDING(MAX_WR_OUTSTANDING)
   ,.MAX_RD_OUTSTANDING(MAX_RD_OUTSTANDING)
  ) u_engine (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.wreq_valid(wreq_valid)
   ,.wreq_ready(wreq_ready)
   ,.wreq_addr(w_addr_q)
   ,.wreq_data(wreq_data)
   ,.wreq_strb(w_strb_q)
   ,.wreq_prot(w_prot_q)
   ,.wrsp_valid(wrsp_valid)
   ,.wrsp_resp(wrsp_resp)
   ,.rreq_valid(rreq_valid)
   ,.rreq_ready(rreq_ready)
   ,.rreq_addr(r_addr_q)
   ,.rreq_prot(r_prot_q)
   ,.rrsp_valid(rrsp_valid)
   ,.rrsp_data(rrsp_data)
   ,.rrsp_resp(rrsp_resp)
   ,.wr_busy(eng_wr_busy)
   ,.rd_busy(eng_rd_busy)
   ,.axi_wakeup(axi_wakeup)
   ,.m_axi_awaddr(m_axi_awaddr)
   ,.m_axi_awprot(m_axi_awprot)
   ,.m_axi_awvalid(m_axi_awvalid)
   ,.m_axi_awready(m_axi_awready)
   ,.m_axi_wdata(m_axi_wdata)
   ,.m_axi_wstrb(m_axi_wstrb)
   ,.m_axi_wvalid(m_axi_wvalid)
   ,.m_axi_wready(m_axi_wready)
   ,.m_axi_bresp(m_axi_bresp)
   ,.m_axi_bvalid(m_axi_bvalid)
   ,.m_axi_bready(m_axi_bready)
   ,.m_axi_araddr(m_axi_araddr)
   ,.m_axi_arprot(m_axi_arprot)
   ,.m_axi_arvalid(m_axi_arvalid)
   ,.m_axi_arready(m_axi_arready)
   ,.m_axi_rdata(m_axi_rdata)
   ,.m_axi_rresp(m_axi_rresp)
   ,.m_axi_rvalid(m_axi_rvalid)
   ,.m_axi_rready(m_axi_rready)
  );

  //---------------------------------------------------------------------------
  // 未使用信号
  //---------------------------------------------------------------------------
  logic unused_ok;
  assign unused_ok = &{1'b0, eng_wr_busy, eng_rd_busy};

  //---------------------------------------------------------------------------
  // パラメータチェック (エラボレーション時。IEEE 1800 20.11)
  //   対応していない合成ツールでは +define+AXIL_MASTER_NO_ELAB_CHECK で外す
  //   (DATA_WIDTH / ADDR_WIDTH / MAX_*_OUTSTANDING はエンジン側で確認する)
  //---------------------------------------------------------------------------
`ifndef AXIL_MASTER_NO_ELAB_CHECK
  generate
    if( MEM_DEPTH<1 ) begin : g_chk_depth
      $error("axil_master_mem : MEM_DEPTH must be >= 1 (MEM_DEPTH=%0d)", MEM_DEPTH);
    end
  endgenerate
`endif

endmodule
