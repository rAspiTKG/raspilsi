#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BAYER_EX のブロック図を作る
  <out>/bayer_ex_arch.drawio : draw.io ファイル(1: トップ、2: CORE、3: PIXCOR、4: 検証環境)
  <out>/bayer_ex_top.svg、bayer_ex_core.svg、bayer_ex_pixcor.svg、bayer_ex_tb.svg
                             : 各ページの SVG(draw.io のデータを埋め込み。draw.io でも開ける)
使い方: python3 doc/tools/gen_arch.py <出力ディレクトリ>
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from archdiag import BLACK, BLUE, GRAY, GREEN, THICK, Diagram, write_drawio  # noqa: E402

LBL = 9.0   # 線のラベルの文字サイズ


def legend( d, x, y, notes, thick_label="" ):
  items = [(GREEN, 1.2, "クロック"), (BLUE, 1.2, "データパス(画素)"), (BLACK, 1.2, "リセット・制御・設定")]
  if( thick_label!="" ):
    items.append((BLACK, THICK, thick_label))
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
# 1ページ目: BAYER_EX(合成・配置配線のトップ)
# ============================================================================
def build_top():
  d = Diagram("top", "BAYER_EX (トップ)", 1620, 860)
  X0, Y0, X1, Y1 = 330, 80, 1290, 600
  d.box(X0, Y0, X1-X0, Y1-Y0, "BAYER_EX (論理合成・配置配線のトップ。ポートを平らにしたラッパ)", size=14, sw=2.0)
  si = d.box(400, 260, 220, 110, "BAYER_EX_DATA_IF (s_i_pix)")
  co = d.box(680, 160, 330, 340, "BAYER_EX_CORE (u_core)")
  so = d.box(1050, 260, 220, 110, "BAYER_EX_DATA_IF (s_o_pix)")

  # ---- 入力側(左辺)
  d.wire([(X0, 200), (co.x, 200)], BLACK)
  d.wire([(co.x, 230), (X0, 230)], BLACK)
  d.wire([(X0, 315), (si.x, 315)], BLUE)
  d.wire([(si.r, 315), (co.x, 315)], BLUE)
  d.text(X0-10, 200, "i_vld", 11, "end", bold=True)
  d.text(X0-10, 230, "o_busy", 11, "end", bold=True)
  d.text(X0-10, 307, "i_data[114:0]", 11, "end", BLUE, bold=True)
  d.text(X0-10, 324, "(bayer4x2_t)", 10, "end", BLUE)
  d.port(co, "L", 200, "i_vld")
  d.port(co, "L", 230, "o_busy")
  d.port(co, "L", 315, "i_pix.data", color=BLUE)
  d.port(si, "L", 315, "data", color=BLUE)
  d.port(si, "R", 315, "data", color=BLUE)
  d.text(si.x+8, si.b-34, "assign s_i_pix.data", 9, color=GRAY)
  d.text(si.x+8, si.b-18, "  = i_data;", 9, color=GRAY)
  d.text(si.r+6, 307, "s_i_pix", LBL, color=BLUE)

  # ---- 出力側(右辺)
  d.wire([(co.r, 200), (X1, 200)], BLACK)
  d.wire([(X1, 230), (co.r, 230)], BLACK)
  d.wire([(co.r, 315), (so.x, 315)], BLUE)
  d.wire([(so.r, 315), (X1, 315)], BLUE)
  d.text(X1+10, 200, "o_vld", 11, bold=True)
  d.text(X1+10, 230, "i_busy", 11, bold=True)
  d.text(X1+10, 307, "o_data[114:0]", 11, color=BLUE, bold=True)
  d.text(X1+10, 324, "(bayer4x2_t)", 10, color=BLUE)
  d.port(co, "R", 200, "o_vld")
  d.port(co, "R", 230, "i_busy")
  d.port(co, "R", 315, "o_pix.data", color=BLUE)
  d.port(so, "L", 315, "data", color=BLUE)
  d.port(so, "R", 315, "data", color=BLUE)
  d.text(so.x+8, so.b-34, "assign o_data", 9, color=GRAY)
  d.text(so.x+8, so.b-18, "  = s_o_pix.data;", 9, color=GRAY)
  d.text(co.r+6, 307, "s_o_pix", LBL, color=BLUE)

  # ---- 設定(上辺)
  d.wire([(845, Y0), (845, co.y)], BLACK)
  d.text(845, Y0-14, "i_cfg[122:0] (cfg_t)", 11, "middle", bold=True)
  d.port(co, "T", 845, "i_cfg", inset=22)

  # ---- clk / rst_n(下辺)
  d.wire([(800, Y1), (800, co.b)], GREEN)
  d.wire([(890, Y1), (890, co.b)], BLACK)
  d.port(co, "B", 800, "clk", color=GREEN)
  d.port(co, "B", 890, "rst_n")
  d.text(800, Y1+8, "clk (400MHz)", 11, "end", GREEN, rot=-90, bold=True)
  d.text(890, Y1+8, "rst_n (Low)", 11, "end", rot=-90, bold=True)

  # ---- 説明
  d.text(co.x+12, 380, "入力段(スキッド付き)→ PIXCOR(2段)", 10, color=GRAY)
  d.text(co.x+12, 398, "レイテンシ 3、1転送/クロック(8画素)", 10, color=GRAY)
  d.text(co.x+12, 416, "詳細は2ページ目", 10, color=GRAY)

  legend(d, X0-200, 720, [
      "※ BAYER_EX_CORE の data は SystemVerilog のインタフェース(BAYER_EX_DATA_IF、data だけ)。vld / busy はポート",
      "※ vld=1 かつ busy=0 のクロックで1転送。busy=1 の間、送り側は vld と data を保持する。o_vld / o_data / o_busy は FF から出す",
      "※ BAYER_EX はインタフェースのインスタンス(s_i_pix、s_o_pix)とつなぐだけで、論理を持たない。交差はない",
  ])
  return d


# ============================================================================
# 2ページ目: BAYER_EX_CORE
# ============================================================================
def build_core():
  d = Diagram("core", "BAYER_EX_CORE (u_core)", 1940, 1040)
  X0, Y0, X1, Y1 = 290, 80, 1660, 860
  d.box(X0, Y0, X1-X0, Y1-Y0, "BAYER_EX_CORE (u_core)", size=14, sw=2.0)
  ib = d.box(390, 300, 350, 260, "入力段とスキッド (r_in_* / r_skd_*)", dash=True)
  pc = d.box(930, 300, 340, 260, "BAYER_EX_PIXCOR (u_pixcor)")
  st = d.box(1300, 110, 320, 110, "停止の判定 (s_en)", dash=True)
  cf = d.box(1040, 640, 220, 80, "設定 (r_cfg)", dash=True)

  # ---- 入力側
  d.wire([(X0, 340), (ib.x, 340)], BLACK)
  d.wire([(X0, 420), (ib.x, 420)], BLUE)
  d.wire([(ib.x, 500), (X0, 500)], BLACK)
  d.text(X0-10, 340, "i_vld", 11, "end", bold=True)
  d.text(X0-10, 412, "i_pix.data[114:0]", 11, "end", BLUE, bold=True)
  d.text(X0-10, 429, "(BAYER_EX_DATA_IF.dst)", 10, "end", BLUE)
  d.text(X0-10, 500, "o_busy", 11, "end", bold=True)
  d.port(ib, "L", 340, "i_vld")
  d.port(ib, "L", 420, "i_pix.data", color=BLUE)
  d.port(ib, "L", 500, "o_busy")

  # ---- 入力段 → PIXCOR
  d.wire([(ib.r, 340), (pc.x, 340)], BLACK)
  d.wire([(ib.r, 420), (pc.x, 420)], BLUE)
  d.text(ib.r+8, 332, "r_in_vld", LBL)
  d.text(ib.r+8, 412, "r_in_data", LBL, color=BLUE)
  d.port(ib, "R", 340, "r_in_vld")
  d.port(ib, "R", 420, "r_in_data", color=BLUE)
  d.port(pc, "L", 340, "i_vld")
  d.port(pc, "L", 420, "i_data", color=BLUE)

  # ---- PIXCOR → 出力
  d.wire([(pc.r, 340), (X1, 340)], BLACK)
  d.wire([(pc.r, 420), (X1, 420)], BLUE)
  d.text(pc.r+8, 332, "s_pc_vld", LBL)
  d.text(pc.r+8, 412, "s_pc_data", LBL, color=BLUE)
  d.text(X1+10, 340, "o_vld", 11, bold=True)
  d.text(X1+10, 412, "o_pix.data[114:0]", 11, color=BLUE, bold=True)
  d.text(X1+10, 429, "(BAYER_EX_DATA_IF.src)", 10, color=BLUE)
  d.port(pc, "R", 340, "o_vld")
  d.port(pc, "R", 420, "o_data", color=BLUE)

  # ---- 停止の判定: s_en = !(s_pc_vld && i_busy)
  xb = 1570
  ys = 150
  d.wire([(xb, 340), (xb, st.b)], BLACK)
  d.dot(xb, 340, BLACK)
  d.wire([(X1, ys), (st.r, ys)], BLACK)
  d.text(X1+10, ys, "i_busy", 11, bold=True)
  d.port(st, "B", xb, "s_pc_vld", size=8.5)
  d.port(st, "R", ys, "i_busy")
  d.port(st, "L", ys, "s_en")
  # s_en → PIXCOR の i_en と、入力段の s_in_free
  xe_pc, xe_ib = 1100, 565
  d.wire([(st.x, ys), (xe_ib, ys), (xe_ib, ib.y)], BLACK)
  d.wire([(xe_pc, ys), (xe_pc, pc.y)], BLACK)
  d.dot(xe_pc, ys, BLACK)
  d.text(xe_ib+10, ys-8, "s_en(0: 出力が止められている → PIXCOR の全段を止める)", LBL)
  d.port(pc, "T", xe_pc, "i_en", inset=22)
  d.port(ib, "T", xe_ib, "s_en", inset=22)

  # ---- 設定
  d.wire([(X1, 680), (cf.r, 680)], BLACK)
  d.text(X1+10, 680, "i_cfg[122:0] (cfg_t)", 11, bold=True)
  d.port(cf, "R", 680, "i_cfg")
  xc = 1150
  d.wire([(xc, cf.y), (xc, pc.b)], BLACK)
  d.text(xc+10, 600, "r_cfg (cfg_t)", LBL)
  d.port(cf, "T", xc, "r_cfg", inset=22)
  d.port(pc, "B", xc, "i_cfg", inset=22)

  # ---- clk / rst_n
  yc, yr = 760, 780
  x_ib_r, x_ib_c, x_pc_c, x_pc_r, x_cf_c = 420, 450, 960, 990, 1070
  d.wire([(X0, yc), (x_cf_c, yc), (x_cf_c, cf.b)], GREEN)
  for x, bx in ((x_ib_c, ib), (x_pc_c, pc)):
    d.wire([(x, yc), (x, bx.b)], GREEN)
    d.dot(x, yc, GREEN)
  d.wire([(X0, yr), (x_pc_r, yr), (x_pc_r, pc.b)], BLACK)
  d.wire([(x_ib_r, yr), (x_ib_r, ib.b)], BLACK)
  d.dot(x_ib_r, yr, BLACK)
  d.text(X0-10, yc, "clk", 11, "end", GREEN, bold=True)
  d.text(X0-10, yr, "rst_n (Low)", 11, "end", bold=True)
  d.port(ib, "B", x_ib_r, "rst_n")
  d.port(ib, "B", x_ib_c, "clk", color=GREEN)
  d.port(pc, "B", x_pc_c, "clk", color=GREEN)
  d.port(pc, "B", x_pc_r, "rst_n")
  d.port(cf, "B", x_cf_c, "clk", color=GREEN)

  # ---- 説明
  d.text(ib.x+10, 448, "s_take = i_vld && !r_skd_vld", 9.5, color=GRAY)
  d.text(ib.x+10, 466, "s_in_free = !r_in_vld || s_en", 9.5, color=GRAY)
  d.text(ib.x+10, 484, "o_busy = r_skd_vld", 9.5, color=GRAY)
  d.text(ib.x+10, 386, "入力段が更新できないときの転送は", 9.5, color=GRAY)
  d.text(ib.x+10, 402, "スキッドで受ける", 9.5, color=GRAY)
  d.text(pc.x+10, 460, "1段目: 黒レベル補正", 10, color=GRAY)
  d.text(pc.x+10, 478, "2段目: ゲイン・丸め・クリップ", 10, color=GRAY)
  d.text(pc.x+10, 496, "詳細は3ページ目", 10, color=GRAY)
  d.text(st.x+10, 192, "s_en = !(s_pc_vld && i_busy)", 9.5, color=GRAY)
  d.text(cf.x+10, 696, "毎クロック i_cfg を受ける", 9.5, color=GRAY)

  legend(d, X0-200, 920, [
      "※ 破線の箱はモジュールではなく、CORE の中の論理のまとまり(FF と組み合わせ回路)。実線の箱はモジュール",
      "※ レイテンシ: 入力の転送から3クロック後に o_vld=1(入力段 1 + PIXCOR 2)。出力が止められていなければ1転送/クロック",
      "※ 交差は2か所(rst_n の分岐と clk)",
  ])
  return d


# ============================================================================
# 3ページ目: BAYER_EX_PIXCOR
# ============================================================================
def build_pixcor():
  d = Diagram("pixcor", "BAYER_EX_PIXCOR (u_pixcor)", 1960, 960)
  X0, Y0, X1, Y1 = 290, 80, 1680, 760
  d.box(X0, Y0, X1-X0, Y1-Y0, "BAYER_EX_PIXCOR (u_pixcor)", size=14, sw=2.0)
  se = d.box(390, 120, 330, 100, "色の選択 (s_site / s_lvl / s_gain)", dash=True)
  s1 = d.box(500, 300, 400, 220, "1段目 黒レベル補正 (s_q1 → r_data1 / r_vld1)", dash=True)
  s2 = d.box(1060, 300, 460, 220, "2段目 ゲイン・丸め・クリップ (s_q2 → r_data2 / r_vld2)", dash=True)

  # ---- 有効ビットとデータ
  d.wire([(X0, 350), (s1.x, 350)], BLACK)
  d.wire([(X0, 430), (s1.x, 430)], BLUE)
  d.text(X0-10, 350, "i_vld", 11, "end", bold=True)
  d.text(X0-10, 430, "i_data[114:0] (bayer4x2_t)", 11, "end", BLUE, bold=True)
  d.port(s1, "L", 350, "i_vld")
  d.port(s1, "L", 430, "i_data", color=BLUE)
  d.wire([(s1.r, 350), (s2.x, 350)], BLACK)
  d.wire([(s1.r, 430), (s2.x, 430)], BLUE)
  d.text(s1.r+8, 342, "r_vld1", LBL)
  d.text(s1.r+8, 422, "r_data1", LBL, color=BLUE)
  d.port(s1, "R", 350, "r_vld1")
  d.port(s1, "R", 430, "r_data1", color=BLUE)
  d.port(s2, "L", 350, "r_vld1")
  d.port(s2, "L", 430, "r_data1", color=BLUE)
  d.wire([(s2.r, 350), (X1, 350)], BLACK)
  d.wire([(s2.r, 430), (X1, 430)], BLUE)
  d.port(s2, "R", 350, "r_vld2")
  d.port(s2, "R", 430, "r_data2", color=BLUE)
  d.text(X1+10, 350, "o_vld", 11, bold=True)
  d.text(X1+10, 430, "o_data[114:0]", 11, color=BLUE, bold=True)

  # ---- 設定
  d.wire([(X0, 170), (se.x, 170)], BLACK)
  d.text(X0-10, 170, "i_cfg[122:0] (cfg_t)", 11, "end", bold=True)
  d.port(se, "L", 170, "i_cfg")
  xl = 650
  d.wire([(xl, se.b), (xl, s1.y)], BLACK)
  d.text(xl+10, 262, "s_lvl[2][4], bypass", LBL)
  d.port(se, "B", xl, "s_lvl", inset=6, size=8.5)
  d.port(s1, "T", xl, "s_lvl", inset=22)
  xg = 1200
  d.wire([(se.r, 170), (xg, 170), (xg, s2.y)], BLACK)
  d.text(se.r+8, 162, "s_gain[2][4], bypass", LBL)
  d.port(se, "R", 170, "s_gain")
  d.port(s2, "T", xg, "s_gain", inset=22)

  # ---- i_en(右辺から。0 のクロックは全段を保持)
  ye = 250
  xe1, xe2 = 860, 1440
  d.wire([(X1, ye), (xe1, ye), (xe1, s1.y)], BLACK)
  d.wire([(xe2, ye), (xe2, s2.y)], BLACK)
  d.dot(xe2, ye, BLACK)
  d.text(X1+10, ye, "i_en", 11, bold=True)
  d.port(s1, "T", xe1, "i_en", inset=22)
  d.port(s2, "T", xe2, "i_en", inset=22)

  # ---- clk / rst_n
  yc, yr = 640, 660
  xc1, xr1, xc2, xr2 = 820, 850, 1440, 1470
  d.wire([(X0, yc), (xc2, yc), (xc2, s2.b)], GREEN)
  d.wire([(xc1, yc), (xc1, s1.b)], GREEN)
  d.dot(xc1, yc, GREEN)
  d.wire([(X0, yr), (xr2, yr), (xr2, s2.b)], BLACK)
  d.wire([(xr1, yr), (xr1, s1.b)], BLACK)
  d.dot(xr1, yr, BLACK)
  d.text(X0-10, yc, "clk", 11, "end", GREEN, bold=True)
  d.text(X0-10, yr, "rst_n (Low)", 11, "end", bold=True)
  d.port(s1, "B", xc1, "clk", color=GREEN)
  d.port(s1, "B", xr1, "rst_n")
  d.port(s2, "B", xc2, "clk", color=GREEN)
  d.port(s2, "B", xr2, "rst_n")

  # ---- 説明
  d.text(se.x+10, 194, "色 = {y ^ phase[1], x[0] ^ phase[0]}", 9.5, color=GRAY)
  d.text(se.x+10, 210, "0:R 1:Gr 2:Gb 3:B(位置ごとに選ぶ)", 9.5, color=GRAY)
  d.text(s1.x+10, 470, "q1 = max(p − blc[色], 0)", 10, color=GRAY)
  d.text(s1.x+10, 488, "bypass=1: q1 = p", 10, color=GRAY)
  d.text(s1.x+10, 506, "i_en && i_vld で r_data1 に取り込む", 10, color=GRAY)
  d.text(s2.x+10, 470, "q2 = min(16383, (q1 × gain[色] + 2048) >> 12)", 10, color=GRAY)
  d.text(s2.x+10, 488, "bypass=1: q2 = q1", 10, color=GRAY)
  d.text(s2.x+10, 506, "i_en && r_vld1 で r_data2 に取り込む", 10, color=GRAY)
  d.text(s1.x+10, 398, "8画素とも同じ式(色だけ位置で変わる)", 9.5, color=GRAY)
  d.text(s2.x+10, 398, "積 30bit → 丸め 19bit → 14bit に飽和", 9.5, color=GRAY)

  legend(d, X0-200, 820, [
      "※ 破線の箱は PIXCOR の中の論理のまとまり。sof / eol / eof は計算せず、r_data1 → r_data2 とそのまま運ぶ",
      "※ 有効ビット(r_vld1、r_vld2)だけリセットする。データの FF はリセットしない(有効な転送のときだけ取り込む)",
      "※ 交差は2か所(i_en と s_gain、rst_n の分岐と clk)",
  ])
  return d


# ============================================================================
# 4ページ目: 検証環境(tb_top と UVM)
# ============================================================================
def build_tb():
  d = Diagram("tb", "検証環境 (tb_top)", 1980, 1120)
  X0, Y0, X1, Y1 = 60, 60, 1920, 960
  d.box(X0, Y0, X1-X0, Y1-Y0, "tb_top (検証環境のトップ)", size=14, sw=2.0)
  en = d.box(110, 110, 1760, 420, "bex_env (uvm_test_top.env)。テスト bex_*_test(bex_base_test)の中にある")
  ia = d.box(150, 160, 470, 340, "bex_in_agent (in_agt)")
  sq = d.box(180, 210, 190, 70, "bex_sequencer (sqr)")
  dv = d.box(400, 210, 190, 120, "bex_driver (drv)")
  mi = d.box(400, 360, 190, 110, "bex_monitor (mon)")
  sb = d.box(760, 180, 420, 150, "bex_scoreboard (sb)")
  rm = d.box(790, 230, 230, 80, "bex_ref_model")
  cv = d.box(760, 380, 420, 110, "bex_coverage (cov)")
  oa = d.box(1310, 160, 520, 340, "bex_out_agent (out_agt)")
  bd = d.box(1600, 210, 200, 120, "bex_busy_driver (bdrv)")
  mo = d.box(1340, 360, 200, 110, "bex_monitor (mon)")
  ii = d.box(330, 600, 300, 90, "bex_vbd_if (in_if)")
  mf = d.box(830, 600, 300, 90, "bex_misc_if (misc)")
  oi = d.box(1340, 600, 300, 90, "bex_vbd_if (out_if)")
  du = d.box(560, 770, 860, 140, "BAYER_EX_CORE (u_dut)。+define+BEX_DUT_TOP のときは BAYER_EX")

  # ---- シーケンサ → ドライバ
  d.wire([(sq.r, 245), (dv.x, 245)], BLACK)
  d.text(sq.r+4, 237, "bex_item", 8.5)
  # ---- ドライバ → in_if(vld / data を出す、busy を見る)
  # ドライバの線はモニタの箱をよけて左を通す
  d.wire([(dv.x, 300), (380, 300), (380, ii.y)], BLACK, THICK, arrow="both")
  d.text(388, 560, "vld / data(busy を見る)", 9)
  # ---- in_if → モニタ
  d.wire([(495, ii.y), (495, mi.b)], BLACK, THICK)
  d.text(503, 560, "転送を拾う", 9)
  # ---- in_if ⇔ DUT
  d.wire([(450, ii.b), (450, 840), (du.x, 840)], BLUE, THICK, arrow="both")
  d.text(458, 740, "i_vld / i_pix(s_i_pix) / o_busy", 9, color=BLUE)
  # ---- DUT ⇔ out_if
  d.wire([(du.r, 840), (1490, 840), (1490, oi.b)], BLUE, THICK, arrow="both")
  d.text(1498, 740, "o_vld / o_pix(s_o_pix) / i_busy", 9, color=BLUE)
  # ---- out_if → モニタ、busy のドライバ → out_if
  d.wire([(1440, oi.y), (1440, mo.b)], BLACK, THICK)
  d.text(1448, 560, "転送を拾う", 9)
  d.wire([(1700, bd.b), (1700, 640), (oi.r, 640)], BLACK, THICK)
  d.text(1708, 560, "busy を出す", 9)
  # ---- misc → DUT(設定)、テスト → misc
  d.wire([(980, mf.b), (980, du.y)], BLACK)
  d.text(988, 735, "i_cfg(cfg)", 9)
  d.wire([(980, en.b), (980, mf.y)], BLACK)
  d.text(988, 560, "cfg / rst_req(テストが書く)", 9)
  # ---- モニタ → スコアボード
  d.wire([(mi.r, 400), (700, 400), (700, 260), (sb.x, 260)], BLACK)
  d.text(598, 412, "ap(入力の転送 + 設定)", 8.5)
  d.wire([(mo.x, 400), (1240, 400), (1240, 290), (sb.r, 290)], BLACK)
  d.text(1248, 412, "ap(出力の転送)", 8.5)
  # ---- スコアボード → カバレッジ
  d.wire([(970, sb.b), (970, cv.y)], BLACK)
  d.text(978, 357, "画素の結果", 8.5)

  # ---- clk / rst_n(tb_top で作る)
  d.wire([(X0, 940), (1800, 940)], GREEN, arrow="none")
  d.text(X0+10, 928, "clk(+CLK_PS、既定 2.5 ns)/ rst_n(20クロック。テストの rst_req でもかける)は tb_top が作り、in_if・out_if・misc・u_dut に配る", 9.5, color=GREEN)

  # ---- 説明
  d.text(rm.x+8, rm.b-30, "仕様書 6章の式(整数)", 9, color=GRAY)
  d.text(rm.x+8, rm.b-14, "入力の転送 + 設定 → 期待値", 9, color=GRAY)
  d.text(rm.r+12, 244, "転送の順に比べる", 9, color=GRAY)
  d.text(rm.r+12, 260, "レイテンシ ≥ 3", 9, color=GRAY)
  d.text(rm.r+12, 276, "リセットで期待値を捨てる", 9, color=GRAY)
  d.text(cv.x+8, 430, "設定・画素の結果・フラグ・ハンドシェイクのビン(モニタ・スコアボード・テストが標本を渡す)", 9, color=GRAY)
  d.text(cv.x+8, 446, "[COVBIN] をログに出す(tools/merge_cov.py でまとめる)", 9, color=GRAY)
  d.text(ii.x+8, ii.b-30, "アサーション: busy=1 の間 vld / data を", 9, color=GRAY)
  d.text(ii.x+8, ii.b-14, "保持する、vld が不定にならない", 9, color=GRAY)
  d.text(oi.x+8, oi.b-30, "同じアサーションで DUT の出し方を", 9, color=GRAY)
  d.text(oi.x+8, oi.b-14, "確かめる", 9, color=GRAY)
  d.text(du.x+12, du.b-48, "u_dut の data のポートは BAYER_EX_DATA_IF(s_i_pix / s_o_pix)。", 10, color=GRAY)
  d.text(du.x+12, du.b-30, "tb_top が in_if.data → s_i_pix.data、s_o_pix.data → out_if.data を assign でつなぐ", 10, color=GRAY)

  legend(d, X0, 1000, [], thick_label="仮想インタフェース経由の信号の束")
  return d


def main():
  out = sys.argv[1] if( len(sys.argv)>1 ) else "."
  os.makedirs(out, exist_ok=True)
  pages = [(build_top(), "bayer_ex_top.svg"), (build_core(), "bayer_ex_core.svg"),
           (build_pixcor(), "bayer_ex_pixcor.svg"), (build_tb(), "bayer_ex_tb.svg")]
  write_drawio(os.path.join(out, "bayer_ex_arch.drawio"), [p[0] for p in pages])
  for dg, fn in pages:
    with open(os.path.join(out, fn), "w", encoding="utf-8") as f:
      f.write(dg.svg())
  print("written:", out)


if( __name__=="__main__" ):
  main()
