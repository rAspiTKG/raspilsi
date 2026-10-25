// ============================================================================
// BAYER2RGB_CDC : 制御系(ctrl_clk) ⇔ 映像系(clk) のクロック乗せ換え
//
//  [要求: 制御系 → 映像系]  トグル + 2段同期 + ACK のハンドシェイク(MCP)
//    - STARTとSW_RESETを1つずつ送る(o_busy=1 の間は次を受けない)
//    - START: REG_UPDATE=1 なら設定を r_pl_cfg に取り込んでから送る
//             映像系は受けたクロックで設定を r_cfg_v に移し、同時に start を出す
//    - SW_RESET: 映像系で sw_rst を1クロック出し、DMAが止まったら srst_done を返す
//    - r_pl_cfg は要求中に変化しないので、映像系はトグル検出後に直接取り込んでよい
//
//  [イベント: 映像系 → 制御系]  同じ方式のハンドシェイク
//    - frame_done / rd_err / wr_err / srst_done を保留ビットに貯め、まとめて送る
//    - 1本のハンドシェイクなので、発生した順番が入れ替わることはない
//
//  タイミング制約: r_pl_cfg → r_cfg_v、r_ev_pl_v → r_evt_c はMCP(set_max_delay等)、
//                  トグル信号は同期化セルの1段目へのフォールスパスとする。
// ============================================================================
module BAYER2RGB_CDC
  import BAYER2RGB_PKG::*;
(
  // 制御系
  input  logic    ctrl_clk
 ,input  logic    ctrl_rst_n
 ,input  cfg_t    i_cfg        // REGの現在の設定
 ,input  logic    i_start      // フレーム開始の要求(パルス)
 ,input  logic    i_sw_rst     // ソフトリセットの要求(パルス)
 ,output logic    o_busy       // 要求の受け渡し中
 ,output evt_t    o_evt        // 映像系からのイベント(パルス)
 // 映像系
 ,input  logic    clk
 ,input  logic    rst_n
 ,output ctl_t    o_ctl        // フレームの設定 + start + sw_rst
 ,input  rd_evt_t i_rd_evt
 ,input  wr_evt_t i_wr_evt
);

  // 要求: 制御系
  cfg_t r_pl_cfg;      // 送る設定(STARTのときだけ更新)
  logic r_pl_start;    // 送る要求の種類
  logic r_pl_srst;
  logic r_req_c;       // 要求トグル
  logic r_busy_c;
  logic s_ack_c;       // 映像系からのACK(同期化後)
  // 要求: 映像系
  logic r_req_d_v;     // 受け取った要求トグル(ACKとして返す)
  logic s_req_v;       // 要求トグル(同期化後)
  logic s_req_edge;
  cfg_t r_cfg_v;       // フレームの設定
  logic r_start_v;
  logic r_srst_v;
  logic r_abort_v;     // ソフトリセットの後始末中
  logic s_dma_busy;
  // イベント: 映像系
  evt_t r_ev_pend_v;   // 送信待ちのイベント
  evt_t r_ev_pl_v;     // 送信中のイベント
  logic r_ev_req_v;
  logic r_ev_busy_v;
  logic s_ev_ack_v;
  evt_t s_ev_new;
  evt_t s_ev_all;
  // イベント: 制御系
  logic r_ev_req_d_c;
  logic s_ev_req_c;
  evt_t r_evt_c;

  // ==========================================================================
  // 要求: 制御系
  // ==========================================================================
  BAYER2RGB_SYNC2 u_sync_ack (
    .clk   (ctrl_clk)
   ,.rst_n (ctrl_rst_n)
   ,.i_d   (r_req_d_v)
   ,.o_q   (s_ack_c)
  );

  always_ff @(posedge ctrl_clk or negedge ctrl_rst_n) begin
    if( !ctrl_rst_n ) begin
      r_pl_cfg   <= f_cfg_default();
      r_pl_start <= 1'b0;
      r_pl_srst  <= 1'b0;
      r_req_c    <= 1'b0;
      r_busy_c   <= 1'b0;
    end else begin
      if( i_sw_rst&&!r_busy_c ) begin
        r_pl_start <= 1'b0;
        r_pl_srst  <= 1'b1;
        r_req_c    <= ~r_req_c;
        r_busy_c   <= 1'b1;
      end else if( i_start&&!r_busy_c ) begin
        if( i_cfg.reg_update ) begin
          r_pl_cfg <= i_cfg;
        end
        r_pl_start <= 1'b1;
        r_pl_srst  <= 1'b0;
        r_req_c    <= ~r_req_c;
        r_busy_c   <= 1'b1;
      end else if( r_busy_c&&(s_ack_c==r_req_c) ) begin
        r_busy_c <= 1'b0;
      end
    end
  end

  assign o_busy = r_busy_c;

  // ==========================================================================
  // 要求: 映像系
  // ==========================================================================
  BAYER2RGB_SYNC2 u_sync_req (
    .clk   (clk)
   ,.rst_n (rst_n)
   ,.i_d   (r_req_c)
   ,.o_q   (s_req_v)
  );

  assign s_req_edge = s_req_v^r_req_d_v;
  assign s_dma_busy = i_rd_evt.busy||i_wr_evt.busy;

  always_ff @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      r_req_d_v <= 1'b0;
      r_cfg_v   <= f_cfg_default();
      r_start_v <= 1'b0;
      r_srst_v  <= 1'b0;
      r_abort_v <= 1'b0;
    end else begin
      r_req_d_v <= s_req_v;
      r_start_v <= 1'b0;
      r_srst_v  <= 1'b0;
      if( s_req_edge&&r_pl_srst ) begin
        r_srst_v  <= 1'b1;
        r_abort_v <= 1'b1;
      end else if( s_req_edge&&r_pl_start&&!r_abort_v&&!s_dma_busy ) begin
        r_cfg_v   <= r_pl_cfg;
        r_start_v <= 1'b1;
      end else if( r_abort_v&&!r_srst_v&&!s_dma_busy ) begin
        r_abort_v <= 1'b0;
      end
    end
  end

  assign o_ctl.cfg    = r_cfg_v;
  assign o_ctl.start  = r_start_v;
  assign o_ctl.sw_rst = r_srst_v;

  // ==========================================================================
  // イベント: 映像系
  // ==========================================================================
  BAYER2RGB_SYNC2 u_sync_ev_ack (
    .clk   (clk)
   ,.rst_n (rst_n)
   ,.i_d   (r_ev_req_d_c)
   ,.o_q   (s_ev_ack_v)
  );

  always_comb begin
    s_ev_new.frame_done = i_wr_evt.frame_done;
    s_ev_new.rd_err     = i_rd_evt.rd_err;
    s_ev_new.wr_err     = i_wr_evt.wr_err;
    s_ev_new.srst_done  = r_abort_v&&!r_srst_v&&!s_dma_busy;
  end

  assign s_ev_all = r_ev_pend_v|s_ev_new;

  always_ff @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      r_ev_pend_v <= '0;
      r_ev_pl_v   <= '0;
      r_ev_req_v  <= 1'b0;
      r_ev_busy_v <= 1'b0;
    end else begin
      if( !r_ev_busy_v&&(r_ev_pend_v!=evt_t'(0)) ) begin
        r_ev_pl_v   <= r_ev_pend_v;
        r_ev_pend_v <= s_ev_new;
        r_ev_req_v  <= ~r_ev_req_v;
        r_ev_busy_v <= 1'b1;
      end else begin
        r_ev_pend_v <= s_ev_all;
        if( r_ev_busy_v&&(s_ev_ack_v==r_ev_req_v) ) begin
          r_ev_busy_v <= 1'b0;
        end
      end
    end
  end

  // ==========================================================================
  // イベント: 制御系
  // ==========================================================================
  BAYER2RGB_SYNC2 u_sync_ev_req (
    .clk   (ctrl_clk)
   ,.rst_n (ctrl_rst_n)
   ,.i_d   (r_ev_req_v)
   ,.o_q   (s_ev_req_c)
  );

  always_ff @(posedge ctrl_clk or negedge ctrl_rst_n) begin
    if( !ctrl_rst_n ) begin
      r_ev_req_d_c <= 1'b0;
      r_evt_c      <= '0;
    end else begin
      r_ev_req_d_c <= s_ev_req_c;
      if( s_ev_req_c^r_ev_req_d_c ) begin
        r_evt_c <= r_ev_pl_v;
      end else begin
        r_evt_c <= '0;
      end
    end
  end

  assign o_evt = r_evt_c;

  // ==========================================================================
  // 使い方の誤りの検出(シミュレーション用)
  // ==========================================================================
`ifndef SYNTHESIS
  always @(posedge ctrl_clk) begin
    if( ctrl_rst_n&&r_busy_c&&(i_start||i_sw_rst) ) begin
      $error("%m: 要求の受け渡し中に次の要求を受けた");
    end
  end
  always @(posedge clk) begin
    if( rst_n&&s_req_edge&&r_pl_start&&(r_abort_v||s_dma_busy) ) begin
      $error("%m: 映像系の動作中にSTARTを受けた");
    end
  end
`endif

endmodule
