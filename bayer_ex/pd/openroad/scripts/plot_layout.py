#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
配置配線の結果(DEF)から、レイアウトの概略図を描く

  python3 plot_layout.py --def 6_final.def --lef tech.lef --lef cells.lef --lef macro.lef ... --out layout.png

  - ダイとコアの外形、マクロ(名前つき。あれば)、端子の位置(入力は赤、出力は緑、ほかは黒)
  - 標準セルの密度(面積の割合を色で表す)
  GUI を使わずに結果を見るためのもの。細かい配線は描かない
"""
import argparse
import re
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt          # noqa: E402
import matplotlib.patches as patches     # noqa: E402
import numpy as np                       # noqa: E402


# ラベルに使わない一般的なインスタンス名
GENERIC = ("u_core", "u_mem", "u_sram", "u_fifo")
# 90度回した向き(幅と高さを入れ替える)
ROT90 = ("E", "W", "FE", "FW")


def read_lef_sizes( paths ):
  """LEF の MACRO ごとの大きさ(um)と CLASS"""
  sizes = {}
  for p in paths:
    name = None
    cls = ""
    wh = None
    with open(p, encoding="utf-8", errors="ignore") as f:
      for ln in f:
        t = ln.split()
        if( len(t)==0 ):
          continue
        if( t[0]=="MACRO" and len(t)>=2 ):
          name = t[1]
          cls = ""
          wh = None
        elif( name is not None and t[0]=="CLASS" ):
          cls = t[1].rstrip(";")
        elif( name is not None and t[0]=="SIZE" and len(t)>=4 ):
          wh = (float(t[1]), float(t[3]))
        elif( name is not None and t[0]=="END" and len(t)>=2 and t[1]==name ):
          # SIZE と CLASS の順は LEF によって違うので、MACRO の終わりでまとめる
          if( wh is not None ):
            sizes[name] = (wh[0], wh[1], cls)
          name = None
  return sizes


def read_def( path ):
  """DEF のダイ、部品(位置・向き)、端子"""
  units = 1000.0
  die = None
  comps = []
  pins = []
  sect = None
  buf = ""
  with open(path, encoding="utf-8", errors="ignore") as f:
    for ln in f:
      s = ln.strip()
      if( s.startswith("UNITS DISTANCE MICRONS") ):
        units = float(s.split()[3])
      elif( s.startswith("DIEAREA") ):
        v = [float(x) for x in re.findall(r"-?\d+", s)]
        die = (v[0]/units, v[1]/units, v[2]/units, v[3]/units)
      elif( s.startswith("COMPONENTS") ):
        sect = "C"
        buf = ""
      elif( s.startswith("END COMPONENTS") ):
        sect = None
      elif( s.startswith("PINS") ):
        sect = "P"
        buf = ""
      elif( s.startswith("END PINS") ):
        sect = None
      elif( sect is not None ):
        buf += " "+s
        if( s.endswith(";") ):
          if( sect=="C" ):
            m = re.match(r"\s*-\s+(\S+)\s+(\S+).*?\+\s+(PLACED|FIXED)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+(\S+)", buf)
            if( m ):
              comps.append((m.group(1), m.group(2), float(m.group(4))/units, float(m.group(5))/units, m.group(6)))
          else:
            m = re.match(r"\s*-\s+(\S+).*?\+\s+(PLACED|FIXED)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)", buf)
            if( m ):
              pins.append((m.group(1), float(m.group(3))/units, float(m.group(4))/units))
          buf = ""
  return die, comps, pins


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--def", dest="deff", required=True)
  ap.add_argument("--lef", action="append", default=[])
  ap.add_argument("--out", required=True)
  ap.add_argument("--title", default="")
  ap.add_argument("--bin", type=float, default=5.0, help="密度を数える升目の大きさ [um]")
  a = ap.parse_args()

  sizes = read_lef_sizes(a.lef)
  die, comps, pins = read_def(a.deff)
  if( die is None ):
    print("DIEAREA がありません")
    return 1
  x0, y0, x1, y1 = die
  nx = max(1, int((x1-x0)/a.bin))
  ny = max(1, int((y1-y0)/a.bin))
  dens = np.zeros((ny, nx))
  macros = []
  skip = ("FILLER", "DECAP", "TAPCELL")
  for (inst, cell, x, y, ori) in comps:
    if( cell not in sizes ):
      continue
    w, h, cls = sizes[cell]
    if( ori in ROT90 ):
      w, h = h, w
    if( cls=="BLOCK" ):
      macros.append((inst, cell, x, y, w, h))
      continue
    if( cell.startswith(skip) ):
      continue
    i = min(nx-1, max(0, int((x+w/2-x0)/a.bin)))
    j = min(ny-1, max(0, int((y+h/2-y0)/a.bin)))
    dens[j, i] += w*h
  dens = dens/(a.bin*a.bin)

  fig, ax = plt.subplots(figsize=(8, 8*(y1-y0)/(x1-x0)+0.6))
  im = ax.imshow(dens, origin="lower", extent=(x0, x0+nx*a.bin, y0, y0+ny*a.bin), cmap="Blues",
                 vmin=0.0, vmax=1.0, interpolation="nearest")
  ax.add_patch(patches.Rectangle((x0, y0), x1-x0, y1-y0, fill=False, lw=1.0, ec="black"))
  for (inst, cell, x, y, w, h) in macros:
    ax.add_patch(patches.Rectangle((x, y), w, h, fill=True, fc="#f2c94c", ec="#8a6d00", lw=0.8, alpha=0.9))
    # ラベルはインスタンス名のうち意味のある最後の部分(u_sram0、u_wbuf など)と大きさ
    toks = [t for t in re.split(r"[/.]", inst) if( t.startswith("u_") and t not in GENERIC )]
    label = toks[-1] if( len(toks)>0 ) else inst
    rot = 90 if( w<15.0 ) else 0
    ax.text(x+w/2, y+h/2, label+"\n"+cell.replace("b2r_sram1r1w_", ""), ha="center", va="center",
            fontsize=6, rotation=rot)
  # 端子: 名前の先頭で色を分ける(i_: 入力、o_: 出力、ほか: クロック・リセット)
  groups = {"i": [], "o": [], "-": []}
  io_pre = ("i_", "o_")
  for p in pins:
    k = p[0][0] if( p[0][:2] in io_pre ) else "-"
    groups[k].append(p)
  for (k, col) in (("i", "#c0392b"), ("o", "#1e8449"), ("-", "#000000")):
    sel = groups[k]
    if( len(sel)>0 ):
      ax.plot([p[1] for p in sel], [p[2] for p in sel], ls="none", marker="s", ms=1.6, color=col)
  ax.set_xlim(x0-2, x1+2)
  ax.set_ylim(y0-2, y1+2)
  ax.set_aspect("equal")
  ax.set_xlabel("x [um]")
  ax.set_ylabel("y [um]")
  ax.set_title(a.title, fontsize=9)
  cb = fig.colorbar(im, ax=ax, fraction=0.04, pad=0.02)
  cb.set_label("standard cell density")
  fig.tight_layout()
  fig.savefig(a.out, dpi=150)
  print("%s: ダイ %.1f x %.1f um、マクロ %d 個、端子 %d 本" % (a.out, x1-x0, y1-y0, len(macros), len(pins)))
  return 0


if( __name__=="__main__" ):
  sys.exit(main())
