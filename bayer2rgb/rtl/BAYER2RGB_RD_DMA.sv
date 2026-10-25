// ============================================================================
// BAYER2RGB_RD_DMA : Bayer画像の読み出し
//   - ライン単位にバースト読み出しを出す
//     バースト長 = min(16, ラインの残りビート数, 4KB境界までのビート数)
//   - 読み出しバッファ(64ビート)の空きを予約してから要求を出す(Rを止めない)
//   - 同時発行は4バーストまで
//   - 1ビート(16バイト = 8画素)の各16bitの下位14bitを画素としてCOREへ送る
//   - テストパターン時はメモリを読まず、値0のビートを同じ数だけ送る
//   - ソフトリセット: 新しい要求を止め、発行済みのバーストの応答を受けて捨てる
// ============================================================================
module BAYER2RGB_RD_DMA
  import BAYER2RGB_PKG::*;
(
  input  logic         clk
 ,input  logic         rst_n
 ,input  ctl_t         i_ctl     // フレームの設定 + start + sw_rst
 ,BAYER2RGB_VBD_IF.src ar        // 読み出し要求(axreq_t)
 ,BAYER2RGB_VBD_IF.dst r         // 読み出しデータ(rbeat_t)
 ,BAYER2RGB_VBD_IF.src pix       // COREへの画素(PPC画素 × 14bit)
 ,output rd_evt_t      o_evt
);

  localparam int CRD_W = $clog2(RD_BUF_DEPTH+1);
  localparam int OST_W = $clog2(RD_OST+1);
  localparam int SUB_W = (SUB_BEATS>1) ? $clog2(SUB_BEATS) : 1;

  // --------------------------------------------------------------------------
  // 内部レジスタ・信号
  // --------------------------------------------------------------------------
  logic                r_act;       // フレーム処理中(start から最後のビートを送るまで)
  logic                r_abort;     // ソフトリセットの後始末中
  logic                r_tpg;       // テストパターン(メモリを読まない)
  logic [HEIGHT_W-1:0] r_h;         // 高さ
  logic [RD_BPL_W-1:0] r_bpl;       // 1ラインのビート数
  // 要求の生成
  logic                r_ar_go;     // 要求を出し終えていない
  logic [HEIGHT_W-1:0] r_ar_line;
  logic [MEM_AW-1:0]   r_ar_la;     // ラインの先頭アドレス
  logic [MEM_AW-1:0]   r_ar_addr;   // 次のバーストのアドレス
  logic [RD_BPL_W-1:0] r_ar_rem;    // ラインの残りビート数
  logic [CRD_W-1:0]    r_credit;    // 読み出しバッファの空き(予約していない数)
  logic [OST_W-1:0]    r_ost;       // 応答を受け終えていないバースト数
  logic                r_ar_vld;
  axreq_t              r_ar_data;
  // 画素の送出
  logic [SUB_W-1:0]    r_sub;       // ビート内の位置(PPC<8 のとき)
  logic [RD_BPL_W-1:0] r_up_beat;
  logic [HEIGHT_W-1:0] r_up_line;
  logic                r_rd_err;

  logic [BLEN_W-1:0]   s_blen;
  logic                s_ar_free;
  logic                s_ar_issue;
  logic                s_ar_done;   // 出力レジスタの要求が受け取られた
  logic                s_line_end;  // ラインの最後のバースト
  logic [MEM_AW-1:0]   s_next_la;
  rbeat_t              s_rbeat;
  logic                s_r_take;
  logic                s_r_last;
  logic                s_fifo_wbusy;
  logic                s_fifo_rvld;
  logic                s_fifo_rbusy;
  logic [MEM_DW-1:0]   s_fifo_rdata;
  logic                s_pix_take;
  logic                s_sub_last;
  logic                s_beat_take; // メモリ1ビート分を送り終えた
  logic                s_frame_end;
  logic [PPC-1:0][IN_BITS-1:0] s_pix;

  // --------------------------------------------------------------------------
  // 読み出し要求
  // --------------------------------------------------------------------------
  assign s_blen     = f_blen(r_ar_addr[11:4], WR_BPL_W'(r_ar_rem));
  assign s_ar_free  = (!r_ar_vld)||(!ar.busy);
  assign s_ar_done  = r_ar_vld&&!ar.busy;
  assign s_ar_issue = r_ar_go&&(!r_abort)&&(!i_ctl.sw_rst)&&s_ar_free&&(r_credit>=CRD_W'(s_blen))&&(r_ost<OST_W'(RD_OST));
  assign s_line_end = (r_ar_rem==RD_BPL_W'(s_blen));
  assign s_next_la  = r_ar_la+MEM_AW'(i_ctl.cfg.src_stride);

  assign ar.vld  = r_ar_vld;
  assign ar.data = r_ar_data;

  // --------------------------------------------------------------------------
  // 読み出しデータ → 読み出しバッファ
  // --------------------------------------------------------------------------
  assign s_rbeat  = rbeat_t'(r.data);
  assign r.busy   = (!r_abort)&&s_fifo_wbusy;
  assign s_r_take = r.vld&&!r.busy;
  assign s_r_last = s_r_take&&s_rbeat.last;

  BAYER2RGB_SFIFO #(
    .DEPTH    (RD_BUF_DEPTH)
   ,.DW       (MEM_DW)
   ,.USE_SRAM (1'b1)
  ) u_rbuf (
    .clk     (clk)
   ,.rst_n   (rst_n)
   ,.i_clr   (i_ctl.sw_rst)
   ,.i_wvld  (s_r_take&&!r_abort)
   ,.o_wbusy (s_fifo_wbusy)
   ,.i_wdata (s_rbeat.data)
   ,.o_rvld  (s_fifo_rvld)
   ,.i_rbusy (s_fifo_rbusy)
   ,.o_rdata (s_fifo_rdata)
   ,.o_cnt   ()
  );

  // --------------------------------------------------------------------------
  // 画素の送出(COREへ)
  // --------------------------------------------------------------------------
  always_comb begin
    for( int i=0; i<PPC; i++ ) begin
      s_pix[i] = s_fifo_rdata[(16*((int'(r_sub)*PPC)+i))+:IN_BITS];
    end
  end

  assign s_sub_last   = (r_sub==SUB_W'(SUB_BEATS-1));
  assign pix.vld      = r_act&&(r_tpg||s_fifo_rvld);
  assign pix.data     = r_tpg ? '0 : s_pix;
  assign s_pix_take   = pix.vld&&!pix.busy;
  assign s_beat_take  = s_pix_take&&s_sub_last;
  assign s_fifo_rbusy = !(s_beat_take&&!r_tpg);
  assign s_frame_end  = s_beat_take&&(r_up_beat==(r_bpl-RD_BPL_W'(1)))&&(r_up_line==(r_h-HEIGHT_W'(1)));

  // --------------------------------------------------------------------------
  // 制御(リセットあり)
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      r_act     <= 1'b0;
      r_abort   <= 1'b0;
      r_tpg     <= 1'b0;
      r_h       <= HEIGHT_W'(MAX_HEIGHT);
      r_bpl     <= RD_BPL_W'(RD_BPL_MAX);
      r_ar_go   <= 1'b0;
      r_ar_line <= '0;
      r_ar_la   <= '0;
      r_ar_addr <= '0;
      r_ar_rem  <= '0;
      r_credit  <= CRD_W'(RD_BUF_DEPTH);
      r_ost     <= '0;
      r_ar_vld  <= 1'b0;
      r_sub     <= '0;
      r_up_beat <= '0;
      r_up_line <= '0;
      r_rd_err  <= 1'b0;
    end else begin
      // ---- 要求の出力レジスタ
      if( s_ar_issue ) begin
        r_ar_vld <= 1'b1;
      end else if( s_ar_done ) begin
        r_ar_vld <= 1'b0;
      end
      // ---- 要求の生成
      if( s_ar_issue ) begin
        if( s_line_end ) begin
          if( r_ar_line==(r_h-HEIGHT_W'(1)) ) begin
            r_ar_go <= 1'b0;
          end
          r_ar_line <= r_ar_line+HEIGHT_W'(1);
          r_ar_la   <= s_next_la;
          r_ar_addr <= s_next_la;
          r_ar_rem  <= r_bpl;
        end else begin
          r_ar_addr <= r_ar_addr+{{(MEM_AW-BLEN_W-4){1'b0}}, s_blen, 4'h0};
          r_ar_rem  <= r_ar_rem-RD_BPL_W'(s_blen);
        end
      end
      // ---- 空きと発行数
      r_credit <= r_credit-(s_ar_issue ? CRD_W'(s_blen) : CRD_W'(0))+((s_beat_take&&!r_tpg) ? CRD_W'(1) : CRD_W'(0));
      r_ost    <= r_ost+OST_W'(s_ar_issue)-OST_W'(s_r_last);
      // ---- 画素の送出
      if( s_pix_take ) begin
        if( s_sub_last ) begin
          r_sub <= '0;
        end else begin
          r_sub <= r_sub+SUB_W'(1);
        end
      end
      if( s_beat_take ) begin
        if( r_up_beat==(r_bpl-RD_BPL_W'(1)) ) begin
          r_up_beat <= '0;
          r_up_line <= r_up_line+HEIGHT_W'(1);
        end else begin
          r_up_beat <= r_up_beat+RD_BPL_W'(1);
        end
      end
      if( s_frame_end ) begin
        r_act <= 1'b0;
      end
      // ---- エラー(後始末中は報告しない)
      r_rd_err <= s_r_take&&(s_rbeat.resp!=AXI_RESP_OKAY)&&!r_abort;
      // ---- フレーム開始
      if( i_ctl.start&&!r_act&&!r_abort ) begin
        r_act     <= 1'b1;
        r_tpg     <= i_ctl.cfg.tpg_en;
        r_h       <= f_height(i_ctl.cfg.height);
        r_bpl     <= f_rd_bpl(i_ctl.cfg.width);
        r_ar_go   <= !i_ctl.cfg.tpg_en;
        r_ar_line <= '0;
        r_ar_la   <= i_ctl.cfg.src_addr;
        r_ar_addr <= i_ctl.cfg.src_addr;
        r_ar_rem  <= f_rd_bpl(i_ctl.cfg.width);
        r_sub     <= '0;
        r_up_beat <= '0;
        r_up_line <= '0;
      end
      // ---- ソフトリセット
      if( i_ctl.sw_rst ) begin
        r_act    <= 1'b0;
        r_abort  <= 1'b1;
        r_ar_go  <= 1'b0;
        r_credit <= CRD_W'(RD_BUF_DEPTH);
        r_sub    <= '0;
      end else if( r_abort&&(r_ost==OST_W'(0)) ) begin
        r_abort <= 1'b0;
      end
    end
  end

  // データ(リセットなし)
  always_ff @(posedge clk) begin
    if( s_ar_issue ) begin
      r_ar_data.qos   <= i_ctl.cfg.arqos;
      r_ar_data.prot  <= i_ctl.cfg.arprot;
      r_ar_data.cache <= i_ctl.cfg.arcache;
      r_ar_data.len   <= 8'(s_blen-BLEN_W'(1));
      r_ar_data.addr  <= r_ar_addr;
    end
  end

  assign o_evt.busy   = r_act||r_abort;
  assign o_evt.rd_err = r_rd_err;

endmodule
