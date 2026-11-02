// ============================================================================
// BAYER2RGB_CORE : 画像処理のコア
//   IN_CTRL → BLC → WB → LBUF(+SRAM×2) → DMSC → FCS → GAMMA → OUT_FMT → OUT_FIFO
//   IN_CTRL より後ろは固定レイテンシ(PIPE_LAT=14)で止まらずに流れる。
//   出力側の詰まりは OUT_FIFO とクレジット制御で吸収する。
// ============================================================================
module BAYER2RGB_CORE
  import BAYER2RGB_PKG::*;
(
  input  logic         clk
 ,input  logic         rst_n
 ,input  ctl_t         i_ctl     // フレームの設定 + start + sw_rst
 ,BAYER2RGB_VBD_IF.dst pix       // 入力画素(PPC画素 × 14bit)
 ,BAYER2RGB_VBD_IF.src rgb       // 出力(obeat_t)
);

  cfg_t                s_cfg;
  logic                s_clr;
  logic [OFIFO_CW-1:0] s_fifo_cnt;
  stp_t                s_stp0;
  stp_t                s_stp1;
  stp_t                s_stp2;
  win_t                s_win;
  dm_t                 s_dm;
  fc_t                 s_fc;
  gm_t                 s_gm;
  logic                s_of_vld;
  obeat_t              s_of_data;
  // ラインバッファのSRAM
  logic                s_sram0_ren;
  logic [LB_AW-1:0]    s_sram0_raddr;
  logic [BEAT_W-1:0]   s_sram0_rdata;
  logic                s_sram0_wen;
  logic [LB_AW-1:0]    s_sram0_waddr;
  logic [BEAT_W-1:0]   s_sram0_wdata;
  logic                s_sram1_ren;
  logic [LB_AW-1:0]    s_sram1_raddr;
  logic [BEAT_W-1:0]   s_sram1_rdata;
  logic                s_sram1_wen;
  logic [LB_AW-1:0]    s_sram1_waddr;
  logic [BEAT_W-1:0]   s_sram1_wdata;

  BAYER2RGB_IN_CTRL u_in_ctrl (
    .clk        (clk)
   ,.rst_n      (rst_n)
   ,.i_ctl      (i_ctl)
   ,.pix        (pix)
   ,.i_fifo_cnt (s_fifo_cnt)
   ,.o_cfg      (s_cfg)
   ,.o_clr      (s_clr)
   ,.o_stp      (s_stp0)
  );

  BAYER2RGB_BLC u_blc (
    .clk   (clk)
   ,.rst_n (rst_n)
   ,.i_clr (s_clr)
   ,.i_cfg (s_cfg)
   ,.i_stp (s_stp0)
   ,.o_stp (s_stp1)
  );

  BAYER2RGB_WB u_wb (
    .clk   (clk)
   ,.rst_n (rst_n)
   ,.i_clr (s_clr)
   ,.i_cfg (s_cfg)
   ,.i_stp (s_stp1)
   ,.o_stp (s_stp2)
  );

  BAYER2RGB_LBUF u_lbuf (
    .clk           (clk)
   ,.rst_n         (rst_n)
   ,.i_clr         (s_clr)
   ,.i_stp         (s_stp2)
   ,.o_win         (s_win)
   ,.o_sram0_ren   (s_sram0_ren)
   ,.o_sram0_raddr (s_sram0_raddr)
   ,.i_sram0_rdata (s_sram0_rdata)
   ,.o_sram0_wen   (s_sram0_wen)
   ,.o_sram0_waddr (s_sram0_waddr)
   ,.o_sram0_wdata (s_sram0_wdata)
   ,.o_sram1_ren   (s_sram1_ren)
   ,.o_sram1_raddr (s_sram1_raddr)
   ,.i_sram1_rdata (s_sram1_rdata)
   ,.o_sram1_wen   (s_sram1_wen)
   ,.o_sram1_waddr (s_sram1_waddr)
   ,.o_sram1_wdata (s_sram1_wdata)
  );

  BAYER2RGB_SRAM_1R1W #(
    .DEPTH (K_MAX)
   ,.DW    (BEAT_W)
   ,.AW    (LB_AW)
  ) u_sram0 (
    .clk     (clk)
   ,.i_ren   (s_sram0_ren)
   ,.i_raddr (s_sram0_raddr)
   ,.o_rdata (s_sram0_rdata)
   ,.i_wen   (s_sram0_wen)
   ,.i_waddr (s_sram0_waddr)
   ,.i_wdata (s_sram0_wdata)
  );

  BAYER2RGB_SRAM_1R1W #(
    .DEPTH (K_MAX)
   ,.DW    (BEAT_W)
   ,.AW    (LB_AW)
  ) u_sram1 (
    .clk     (clk)
   ,.i_ren   (s_sram1_ren)
   ,.i_raddr (s_sram1_raddr)
   ,.o_rdata (s_sram1_rdata)
   ,.i_wen   (s_sram1_wen)
   ,.i_waddr (s_sram1_waddr)
   ,.i_wdata (s_sram1_wdata)
  );

  BAYER2RGB_DMSC u_dmsc (
    .clk   (clk)
   ,.rst_n (rst_n)
   ,.i_clr (s_clr)
   ,.i_cfg (s_cfg)
   ,.i_win (s_win)
   ,.o_dm  (s_dm)
  );

  BAYER2RGB_FCS u_fcs (
    .clk   (clk)
   ,.rst_n (rst_n)
   ,.i_clr (s_clr)
   ,.i_cfg (s_cfg)
   ,.i_dm  (s_dm)
   ,.o_fc  (s_fc)
  );

  BAYER2RGB_GAMMA u_gamma (
    .clk   (clk)
   ,.rst_n (rst_n)
   ,.i_clr (s_clr)
   ,.i_cfg (s_cfg)
   ,.i_fc  (s_fc)
   ,.o_gm  (s_gm)
  );

  BAYER2RGB_OUT_FMT u_out_fmt (
    .clk    (clk)
   ,.rst_n  (rst_n)
   ,.i_clr  (s_clr)
   ,.i_cfg  (s_cfg)
   ,.i_gm   (s_gm)
   ,.o_vld  (s_of_vld)
   ,.o_data (s_of_data)
  );

  BAYER2RGB_OUT_FIFO u_out_fifo (
    .clk    (clk)
   ,.rst_n  (rst_n)
   ,.i_clr  (s_clr)
   ,.i_vld  (s_of_vld)
   ,.i_data (s_of_data)
   ,.o_cnt  (s_fifo_cnt)
   ,.rgb    (rgb)
  );

endmodule
