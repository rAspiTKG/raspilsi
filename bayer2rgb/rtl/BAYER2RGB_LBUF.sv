// ============================================================================
// BAYER2RGB_LBUF : ラインバッファと3×(PPC+2)画素の窓(レイテンシ2)
//   SRAM0 : 2ライン前、SRAM1 : 1ライン前 を保持する(各 K_MAX ワード × PPC画素)
//   0段目: SRAM0/1 の列colを読む
//   1段目: 読んだ値と入力から窓の3行を作る。同時に書き戻す
//            SRAM1[col] ← 入力、SRAM0[col] ← SRAM1の読み出し値
//            (読み出しの次のクロックに書くので、同じアドレスを同時に読み書きしない)
//   2段目: 窓を出力する(出力列 oc = col-1、出力ライン y = line-1)
//   上下左右の端はミラー(reflect-101): x=-1 → x=1、x=W → x=W-2、y=-1 → y=1、y=H → y=H-2
// ============================================================================
module BAYER2RGB_LBUF
  import BAYER2RGB_PKG::*;
(
  input  logic              clk
 ,input  logic              rst_n
 ,input  logic              i_clr
 ,input  stp_t              i_stp
 ,output win_t              o_win
 // SRAM0(2ライン前)
 ,output logic              o_sram0_ren
 ,output logic [LB_AW-1:0]  o_sram0_raddr
 ,input  logic [BEAT_W-1:0] i_sram0_rdata
 ,output logic              o_sram0_wen
 ,output logic [LB_AW-1:0]  o_sram0_waddr
 ,output logic [BEAT_W-1:0] o_sram0_wdata
 // SRAM1(1ライン前)
 ,output logic              o_sram1_ren
 ,output logic [LB_AW-1:0]  o_sram1_raddr
 ,input  logic [BEAT_W-1:0] i_sram1_rdata
 ,output logic              o_sram1_wen
 ,output logic [LB_AW-1:0]  o_sram1_waddr
 ,output logic [BEAT_W-1:0] o_sram1_wdata
);

  typedef logic [PPC-1:0][IN_BITS-1:0] beat_t;

  logic                             r_s1_vld;
  /* verilator lint_off UNUSEDSIGNAL */
  stp_t                             r_s1;     // vld は r_s1_vld を使う
  /* verilator lint_on UNUSEDSIGNAL */
  logic [2:0][PPC-1:0][IN_BITS-1:0] r_b1;     // 列 col-1 のビート(3行)
  logic [2:0][IN_BITS-1:0]          r_b2;     // 列 col-2 のビートの最後の画素(3行)
  logic                             r_win_vld;
  win_t                             r_win;

  beat_t                            s_rd0;
  beat_t                            s_rd1;
  logic [2:0][PPC-1:0][IN_BITS-1:0] s_cur;    // 列 col のビート(3行)
  logic [2:0][PPC+1:0][IN_BITS-1:0] s_raw;    // ミラー前の窓
  logic [2:0][PPC+1:0][IN_BITS-1:0] s_win;
  logic                             s_out;    // 窓を出力するステップ
  logic                             s_shift;  // 履歴を進めるステップ
  logic [HEIGHT_W-1:0]              s_y;
  logic [COL_W-1:0]                 s_oc;

  // --------------------------------------------------------------------------
  // 0段目: 読み出し
  // --------------------------------------------------------------------------
  assign o_sram0_ren   = i_stp.vld&&!i_stp.fcol;
  assign o_sram0_raddr = LB_AW'(i_stp.col);
  assign o_sram1_ren   = i_stp.vld&&!i_stp.fcol;
  assign o_sram1_raddr = LB_AW'(i_stp.col);

  // --------------------------------------------------------------------------
  // 1段目: 書き戻しと窓の生成
  // --------------------------------------------------------------------------
  assign s_rd0 = beat_t'(i_sram0_rdata);
  assign s_rd1 = beat_t'(i_sram1_rdata);

  assign o_sram1_wen   = r_s1_vld&&!r_s1.fcol&&!r_s1.frow;
  assign o_sram1_waddr = LB_AW'(r_s1.col);
  assign o_sram1_wdata = r_s1.pix;
  assign o_sram0_wen   = r_s1_vld&&!r_s1.fcol&&!r_s1.frow;
  assign o_sram0_waddr = LB_AW'(r_s1.col);
  assign o_sram0_wdata = s_rd1;

  always_comb begin
    // 3行: 上 = ライン-2(ライン1では上端のミラーで入力)、中 = ライン-1、下 = 入力(掃き出しラインではミラー)
    if( r_s1.line==HEIGHT_W'(1) ) begin
      s_cur[0] = r_s1.pix;
    end else begin
      s_cur[0] = s_rd0;
    end
    s_cur[1] = s_rd1;
    if( r_s1.frow ) begin
      s_cur[2] = s_rd0;
    end else begin
      s_cur[2] = r_s1.pix;
    end
    // ミラー前の窓: [0]=列col-2の最後、[1..PPC]=列col-1、[PPC+1]=列colの最初
    for( int r=0; r<3; r++ ) begin
      s_raw[r][0] = r_b2[r];
      for( int j=0; j<PPC; j++ ) begin
        s_raw[r][j+1] = r_b1[r][j];
      end
      s_raw[r][PPC+1] = s_cur[r][0];
    end
    // 左右のミラー
    s_win = s_raw;
    for( int r=0; r<3; r++ ) begin
      if( r_s1.col==COL_W'(1) ) begin
        s_win[r][0] = s_raw[r][2];
      end
      if( r_s1.fcol ) begin
        s_win[r][PPC+1] = s_raw[r][PPC-1];
      end
    end
  end

  assign s_out   = r_s1_vld&&(r_s1.line!=HEIGHT_W'(0))&&(r_s1.col!=COL_W'(0));
  assign s_shift = r_s1_vld&&!r_s1.fcol;
  assign s_y     = r_s1.line-HEIGHT_W'(1);
  assign s_oc    = r_s1.col-COL_W'(1);

  // --------------------------------------------------------------------------
  // 制御(リセットあり)
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      r_s1_vld  <= 1'b0;
      r_win_vld <= 1'b0;
    end else begin
      r_s1_vld  <= i_stp.vld&&!i_clr;
      r_win_vld <= s_out&&!i_clr;
    end
  end

  // --------------------------------------------------------------------------
  // データ(リセットなし)
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if( i_stp.vld ) begin
      r_s1 <= i_stp;
    end
    if( s_shift ) begin
      for( int r=0; r<3; r++ ) begin
        r_b2[r] <= r_b1[r][PPC-1];
      end
      r_b1 <= s_cur;
    end
    if( s_out ) begin
      r_win.vld <= 1'b0;   // vld は r_win_vld を使う
      r_win.sof <= (r_s1.line==HEIGHT_W'(1))&&(r_s1.col==COL_W'(1));
      r_win.eol <= r_s1.fcol;
      r_win.eof <= r_s1.fcol&&r_s1.frow;
      r_win.y   <= s_y;
      r_win.oc  <= s_oc;
      r_win.win <= s_win;
    end
  end

  always_comb begin
    o_win     = r_win;
    o_win.vld = r_win_vld;
  end

endmodule
