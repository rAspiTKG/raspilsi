#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BAYER2RGB のブロック図を作る
  <out>/bayer2rgb_arch.drawio : draw.io ファイル(1ページ目: トップ、2ページ目: CORE)
  <out>/bayer2rgb_top.svg     : 1ページ目のSVG(draw.ioのデータを埋め込み)
  <out>/bayer2rgb_core.svg    : 2ページ目のSVG(draw.ioのデータを埋め込み)
使い方: python3 doc/tools/gen_arch.py <出力ディレクトリ>
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from archdiag import BLACK, BLUE, GRAY, GREEN, THICK, Diagram, write_drawio  # noqa: E402

LBL = 9.0   # 線のラベルの文字サイズ


def vbd( d, lb, rb, y0, name, dw, flow, lp, rp, dcolor=BLUE ):
  """左右に並んだ箱の間の vld/busy/data(BAYER2RGB_VBD_IF)
  flow '>': 左の箱が送り側、'<': 右の箱が送り側。lp/rp: 左右の箱のポート名(インタフェース名)"""
  ys = (y0, y0+20, y0+40)
  if( flow==">" ):
    d.wire([(lb.r, ys[0]), (rb.x, ys[0])], BLACK)
    d.wire([(rb.x, ys[1]), (lb.r, ys[1])], BLACK)
    d.wire([(lb.r, ys[2]), (rb.x, ys[2])], dcolor)
  else:
    d.wire([(rb.x, ys[0]), (lb.r, ys[0])], BLACK)
    d.wire([(lb.r, ys[1]), (rb.x, ys[1])], BLACK)
    d.wire([(rb.x, ys[2]), (lb.r, ys[2])], dcolor)
  d.text(lb.r+8, ys[0]-7, "%s.vld" % name, LBL)
  d.text(lb.r+8, ys[1]-7, "%s.busy" % name, LBL)
  d.text(lb.r+8, ys[2]-7, "%s.data%s" % (name, dw), LBL, color=dcolor)
  for i, sig in enumerate(("vld", "busy", "data")):
    col = dcolor if( i==2 ) else BLACK
    d.port(lb, "R", ys[i], "%s.%s" % (lp, sig), color=col)
    d.port(rb, "L", ys[i], "%s.%s" % (rp, sig), color=col)


def legend( d, x, y, notes ):
  items = [(GREEN, 1.2, "クロック"), (BLUE, 1.2, "データパス(画像データ)"), (BLACK, 1.2, "リセット・制御"),
           (BLACK, THICK, "AXIバス(1本にまとめて表記)")]
  cx = x
  d.text(cx, y, "凡例:", 10, bold=True)
  cx += 50
  for col, w, s in items:
    d.wire([(cx, y), (cx+40, y)], col, w, arrow="end")
    d.text(cx+48, y, s, 10)
    cx += 60+int(len(s)*10.5)+20
  d.dot(cx+4, y, BLACK)
  d.text(cx+14, y, "分岐(接続点)。点のない交差は接続していない", 10)
  for i, s in enumerate(notes):
    d.text(x, y+(26*(i+1)), s, 10)


# ============================================================================
# 1ページ目: トップ階層
# ============================================================================
def build_top():
  d = Diagram("top", "BAYER2RGB (トップ階層)", 2980, 1180)
  X0, Y0, X1, Y1 = 330, 70, 2620, 930
  d.box(X0, Y0, X1-X0, Y1-Y0, "BAYER2RGB (トップ階層)", size=14, sw=2.0)
  d.text(X0+12, 140, "制御系 (ctrl_clk ドメイン)", 11, color=GRAY)
  d.text(X0+12, 535, "映像系 (clk ドメイン)", 11, color=GRAY)

  # ---- 箱
  ax = d.box(400, 160, 330, 190, "BAYER2RGB_AXIL_BRIDGE (u_axil_bridge)")
  rg = d.box(870, 160, 250, 190, "BAYER2RGB_REG (u_reg)")
  cd = d.box(1270, 160, 410, 190, "BAYER2RGB_CDC (u_cdc)")
  rb = d.box(400, 560, 330, 260, "BAYER2RGB_AXIM_RD_BRIDGE (u_axim_rd_bridge)")
  rd = d.box(880, 560, 260, 260, "BAYER2RGB_RD_DMA (u_rd_dma)")
  co = d.box(1290, 560, 330, 260, "BAYER2RGB_CORE (u_core)")
  wd = d.box(1770, 560, 260, 260, "BAYER2RGB_WR_DMA (u_wr_dma)")
  wb = d.box(2180, 560, 340, 260, "BAYER2RGB_AXIM_WR_BRIDGE (u_axim_wr_bridge)")

  # ---- AXI4-Lite スレーブ
  y = 200
  d.wire([(X0, y), (ax.x, y)], BLACK, THICK, arrow="both")
  d.text(X0-10, y-9, "AXI4-Lite スレーブ (ctrl_clk)", 11, "end", bold=True)
  d.text(X0-10, y+9, "BAYER2RGB_REG_AW* / W* / B* / AR* / R*", 10, "end")
  d.text(X0-10, y+25, "AWADDR[11:0] WDATA[31:0]", 10, "end")
  d.port(ax, "L", y, "BAYER2RGB_REG_*")
  d.text(ax.x+8, y+18, "(内部 s_reg_*)", 9, color=GRAY)

  # ---- AXIL_BRIDGE ⇔ REG(要求と応答)
  for grp, top, flow, dw in (("req", 200, ">", "[48:0]"), ("rsp", 270, "<", "[33:0]")):
    ys = (top, top+20, top+40)
    for i, sig in enumerate(("vld", "busy", "data")):
      fwd = ((flow==">")!=(sig=="busy"))
      pts = [(ax.r, ys[i]), (rg.x, ys[i])] if( fwd ) else [(rg.x, ys[i]), (ax.r, ys[i])]
      d.wire(pts, BLACK)
      lbl = "s_%s.%s%s" % (grp, sig, dw if( sig=="data" ) else "")
      d.text(ax.r+8, ys[i]-7, lbl, LBL)
      d.port(ax, "R", ys[i], "%s.%s" % (grp, sig))
      d.port(rg, "L", ys[i], "%s.%s" % (grp, sig))

  # ---- REG ⇔ CDC
  rc = [(190, "s_cfg (cfg_t)", "o_cfg", "i_cfg", ">"), (208, "s_start", "o_start", "i_start", ">"),
        (226, "s_sw_rst", "o_sw_rst", "i_sw_rst", ">"), (244, "s_cdc_busy", "i_cdc_busy", "o_busy", "<"),
        (262, "s_evt_c (evt_t)", "i_evt", "o_evt", "<")]
  for yy, wl, pr, pc, flow in rc:
    pts = [(rg.r, yy), (cd.x, yy)] if( flow==">" ) else [(cd.x, yy), (rg.r, yy)]
    d.wire(pts, BLACK)
    d.text(rg.r+8, yy-7, wl, LBL)
    d.port(rg, "R", yy, pr)
    d.port(cd, "L", yy, pc)

  # ---- irq
  d.wire([(1000, rg.y), (1000, 110), (X1, 110)], BLACK)
  d.port(rg, "T", 1000, "o_irq", inset=22)
  d.text(X1+10, 110, "irq (ctrl_clk, High, レベル)", 11, bold=True)

  # ---- ctrl_clk / ctrl_rst_n
  yc, yr = 395, 415
  d.wire([(X0, yc), (1290, yc), (1290, cd.b)], GREEN)
  d.wire([(X0, yr), (1320, yr), (1320, cd.b)], BLACK)
  for xc, bx in ((430, ax), (1030, rg)):
    d.wire([(xc, yc), (xc, bx.b)], GREEN)
    d.dot(xc, yc, GREEN)
  for xr, bx in ((460, ax), (1060, rg)):
    d.wire([(xr, yr), (xr, bx.b)], BLACK)
    d.dot(xr, yr, BLACK)
  d.text(X0-10, yc, "ctrl_clk", 11, "end", bold=True)
  d.text(X0-10, yr, "ctrl_rst_n (Low)", 11, "end", bold=True)
  for bx, xc, xr in ((ax, 430, 460), (rg, 1030, 1060), (cd, 1290, 1320)):
    d.port(bx, "B", xc, "ctrl_clk", color=GREEN)
    d.port(bx, "B", xr, "ctrl_rst_n")

  # ---- CDC → RD_DMA / CORE / WR_DMA : s_ctl_v(フレームの設定 + start + sw_rst)
  xctl, yt = 1460, 490
  d.wire([(xctl, cd.b), (xctl, co.y)], BLACK)
  d.wire([(xctl, yt), (1100, yt), (1100, rd.y)], BLACK)
  d.wire([(xctl, yt), (1810, yt), (1810, wd.y)], BLACK)
  d.dot(xctl, yt, BLACK)
  d.text(xctl+9, 410, "s_ctl_v (ctl_t)", LBL, "middle", rot=-90)
  d.text(1110, yt-8, "s_ctl_v", LBL)
  d.port(cd, "B", xctl, "o_ctl")
  for bx, x in ((rd, 1100), (co, xctl), (wd, 1810)):
    d.port(bx, "T", x, "i_ctl", inset=22)

  # ---- 状態・イベント → CDC
  ye = 440
  d.wire([(1000, rd.y), (1000, ye), (1360, ye), (1360, cd.b)], BLACK)
  d.text(1010, ye-8, "s_rd_evt (rd_evt_t: busy, rd_err)", LBL)
  d.port(rd, "T", 1000, "o_evt", inset=22)
  d.port(cd, "B", 1360, "i_rd_evt")
  d.wire([(1900, wd.y), (1900, ye), (1600, ye), (1600, cd.b)], BLACK)
  d.text(1610, ye-8, "s_wr_evt (wr_evt_t: busy, frame_done, wr_err)", LBL)
  d.port(wd, "T", 1900, "o_evt", inset=22)
  d.port(cd, "B", 1600, "i_wr_evt")

  # ---- AXI4 マスタ(読み出しは左、書き込みは右)
  yb = 660
  d.wire([(X0, yb), (rb.x, yb)], BLUE, THICK, arrow="both")
  d.text(X0-10, yb-18, "AXI4 マスタ 読み出し (clk)", 11, "end", bold=True)
  d.text(X0-10, yb, "BAYER2RGB_MEM_AR* / R*", 10, "end")
  d.text(X0-10, yb+16, "ARADDR[39:0] RDATA[127:0]", 10, "end")
  d.port(rb, "L", yb, "BAYER2RGB_MEM_AR* / R*", color=BLUE)
  d.text(rb.x+8, yb+18, "(内部 s_mem_*)", 9, color=GRAY)
  d.wire([(wb.r, yb), (X1, yb)], BLUE, THICK, arrow="both")
  d.text(X1+10, yb-18, "AXI4 マスタ 書き込み (clk)", 11, bold=True)
  d.text(X1+10, yb, "BAYER2RGB_MEM_AW* / W* / B*", 10)
  d.text(X1+10, yb+16, "AWADDR[39:0] WDATA[127:0]", 10)
  d.port(wb, "R", yb, "BAYER2RGB_MEM_AW* / W* / B*", color=BLUE)
  d.text(wb.r-8, yb+18, "(内部 s_mem_*)", 9, "end", GRAY)

  # ---- BRIDGE ⇔ DMA ⇔ CORE
  vbd(d, rb, rd, 600, "s_ar", "[58:0]", "<", "ar", "ar", BLACK)
  vbd(d, rb, rd, 690, "s_r", "[130:0]", ">", "r", "r", BLUE)
  vbd(d, rd, co, 630, "s_pix", "[111:0]", ">", "pix", "pix")
  vbd(d, co, wd, 630, "s_rgb", "[194:0]", ">", "rgb", "rgb")
  vbd(d, wd, wb, 600, "s_aw", "[58:0]", ">", "aw", "aw", BLACK)
  vbd(d, wd, wb, 670, "s_w", "[144:0]", ">", "w", "w", BLUE)
  vbd(d, wd, wb, 740, "s_b", "[1:0]", "<", "b", "b", BLACK)

  # ---- 箱の説明
  d.text(rb.x+8, 760, "AR/R ⇔ vld/busy/data(2段スキッド)", 10, color=GRAY)
  d.text(rd.x+8, 752, "ライン単位のバースト読み出し", 10, color=GRAY)
  d.text(rd.x+8, 770, "16bit格納 → 14bit画素(1ビート=8画素)", 10, color=GRAY)
  d.text(co.x+8, 720, "IN_CTRL → BLC → WB → LBUF →", 10, color=GRAY)
  d.text(co.x+8, 738, "DMSC → FCS → GAMMA → OUT_FMT →", 10, color=GRAY)
  d.text(co.x+8, 756, "OUT_FIFO(詳細は2ページ目)", 10, color=GRAY)
  d.text(wd.x+8, 705, "RGB888(R,G,B順)に詰めて書く", 10, color=GRAY)
  d.text(wd.x+8, 723, "全バーストの応答で frame_done", 10, color=GRAY)
  d.text(wb.r-8, 780, "vld/busy/data ⇔ AW/W/B(2段スキッド)", 10, "end", GRAY)
  d.text(rg.x+8, 335, "レジスタ・割り込み", 10, color=GRAY)
  d.text(cd.x+130, 205, "トグル + 2段同期の", 10, color=GRAY)
  d.text(cd.x+130, 223, "ハンドシェイク(MCP)", 10, color=GRAY)

  # ---- clk / rst_n(映像系)と CDC の映像系側
  yv, yw = 860, 880
  d.wire([(X0, yv), (2580, yv), (2580, 210), (cd.r, 210)], GREEN)
  d.wire([(X0, yw), (2600, yw), (2600, 190), (cd.r, 190)], BLACK)
  drops = [(rb, 420, 450), (rd, 900, 960), (co, 1310, 1340), (wd, 1790, 1850), (wb, 2420, 2450)]
  for bx, xc, xr in drops:
    d.wire([(xc, yv), (xc, bx.b)], GREEN)
    d.dot(xc, yv, GREEN)
    d.wire([(xr, yw), (xr, bx.b)], BLACK)
    d.dot(xr, yw, BLACK)
    d.port(bx, "B", xc, "clk", color=GREEN)
    d.port(bx, "B", xr, "rst_n")
  d.text(X0-10, yv, "clk (400MHz)", 11, "end", bold=True)
  d.text(X0-10, yw, "rst_n (Low)", 11, "end", bold=True)
  d.port(cd, "R", 210, "clk", color=GREEN)
  d.port(cd, "R", 190, "rst_n")

  legend(d, X0, 970, [
      "※ AXI4マスタは1つのインタフェース(AR / R / AW / W / B)。図では読み出し側を左、書き込み側を右に分けて描いている",
      "※ 外部ポートは BAYER2RGB_MEM_*(AXI4マスタ)/ BAYER2RGB_REG_*(AXI4-Lite)。BRIDGEの中で s_mem_* / s_reg_* に受ける",
      "※ vld/busy/data(BAYER2RGB_VBD_IF): vld=1 かつ busy=0 のクロックで1転送。busy=1 の間、送り側は vld と data を保持する",
      "※ s_ctl_v = フレームの設定(STARTで確定しフレーム中は変わらない)+ start + sw_rst。内部信号は s_、内部レジスタは r_ で始める",
      "※ 交差は2か所(clk / rst_n を CDC へ引く線と AXI4 書き込みバス)",
  ])
  return d


# ============================================================================
# 2ページ目: BAYER2RGB_CORE
# ============================================================================
def build_core():
  d = Diagram("core", "BAYER2RGB_CORE (u_core)", 3720, 1140)
  X0, Y0, X1, Y1 = 240, 70, 3480, 900
  d.box(X0, Y0, X1-X0, Y1-Y0, "BAYER2RGB_CORE (u_core)", size=14, sw=2.0)

  bh = 220
  ic = d.box(300, 330, 300, bh, "BAYER2RGB_IN_CTRL (u_in_ctrl)")
  bl = d.box(700, 330, 190, bh, "BAYER2RGB_BLC (u_blc)")
  wb = d.box(990, 330, 190, bh, "BAYER2RGB_WB (u_wb)")
  lb = d.box(1280, 330, 510, bh, "BAYER2RGB_LBUF (u_lbuf)")
  dm = d.box(1890, 330, 210, bh, "BAYER2RGB_DMSC (u_dmsc)")
  fc = d.box(2200, 330, 190, bh, "BAYER2RGB_FCS (u_fcs)")
  gm = d.box(2490, 330, 210, bh, "BAYER2RGB_GAMMA (u_gamma)")
  of = d.box(2800, 330, 230, bh, "BAYER2RGB_OUT_FMT (u_out_fmt)")
  ff = d.box(3130, 330, 260, bh, "BAYER2RGB_OUT_FIFO (u_out_fifo)")
  s0 = d.box(1340, 650, 230, 130, "BAYER2RGB_SRAM_1R1W (u_sram0)")
  s1 = d.box(1580, 650, 230, 130, "BAYER2RGB_SRAM_1R1W (u_sram1)")

  notes = [(ic, "ステップ発行・掃き出し・クレジット"), (bl, "黒レベル減算(4ch)"), (wb, "WBゲイン(U4.12)"),
           (dm, "バイリニア補間・エッジ量"), (fc, "エッジ部の彩度抑制"),
           (gm, "折れ線ガンマ(37点)/線形"), (of, "テストパターン・出力整形"), (ff, "32段FIFO・使用数を返す")]
  for bx, s in notes:
    d.text(bx.x+8, 455, s, 10, color=GRAY)
  d.text(lb.x+8, 450, "2ライン保持(SRAM×2)・3×(PPC+2)画素の窓・上下左右の端はミラー", 10, color=GRAY)
  for sb, nm in ((s0, "2ライン前"), (s1, "1ライン前")):
    d.text(sb.x+8, sb.b-30, "480ワード × 112bit, 1R1W", 10, color=GRAY)
    d.text(sb.x+8, sb.b-14, nm, 10, color=GRAY)

  # ---- 入出力(vld/busy/data)
  ys = (380, 400, 420)
  d.wire([(X0, ys[0]), (ic.x, ys[0])], BLACK)
  d.wire([(ic.x, ys[1]), (X0, ys[1])], BLACK)
  d.wire([(X0, ys[2]), (ic.x, ys[2])], BLUE)
  for yy, nm, col in zip(ys, ("pix.vld", "pix.busy", "pix.data[111:0]"), (BLACK, BLACK, BLUE)):
    d.text(X0-10, yy, nm, 11, "end", col, bold=True)
    d.port(ic, "L", yy, nm.split("[")[0], color=col)
  d.wire([(ff.r, ys[0]), (X1, ys[0])], BLACK)
  d.wire([(X1, ys[1]), (ff.r, ys[1])], BLACK)
  d.wire([(ff.r, ys[2]), (X1, ys[2])], BLUE)
  for yy, nm, col in zip(ys, ("rgb.vld", "rgb.busy", "rgb.data[194:0]"), (BLACK, BLACK, BLUE)):
    d.text(X1+10, yy, nm, 11, "start", col, bold=True)
    d.port(ff, "R", yy, nm.split("[")[0], color=col)

  # ---- パイプライン(青)
  chain = [(ic, bl, "s_stp0", "o_stp", "i_stp"), (bl, wb, "s_stp1", "o_stp", "i_stp"),
           (wb, lb, "s_stp2", "o_stp", "i_stp"), (lb, dm, "s_win", "o_win", "i_win"),
           (dm, fc, "s_dm", "o_dm", "i_dm"), (fc, gm, "s_fc", "o_fc", "i_fc"), (gm, of, "s_gm", "o_gm", "i_gm")]
  for a, b, wl, pa, pb in chain:
    d.wire([(a.r, 420), (b.x, 420)], BLUE)
    d.text(a.r+8, 412, wl, LBL, color=BLUE)
    d.port(a, "R", 420, pa, color=BLUE)
    d.port(b, "L", 420, pb, color=BLUE)
  d.wire([(of.r, 400), (ff.x, 400)], BLACK)
  d.text(of.r+8, 392, "s_of_vld", LBL)
  d.port(of, "R", 400, "o_vld")
  d.port(ff, "L", 400, "i_vld")
  d.wire([(of.r, 420), (ff.x, 420)], BLUE)
  d.text(of.r+8, 434, "s_of_data", LBL, color=BLUE)
  d.port(of, "R", 420, "o_data", color=BLUE)
  d.port(ff, "L", 420, "i_data", color=BLUE)

  # ---- 上側: i_ctl / s_fifo_cnt / s_cfg / s_clr
  x_ctl, x_cnt, x_clr, x_cfg = 330, 370, 480, 520
  y_cnt, y_cfg, y_clr = 150, 200, 250
  d.wire([(x_ctl, Y0), (x_ctl, ic.y)], BLACK)
  d.text(x_ctl, Y0-6, "i_ctl (ctl_t)", 11, "start", rot=-90, bold=True)
  d.port(ic, "T", x_ctl, "i_ctl", inset=22)
  # 出力FIFOの使用数(クレジット)
  x_cnt_ff = 3330
  d.wire([(x_cnt_ff, ff.y), (x_cnt_ff, y_cnt), (x_cnt, y_cnt), (x_cnt, ic.y)], BLACK)
  d.text(x_cnt+10, y_cnt-8, "s_fifo_cnt[5:0](クレジット判定)", LBL)
  d.port(ff, "T", x_cnt_ff, "o_cnt", inset=22)
  d.port(ic, "T", x_cnt, "i_fifo_cnt", inset=22)
  # 設定(cfg_t)
  cfg_drops = [(bl, 760), (wb, 1050), (dm, 1950), (fc, 2260), (gm, 2550), (of, 2860)]
  d.wire([(x_cfg, ic.y), (x_cfg, y_cfg), (cfg_drops[-1][1], y_cfg), (cfg_drops[-1][1], of.y)], BLACK)
  for bx, x in cfg_drops[:-1]:
    d.wire([(x, y_cfg), (x, bx.y)], BLACK)
    d.dot(x, y_cfg, BLACK)
  d.text(x_cfg+10, y_cfg-8, "s_cfg (cfg_t: フレームの設定を IN_CTRL で受け直して配る)", LBL)
  d.port(ic, "T", x_cfg, "o_cfg", inset=22)
  for bx, x in cfg_drops:
    d.port(bx, "T", x, "i_cfg", inset=22)
  # クリア(ソフトリセット)
  clr_drops = [(bl, 800), (wb, 1090), (lb, 1320), (dm, 1990), (fc, 2300), (gm, 2590), (of, 2900), (ff, 3170)]
  d.wire([(x_clr, ic.y), (x_clr, y_clr), (clr_drops[-1][1], y_clr), (clr_drops[-1][1], ff.y)], BLACK)
  for bx, x in clr_drops[:-1]:
    d.wire([(x, y_clr), (x, bx.y)], BLACK)
    d.dot(x, y_clr, BLACK)
  d.text(1340, y_clr-8, "s_clr(ソフトリセットで各段の有効ビットを消す)", LBL)
  d.port(ic, "T", x_clr, "o_clr", inset=22)
  for bx, x in clr_drops:
    d.port(bx, "T", x, "i_clr", inset=22)

  # ---- LBUF ⇔ SRAM
  sp = [("ren", ">", BLACK), ("raddr", ">", BLACK), ("rdata", "<", BLUE), ("wen", ">", BLACK),
        ("waddr", ">", BLACK), ("wdata", ">", BLUE)]
  for idx, (sb, x0) in enumerate(((s0, 1355), (s1, 1595))):
    for i, (nm, flow, col) in enumerate(sp):
      x = x0+(30*i)
      pts = [(x, lb.b), (x, sb.y)] if( flow==">" ) else [(x, sb.y), (x, lb.b)]
      d.wire(pts, col)
      d.text(x+9, 600, "s_sram%d_%s" % (idx, nm), 8.5, "middle", col, rot=-90)
      pl = ("o_" if( flow==">" ) else "i_")+"sram%d_%s" % (idx, nm)
      ps = ("i_" if( flow==">" ) else "o_")+nm
      d.port(lb, "B", x, pl, size=8.5, color=col)
      d.port(sb, "T", x, ps, size=8.5, color=col, inset=26)

  # ---- clk / rst_n
  yv, yw = 830, 850
  stage = [(ic, 320, 350), (bl, 720, 750), (wb, 1010, 1040), (lb, 1295, 1320), (dm, 1910, 1940), (fc, 2220, 2250),
           (gm, 2510, 2540), (of, 2820, 2850), (ff, 3150, 3180)]
  d.wire([(270, Y1), (270, yv), (stage[-1][1], yv), (stage[-1][1], ff.b)], GREEN)
  d.wire([(290, Y1), (290, yw), (stage[-1][2], yw), (stage[-1][2], ff.b)], BLACK)
  for bx, xc, xr in stage[:-1]:
    d.wire([(xc, yv), (xc, bx.b)], GREEN)
    d.dot(xc, yv, GREEN)
    d.wire([(xr, yw), (xr, bx.b)], BLACK)
    d.dot(xr, yw, BLACK)
  for bx, xc, xr in stage:
    d.port(bx, "B", xc, "clk", color=GREEN)
    d.port(bx, "B", xr, "rst_n")
  for sb, xc in ((s0, 1550), (s1, 1790)):
    d.wire([(xc, yv), (xc, sb.b)], GREEN)
    d.dot(xc, yv, GREEN)
    d.port(sb, "B", xc, "clk", color=GREEN)
  d.text(270, Y1+8, "clk", 11, "end", GREEN, rot=-90, bold=True)
  d.text(290, Y1+8, "rst_n", 11, "end", rot=-90, bold=True)

  legend(d, X0, 960, [
      "※ s_stp*: 1ステップ = 入力ビート(PPC画素)、行末の掃き出し(1ステップ)、フレーム末の掃き出しライン(K+1ステップ)のどれか",
      "※ IN_CTRLより後ろは固定レイテンシ(合計14)で止まらずに流れる。(s_fifo_cnt + 直近16クロックの発行数) < 32 のときだけ発行する",
      "※ s_cfg はフレームの開始時だけ変わる。s_clr はソフトリセットの1クロックのパルス",
      "※ 交差: s_cfg の分岐と s_clr、rst_n の分岐と clk(点のない交差は接続していない)",
  ])
  return d


def main():
  out = sys.argv[1] if( len(sys.argv)>1 ) else "."
  os.makedirs(out, exist_ok=True)
  top = build_top()
  core = build_core()
  write_drawio(os.path.join(out, "bayer2rgb_arch.drawio"), [top, core])
  for dg, fn in ((top, "bayer2rgb_top.svg"), (core, "bayer2rgb_core.svg")):
    with open(os.path.join(out, fn), "w", encoding="utf-8") as f:
      f.write(dg.svg())
  print("written:", out)


if( __name__=="__main__" ):
  main()
