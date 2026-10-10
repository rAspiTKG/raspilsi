//=============================================================================
// apb_master_engine.sv
//-----------------------------------------------------------------------------
//  APB マスタ (Requester) の転送エンジン。
//  要求 (アドレス / 方向 / 書き込みデータ) を valid/ready で 1 つ受けるごとに
//  APB の転送を 1 回行い、結果を応答 (1 サイクルのパルス) として返す。
//
//      req_* (valid/ready) --> [保留 1 段] --> IDLE -> SETUP -> ACCESS --> APB
//      rsp_* (パルス)      <-------------------------------- PREADY / PRDATA / PSLVERR
//
//  動作 (AMBA APB Protocol Specification, Arm IHI 0024E 4.1 Operating states):
//    - IDLE   : PSEL=0。要求があれば SETUP へ
//    - SETUP  : PSEL=1, PENABLE=0 を 1 サイクル。必ず ACCESS へ進む
//    - ACCESS : PENABLE=1。PREADY=1 で転送完了。次の要求があれば SETUP へ直接進み
//               (back-to-back)、無ければ IDLE へ戻る
//    - SETUP から転送完了まで PADDR / PPROT / PWRITE / PWDATA / PSTRB は変えない
//    - 読み出しでは PSTRB を全て 0 にする (IHI 0024E 3.2)
//    - PSLVERR は PSEL && PENABLE && PREADY のサイクルだけ見る (IHI 0024E 3.4)
//
//  要求 / 応答:
//    - req_ready は保留レジスタの空き (登録値) だけで決まる。PREADY には依存しない
//    - 転送中にも次の要求を 1 つ先に受け付けるので、PREADY が常に 1 なら
//      2 サイクルに 1 転送 (APB の最短) で連続転送できる
//    - 応答は要求を受けた順に、転送完了の次のサイクルに rsp_valid=1 で出る
//        rsp_rdata   : 読み出しデータ (書き込み / 打ち切りのときは 0)
//        rsp_slverr  : PSLVERR を受けた。または req_sel が NUM_SLAVES 以上だった
//        rsp_timeout : タイムアウトで打ち切った
//    - req_sel が NUM_SLAVES 以上の要求は、バスには何も出さずに rsp_slverr=1 を返す
//
//  PSEL が複数 (NUM_SLAVES > 1) の場合:
//    - PADDR / PWDATA などは全スレーブ共通、PSEL だけ req_sel の 1 本を立てる
//    - PREADY / PRDATA / PSLVERR はスレーブごとに入力し、内部で選択する
//      (prdata はスレーブ i の分が [i*DATA_WIDTH +: DATA_WIDTH])
//
//  タイムアウト (TIMEOUT_CYCLES > 0 のとき):
//    - ACCESS が TIMEOUT_CYCLES サイクル続いても PREADY が来なければ、PSEL / PENABLE を
//      下げて転送を打ち切る (待てるウェイトは TIMEOUT_CYCLES-1 サイクルまで)
//    - APB の仕様には転送を打ち切る規定が無い。バスのハングから復帰するための
//      仕様外の動作なので、既定 (0) では無効にしてある
//    - 打ち切った後に次の要求があれば、次のサイクルからその SETUP に入る
//      (同じスレーブへの要求なら PSEL は下がらない)
//
//  エラー時の破棄 (FLUSH_ON_ERROR = 1 のとき):
//    - エラー (PSLVERR / タイムアウト) で終わった転送より後に受け付けていた要求は、
//      バスに出さずに捨てる (捨てた要求には応答を返さない)
//    - エラーの次のサイクルは req_ready=0 にして、上位が応答を見て止まれるようにする
//
//  APB3 のスレーブにつなぐ場合は PSTRB / PPROT を未接続にする。PREADY / PSLVERR を
//  持たないスレーブは、入力をそれぞれ 1 / 0 に固定する。
//
//  参考: AMBA APB Protocol Specification (Arm IHI 0024E)
//        https://documentation-service.arm.com/static/63fe2c1356ea36189d4e79f3
//=============================================================================
`timescale 1ns / 1ps

module apb_master_engine #(
  parameter int unsigned ADDR_WIDTH     = 32
 ,parameter int unsigned DATA_WIDTH     = 32
 ,parameter int unsigned NUM_SLAVES     = 1
 ,parameter int unsigned TIMEOUT_CYCLES = 0
 ,parameter bit          FLUSH_ON_ERROR = 1'b0
) (
  //---------------------------------------------------------------------------
  // Global
  //---------------------------------------------------------------------------
  input  logic                                                 pclk
 ,input  logic                                                 presetn
  //---------------------------------------------------------------------------
  // 要求 (valid/ready)。1 要求 = 1 転送
  //---------------------------------------------------------------------------
 ,input  logic                                                 req_valid
 ,output logic                                                 req_ready
 ,input  logic                                                 req_write
 ,input  logic [((NUM_SLAVES<2) ? 1 : $clog2(NUM_SLAVES))-1:0] req_sel
 ,input  logic [ADDR_WIDTH-1:0]                                req_addr
 ,input  logic [DATA_WIDTH-1:0]                                req_wdata
 ,input  logic [(DATA_WIDTH/8)-1:0]                            req_strb
 ,input  logic [2:0]                                           req_prot
  //---------------------------------------------------------------------------
  // 応答 (rsp_valid は 1 サイクル)
  //---------------------------------------------------------------------------
 ,output logic                                                 rsp_valid
 ,output logic [DATA_WIDTH-1:0]                                rsp_rdata
 ,output logic                                                 rsp_slverr
 ,output logic                                                 rsp_timeout
  //---------------------------------------------------------------------------
  // ステータス (転送中、または保留中の要求がある)
  //---------------------------------------------------------------------------
 ,output logic                                                 busy
  //---------------------------------------------------------------------------
  // APB master
  //---------------------------------------------------------------------------
 ,output logic [ADDR_WIDTH-1:0]                                paddr
 ,output logic [2:0]                                           pprot
 ,output logic [NUM_SLAVES-1:0]                                psel
 ,output logic                                                 penable
 ,output logic                                                 pwrite
 ,output logic [DATA_WIDTH-1:0]                                pwdata
 ,output logic [(DATA_WIDTH/8)-1:0]                            pstrb
 ,input  logic [NUM_SLAVES-1:0]                                pready
 ,input  logic [(NUM_SLAVES*DATA_WIDTH)-1:0]                   prdata
 ,input  logic [NUM_SLAVES-1:0]                                pslverr
);

  //---------------------------------------------------------------------------
  // Local parameters
  //---------------------------------------------------------------------------
  localparam int unsigned STRB_W = DATA_WIDTH / 8;
  localparam int unsigned SEL_W  = (NUM_SLAVES<2) ? 1 : $clog2(NUM_SLAVES);

  typedef enum logic [1:0] {
    ST_IDLE   = 2'd0
   ,ST_SETUP  = 2'd1
   ,ST_ACCESS = 2'd2
  } state_e;

  //---------------------------------------------------------------------------
  // Registers
  //---------------------------------------------------------------------------
  state_e                state;
  // 転送中の要求 (APB 出力はこのレジスタから直接出す)
  logic [NUM_SLAVES-1:0] psel_q;
  logic                  penable_q;
  logic [ADDR_WIDTH-1:0] paddr_q;
  logic                  pwrite_q;
  logic [DATA_WIDTH-1:0] pwdata_q;
  logic [STRB_W-1:0]     pstrb_q;
  logic [2:0]            pprot_q;
  logic [SEL_W-1:0]      sel_q;
  logic                  nosel_q;      // 存在しない PSEL 番号への要求 (バスには出さない)
  // 保留中の要求 (1 段)
  logic                  pend_valid;
  logic                  pend_write;
  logic [SEL_W-1:0]      pend_sel;
  logic [ADDR_WIDTH-1:0] pend_addr;
  logic [DATA_WIDTH-1:0] pend_wdata;
  logic [STRB_W-1:0]     pend_strb;
  logic [2:0]            pend_prot;
  // エラーの次のサイクル (FLUSH_ON_ERROR のとき要求を受けない)
  logic                  err_hold;

  //---------------------------------------------------------------------------
  // 選択中のスレーブからの応答
  //---------------------------------------------------------------------------
  logic                  pready_sel;
  logic [DATA_WIDTH-1:0] prdata_sel;
  logic                  pslverr_sel;

  always @(*) begin
    if( nosel_q ) begin
      pready_sel  = 1'b1;
      prdata_sel  = {DATA_WIDTH{1'b0}};
      pslverr_sel = 1'b1;
    end else begin
      pready_sel  = pready[sel_q];
      prdata_sel  = prdata[(32'(sel_q)*DATA_WIDTH) +: DATA_WIDTH];
      pslverr_sel = pslverr[sel_q];
    end
  end

  //---------------------------------------------------------------------------
  // タイムアウト
  //   to_cnt は ACCESS に入ってからのサイクル数 (最初の ACCESS サイクルで 0)
  //---------------------------------------------------------------------------
  logic timeout_hit;

  generate
    if( TIMEOUT_CYCLES>0 ) begin : g_timeout
      localparam int unsigned TO_W = (TIMEOUT_CYCLES<2) ? 1 : $clog2(TIMEOUT_CYCLES);

      logic [TO_W-1:0] to_cnt;

      assign timeout_hit = (state==ST_ACCESS)&&!pready_sel&&(32'(to_cnt)==32'(TIMEOUT_CYCLES-1));

      always @(posedge pclk or negedge presetn) begin
        if( !presetn ) begin
          to_cnt <= {TO_W{1'b0}};
        end else begin
          if( state==ST_ACCESS ) begin
            to_cnt <= to_cnt + TO_W'(1);
          end else begin
            to_cnt <= {TO_W{1'b0}};
          end
        end
      end
    end else begin : g_no_timeout
      assign timeout_hit = 1'b0;
    end
  endgenerate

  //---------------------------------------------------------------------------
  // 次に始める要求の選択 (保留があれば保留、無ければ入力をそのまま使う)
  //---------------------------------------------------------------------------
  logic                  xfer_done;    // このサイクルで転送が終わる (PREADY または打ち切り)
  logic                  xfer_err;     // その転送がエラーで終わる
  logic                  flush;
  logic                  can_start;
  logic                  req_fire;
  logic                  nxt_valid;
  logic                  start;
  logic                  nxt_write;
  logic [SEL_W-1:0]      nxt_sel;
  logic                  nxt_sel_ok;
  logic [ADDR_WIDTH-1:0] nxt_addr;
  logic [DATA_WIDTH-1:0] nxt_wdata;
  logic [STRB_W-1:0]     nxt_strb;
  logic [2:0]            nxt_prot;

  assign xfer_done = (state==ST_ACCESS)&&(pready_sel||timeout_hit);
  assign xfer_err  = xfer_done&&(timeout_hit||pslverr_sel);
  assign flush     = FLUSH_ON_ERROR&&xfer_err;
  assign can_start = (state==ST_IDLE)||xfer_done;

  assign req_ready = !pend_valid&&!err_hold;
  assign req_fire  = req_valid&&req_ready;
  assign nxt_valid = pend_valid||req_fire;
  assign start     = can_start&&nxt_valid&&!flush;

  assign nxt_write = pend_valid ? pend_write : req_write;
  assign nxt_sel   = pend_valid ? pend_sel   : req_sel;
  assign nxt_addr  = pend_valid ? pend_addr  : req_addr;
  assign nxt_wdata = pend_valid ? pend_wdata : req_wdata;
  assign nxt_strb  = pend_valid ? pend_strb  : req_strb;
  assign nxt_prot  = pend_valid ? pend_prot  : req_prot;

  // req_sel のビット幅で NUM_SLAVES 以上の値を表せるときだけ比較する
  generate
    if( (1<<SEL_W)>NUM_SLAVES ) begin : g_sel_chk
      assign nxt_sel_ok = (32'(nxt_sel)<32'(NUM_SLAVES));
    end else begin : g_sel_nochk
      assign nxt_sel_ok = 1'b1;
    end
  endgenerate

  //---------------------------------------------------------------------------
  // FSM / APB 出力レジスタ / 保留レジスタ
  //---------------------------------------------------------------------------
  always @(posedge pclk or negedge presetn) begin
    if( !presetn ) begin
      state      <= ST_IDLE;
      psel_q     <= {NUM_SLAVES{1'b0}};
      penable_q  <= 1'b0;
      paddr_q    <= {ADDR_WIDTH{1'b0}};
      pwrite_q   <= 1'b0;
      pwdata_q   <= {DATA_WIDTH{1'b0}};
      pstrb_q    <= {STRB_W{1'b0}};
      pprot_q    <= 3'b000;
      sel_q      <= {SEL_W{1'b0}};
      nosel_q    <= 1'b0;
      pend_valid <= 1'b0;
      pend_write <= 1'b0;
      pend_sel   <= {SEL_W{1'b0}};
      pend_addr  <= {ADDR_WIDTH{1'b0}};
      pend_wdata <= {DATA_WIDTH{1'b0}};
      pend_strb  <= {STRB_W{1'b0}};
      pend_prot  <= 3'b000;
      err_hold   <= 1'b0;
    end else begin
      err_hold <= flush;
      if( start ) begin
        // 次の転送の SETUP へ (IDLE から、または ACCESS 完了から直接)
        state      <= ST_SETUP;
        penable_q  <= 1'b0;
        paddr_q    <= nxt_addr;
        pwrite_q   <= nxt_write;
        pwdata_q   <= nxt_wdata;
        pprot_q    <= nxt_prot;
        sel_q      <= nxt_sel;
        nosel_q    <= !nxt_sel_ok;
        pend_valid <= 1'b0;
        if( nxt_write ) begin
          pstrb_q <= nxt_strb;
        end else begin
          pstrb_q <= {STRB_W{1'b0}};
        end
        if( nxt_sel_ok ) begin
          psel_q <= NUM_SLAVES'(1) << nxt_sel;
        end else begin
          psel_q <= {NUM_SLAVES{1'b0}};
        end
      end else begin
        // 保留レジスタ
        if( flush ) begin
          pend_valid <= 1'b0;
        end else if( req_fire ) begin
          pend_valid <= 1'b1;
          pend_write <= req_write;
          pend_sel   <= req_sel;
          pend_addr  <= req_addr;
          pend_wdata <= req_wdata;
          pend_strb  <= req_strb;
          pend_prot  <= req_prot;
        end
        // 転送の進行
        case( state )
          ST_SETUP : begin
            penable_q <= !nosel_q;
            state     <= ST_ACCESS;
          end
          ST_ACCESS : begin
            if( xfer_done ) begin
              psel_q    <= {NUM_SLAVES{1'b0}};
              penable_q <= 1'b0;
              state     <= ST_IDLE;
            end
          end
          default : begin
            state <= ST_IDLE;
          end
        endcase
      end
    end
  end

  //---------------------------------------------------------------------------
  // 応答 (転送完了の次のサイクル)
  //---------------------------------------------------------------------------
  always @(posedge pclk or negedge presetn) begin
    if( !presetn ) begin
      rsp_valid   <= 1'b0;
      rsp_rdata   <= {DATA_WIDTH{1'b0}};
      rsp_slverr  <= 1'b0;
      rsp_timeout <= 1'b0;
    end else begin
      rsp_valid <= xfer_done;
      if( xfer_done ) begin
        rsp_slverr  <= !timeout_hit&&pslverr_sel;
        rsp_timeout <= timeout_hit;
        if( pwrite_q||timeout_hit ) begin
          rsp_rdata <= {DATA_WIDTH{1'b0}};
        end else begin
          rsp_rdata <= prdata_sel;
        end
      end
    end
  end

  //---------------------------------------------------------------------------
  // 出力
  //---------------------------------------------------------------------------
  assign busy    = (state!=ST_IDLE)||pend_valid;
  assign paddr   = paddr_q;
  assign pprot   = pprot_q;
  assign psel    = psel_q;
  assign penable = penable_q;
  assign pwrite  = pwrite_q;
  assign pwdata  = pwdata_q;
  assign pstrb   = pstrb_q;

  //---------------------------------------------------------------------------
  // パラメータチェック (エラボレーション時。IEEE 1800 20.11)
  //   対応していない合成ツールでは +define+APB_MASTER_NO_ELAB_CHECK で外す
  //---------------------------------------------------------------------------
`ifndef APB_MASTER_NO_ELAB_CHECK
  generate
    if( (DATA_WIDTH!=8)&&(DATA_WIDTH!=16)&&(DATA_WIDTH!=32) ) begin : g_chk_data
      $error("apb_master_engine : DATA_WIDTH must be 8, 16 or 32 (DATA_WIDTH=%0d)", DATA_WIDTH);
    end
    if( (ADDR_WIDTH<1)||(ADDR_WIDTH>32) ) begin : g_chk_addr
      $error("apb_master_engine : ADDR_WIDTH must be 1..32 (ADDR_WIDTH=%0d)", ADDR_WIDTH);
    end
    if( NUM_SLAVES<1 ) begin : g_chk_slaves
      $error("apb_master_engine : NUM_SLAVES must be >= 1 (NUM_SLAVES=%0d)", NUM_SLAVES);
    end
  endgenerate
`endif

endmodule
