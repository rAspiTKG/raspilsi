// ============================================================================
// BAYER2RGB_WR_DMA : RGB画像の書き込み
//   - COREの出力ビート(PPC画素 × 3バイト)を16バイトのビートに詰める
//     ラインの終わり(eol)で端数を1ビートにして出す(WSTRBで有効バイトを示す)
//   - ライン単位にバーストを作る
//     バースト長 = min(16, ラインの残りビート数, 4KB境界までのビート数)
//   - バースト分のデータが書き込みバッファにそろってからAWを出す
//     WはAWの受け付けを待たずに送る(AXI4の依存規則どおり)
//   - 同時発行は4バーストまで。全バーストの応答を受けたら frame_done
//   - ソフトリセット: 新しいAWを止め、発行済みのバーストのWを送り切り、応答を受ける
// ============================================================================
module BAYER2RGB_WR_DMA
  import BAYER2RGB_PKG::*;
(
  input  logic         clk
 ,input  logic         rst_n
 ,input  ctl_t         i_ctl     // フレームの設定 + start + sw_rst
 ,BAYER2RGB_VBD_IF.dst rgb       // COREの出力(obeat_t)
 ,BAYER2RGB_VBD_IF.src aw        // 書き込み要求(axreq_t)
 ,BAYER2RGB_VBD_IF.src w         // 書き込みデータ(wbeat_t)
 ,BAYER2RGB_VBD_IF.dst b         // 書き込み応答(BRESP)
 ,output wr_evt_t      o_evt
);

  // 最大公約数(詰め替えの単位を求める)
  function automatic int f_gcd( input int va, input int vb );
    int x;
    int y;
    int t;
    begin
      x = va;
      y = vb;
      while( y!=0 ) begin
        t = x%y;
        x = y;
        y = t;
      end
      f_gcd = x;
    end
  endfunction

  localparam int GU    = f_gcd(MEM_BYTES, RGB_BYTES); // 詰め替えの単位(バイト)
  localparam int MEMU  = MEM_BYTES/GU;                // 書き込み1ビートの単位数
  localparam int RGBU  = RGB_BYTES/GU;                // COREの1ビートの単位数
  localparam int ACCU  = MEMU-1+RGBU;                 // 詰め替えバッファの単位数
  localparam int ACC_W = ACCU*GU*8;
  localparam int CNT_W = $clog2(ACCU+1);
  localparam int AVL_W = $clog2(WR_BUF_DEPTH+3);
  localparam int OST_W = $clog2(WR_OST+1);
  localparam int WBD_W = MEM_BYTES+MEM_DW;            // 書き込みバッファの幅 {strb, data}

  // --------------------------------------------------------------------------
  // 内部レジスタ・信号
  // --------------------------------------------------------------------------
  logic                r_act;       // フレーム処理中(start から frame_done まで)
  logic                r_abort;     // ソフトリセットの後始末中
  logic [HEIGHT_W-1:0] r_h;
  logic [WR_BPL_W-1:0] r_bpl;       // 1ラインの書き込みビート数
  // 詰め替え
  logic [ACC_W-1:0]    r_acc;
  logic [CNT_W-1:0]    r_cnt;       // 詰め替えバッファの単位数
  logic                r_flush;     // ラインの終わりの端数を出している
  // バーストの生成
  logic                r_aw_go;     // AWを出し終えていない
  logic [HEIGHT_W-1:0] r_aw_line;
  logic [MEM_AW-1:0]   r_aw_la;
  logic [MEM_AW-1:0]   r_aw_addr;
  logic [WR_BPL_W-1:0] r_aw_rem;
  logic [AVL_W-1:0]    r_avail;     // 書き込みバッファ内でまだバーストに割り当てていないビート数
  logic [OST_W-1:0]    r_ost;       // 応答を受け終えていないバースト数
  logic                r_aw_vld;
  axreq_t              r_aw_data;
  // W
  logic [BLEN_W-1:0]   r_wcnt;      // バースト内のビート番号
  logic                r_wr_err;
  logic                r_done;

  /* verilator lint_off UNUSEDSIGNAL */
  obeat_t              s_ob;        // sof / eof は使わない
  /* verilator lint_on UNUSEDSIGNAL */
  logic                s_emit_full;
  logic                s_emit_part;
  logic                s_emit;
  logic                s_push;
  logic [CNT_W-1:0]    s_cnt_e;     // 送出後の単位数
  logic [ACC_W-1:0]    s_acc_e;     // 送出後の詰め替えバッファ
  logic [ACC_W-1:0]    s_acc_n;
  logic [CNT_W-1:0]    s_cnt_n;
  logic                s_take;
  logic [MEM_BYTES-1:0] s_strb;
  logic [MEM_DW-1:0]   s_wdata;
  logic                s_wbuf_wbusy;
  logic                s_wbuf_rvld;
  logic                s_wbuf_rbusy;
  logic [WBD_W-1:0]    s_wbuf_rdata;
  logic                s_wbuf_clr;
  logic [BLEN_W-1:0]   s_blen;
  logic                s_aw_free;
  logic                s_aw_done;
  logic                s_aw_issue;
  logic                s_line_end;
  logic [MEM_AW-1:0]   s_next_la;
  logic                s_lq_wbusy;
  logic                s_lq_rvld;
  logic [BLEN_W-1:0]   s_lq_len;
  logic                s_w_last;
  logic                s_w_take;
  logic                s_b_take;
  logic                s_kill;      // 今クロックはデータを捨てる(ソフトリセット)

  // --------------------------------------------------------------------------
  // 詰め替え(COREの出力 → 16バイトのビート)
  // --------------------------------------------------------------------------
  assign s_ob        = obeat_t'(rgb.data);
  assign s_kill      = r_abort||i_ctl.sw_rst;
  assign s_emit_full = (r_cnt>=CNT_W'(MEMU));
  assign s_emit_part = r_flush&&(r_cnt!=CNT_W'(0))&&(r_cnt<CNT_W'(MEMU));
  assign s_emit      = (s_emit_full||s_emit_part)&&!s_wbuf_wbusy;
  assign s_push      = s_emit&&!s_kill;

  always_comb begin
    if( s_emit&&s_emit_full ) begin
      s_cnt_e = r_cnt-CNT_W'(MEMU);
      s_acc_e = r_acc>>MEM_DW;
    end else if( s_emit ) begin
      s_cnt_e = '0;
      s_acc_e = '0;
    end else begin
      s_cnt_e = r_cnt;
      s_acc_e = r_acc;
    end
  end

  // 受け取れるのは端数を出していないときで、送出後に1ビート分未満しか残っていないとき
  assign rgb.busy = (!s_kill)&&(r_flush||(s_cnt_e>=CNT_W'(MEMU)));
  assign s_take   = rgb.vld&&!rgb.busy&&!s_kill;

  // 残っている u 単位の後ろに入力を詰める。u 単位より上の古い値は捨てる
  // (r_acc はリセットしないので、上位に古い値や不定値が残っていてもよい)
  always_comb begin
    s_acc_n = s_acc_e;
    s_cnt_n = s_cnt_e;
    if( s_take ) begin
      for( int u=0; u<MEMU; u++ ) begin
        if( s_cnt_e==CNT_W'(u) ) begin
          s_acc_n = (s_acc_e&((ACC_W'(1)<<(u*GU*8))-ACC_W'(1)))|(ACC_W'(s_ob.rgb)<<(u*GU*8));
        end
      end
      s_cnt_n = s_cnt_e+CNT_W'(RGBU);
    end
  end

  // 送出するビート(端数のときは有効バイトだけWSTRBを立て、残りのデータは0にする)
  always_comb begin
    for( int i=0; i<MEM_BYTES; i++ ) begin
      if( s_emit_full ) begin
        s_strb[i] = 1'b1;
      end else begin
        s_strb[i] = (i<(int'(r_cnt)*GU));
      end
      s_wdata[(8*i)+:8] = s_strb[i] ? r_acc[(8*i)+:8] : 8'h00;
    end
  end

  // --------------------------------------------------------------------------
  // 書き込みバッファ
  // --------------------------------------------------------------------------
  BAYER2RGB_SFIFO #(
    .DEPTH    (WR_BUF_DEPTH)
   ,.DW       (WBD_W)
   ,.USE_SRAM (1'b1)
  ) u_wbuf (
    .clk     (clk)
   ,.rst_n   (rst_n)
   ,.i_clr   (s_wbuf_clr)
   ,.i_wvld  (s_push)
   ,.o_wbusy (s_wbuf_wbusy)
   ,.i_wdata ({s_strb, s_wdata})
   ,.o_rvld  (s_wbuf_rvld)
   ,.i_rbusy (s_wbuf_rbusy)
   ,.o_rdata (s_wbuf_rdata)
   ,.o_cnt   ()
  );

  // ソフトリセット中、割り当て済みのバーストを送り切ったら残りを捨てる
  assign s_wbuf_clr = r_abort&&!s_lq_rvld;

  // --------------------------------------------------------------------------
  // バーストの生成(AW)
  // --------------------------------------------------------------------------
  assign s_blen     = f_blen(r_aw_addr[11:4], r_aw_rem);
  assign s_aw_free  = (!r_aw_vld)||(!aw.busy);
  assign s_aw_done  = r_aw_vld&&!aw.busy;
  assign s_aw_issue = r_aw_go&&(!s_kill)&&s_aw_free&&(r_avail>=AVL_W'(s_blen))&&(r_ost<OST_W'(WR_OST))&&(!s_lq_wbusy);
  assign s_line_end = (r_aw_rem==WR_BPL_W'(s_blen));
  assign s_next_la  = r_aw_la+MEM_AW'(i_ctl.cfg.dst_stride);

  assign aw.vld  = r_aw_vld;
  assign aw.data = r_aw_data;

  // バースト長のキュー(AWを出した順にWを送る)
  BAYER2RGB_SFIFO #(
    .DEPTH    (WR_OST)
   ,.DW       (BLEN_W)
   ,.USE_SRAM (1'b0)
  ) u_lenq (
    .clk     (clk)
   ,.rst_n   (rst_n)
   ,.i_clr   (1'b0)
   ,.i_wvld  (s_aw_issue)
   ,.o_wbusy (s_lq_wbusy)
   ,.i_wdata (s_blen)
   ,.o_rvld  (s_lq_rvld)
   ,.i_rbusy (!(s_w_take&&s_w_last))
   ,.o_rdata (s_lq_len)
   ,.o_cnt   ()
  );

  // --------------------------------------------------------------------------
  // W
  // --------------------------------------------------------------------------
  assign s_w_last     = (r_wcnt==(s_lq_len-BLEN_W'(1)));
  assign w.vld        = s_wbuf_rvld&&s_lq_rvld;
  assign w.data       = {s_w_last, s_wbuf_rdata};
  assign s_w_take     = w.vld&&!w.busy;
  assign s_wbuf_rbusy = !s_w_take;

  // --------------------------------------------------------------------------
  // B
  // --------------------------------------------------------------------------
  assign b.busy   = 1'b0;
  assign s_b_take = b.vld;

  // --------------------------------------------------------------------------
  // 制御(リセットあり)
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      r_act     <= 1'b0;
      r_abort   <= 1'b0;
      r_h       <= HEIGHT_W'(MAX_HEIGHT);
      r_bpl     <= WR_BPL_W'(WR_BPL_MAX);
      r_cnt     <= '0;
      r_flush   <= 1'b0;
      r_aw_go   <= 1'b0;
      r_aw_line <= '0;
      r_aw_la   <= '0;
      r_aw_addr <= '0;
      r_aw_rem  <= '0;
      r_avail   <= '0;
      r_ost     <= '0;
      r_aw_vld  <= 1'b0;
      r_wcnt    <= '0;
      r_wr_err  <= 1'b0;
      r_done    <= 1'b0;
    end else begin
      // ---- 詰め替え
      r_cnt   <= s_cnt_n;
      r_flush <= (r_flush||(s_take&&s_ob.eol))&&(s_cnt_n!=CNT_W'(0));
      // ---- AWの出力レジスタ
      if( s_aw_issue ) begin
        r_aw_vld <= 1'b1;
      end else if( s_aw_done ) begin
        r_aw_vld <= 1'b0;
      end
      // ---- バーストの生成
      if( s_aw_issue ) begin
        if( s_line_end ) begin
          if( r_aw_line==(r_h-HEIGHT_W'(1)) ) begin
            r_aw_go <= 1'b0;
          end
          r_aw_line <= r_aw_line+HEIGHT_W'(1);
          r_aw_la   <= s_next_la;
          r_aw_addr <= s_next_la;
          r_aw_rem  <= r_bpl;
        end else begin
          r_aw_addr <= r_aw_addr+{{(MEM_AW-BLEN_W-4){1'b0}}, s_blen, 4'h0};
          r_aw_rem  <= r_aw_rem-WR_BPL_W'(s_blen);
        end
      end
      r_avail <= r_avail+AVL_W'(s_push)-(s_aw_issue ? AVL_W'(s_blen) : AVL_W'(0));
      r_ost   <= r_ost+OST_W'(s_aw_issue)-OST_W'(s_b_take);
      // ---- W
      if( s_w_take ) begin
        if( s_w_last ) begin
          r_wcnt <= '0;
        end else begin
          r_wcnt <= r_wcnt+BLEN_W'(1);
        end
      end
      // ---- 応答とフレーム完了
      r_wr_err <= s_b_take&&(b.data!=AXI_RESP_OKAY)&&!r_abort;
      r_done   <= 1'b0;
      if( r_act&&!r_aw_go&&(r_ost==OST_W'(0))&&!r_done ) begin
        r_act  <= 1'b0;
        r_done <= 1'b1;
      end
      // ---- フレーム開始
      if( i_ctl.start&&!r_act&&!r_abort ) begin
        r_act     <= 1'b1;
        r_h       <= f_height(i_ctl.cfg.height);
        r_bpl     <= f_wr_bpl(i_ctl.cfg.width);
        r_aw_go   <= 1'b1;
        r_aw_line <= '0;
        r_aw_la   <= i_ctl.cfg.dst_addr;
        r_aw_addr <= i_ctl.cfg.dst_addr;
        r_aw_rem  <= f_wr_bpl(i_ctl.cfg.width);
      end
      // ---- ソフトリセット
      if( i_ctl.sw_rst ) begin
        r_act   <= 1'b0;
        r_abort <= 1'b1;
        r_aw_go <= 1'b0;
        r_cnt   <= '0;
        r_flush <= 1'b0;
        r_avail <= '0;
        r_done  <= 1'b0;
      end else if( r_abort&&(r_ost==OST_W'(0))&&!s_lq_rvld ) begin
        r_abort <= 1'b0;
      end
    end
  end

  // データ(リセットなし)
  always_ff @(posedge clk) begin
    r_acc <= s_acc_n;
    if( s_aw_issue ) begin
      r_aw_data.qos   <= i_ctl.cfg.awqos;
      r_aw_data.prot  <= i_ctl.cfg.awprot;
      r_aw_data.cache <= i_ctl.cfg.awcache;
      r_aw_data.len   <= 8'(s_blen-BLEN_W'(1));
      r_aw_data.addr  <= r_aw_addr;
    end
  end

  assign o_evt.busy       = r_act||r_abort;
  assign o_evt.frame_done = r_done;
  assign o_evt.wr_err     = r_wr_err;

endmodule
