#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ORFS の結果(各段階の metrics の JSON、ログ、レポート)を1つの Markdown にまとめる

  python3 pd_summary.py --name asap7_ppc8 --logs <LOG_DIR> --reports <REPORTS_DIR> \
                        --results <RESULTS_DIR> --syn <syn/yosys/out/.../reports> --out <出力先>

  出力: <出力先>/summary.md、metrics.json(全段階の値をまとめたもの)、
        レポートの写し(タイミング・電力・DRC など)、layout.png(DEF があるとき)
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys

# 段階(ORFS の metrics の接頭語)と表の見出し
STAGES = [
  ("floorplan",     "フロアプラン"),
  ("detailedplace", "配置"),
  ("cts",           "CTS"),
  ("globalroute",   "概略配線"),
  ("detailedroute", "詳細配線"),
  ("finish",        "最終(抽出後)"),
]

# 表の行: (見出し, metrics の名前の後半, 換算, 書式)
ROWS = [
  ("セル数",                     "design__instance__count",              1.0,    "%.0f"),
  ("セルの面積 [um²]",           "design__instance__area",               1.0,    "%.1f"),
  ("使用率 [%]",                 "design__instance__utilization",        100.0,  "%.1f"),
  ("セットアップ WNS [ps]",      "timing__setup__ws",                    1.0,    "%.1f"),
  ("セットアップ TNS [ps]",      "timing__setup__tns",                   1.0,    "%.1f"),
  ("セットアップ違反 [本]",      "timing__drv__setup_violation_count",   1.0,    "%.0f"),
  ("ホールド WNS [ps]",          "timing__hold__ws",                     1.0,    "%.1f"),
  ("ホールド TNS [ps]",          "timing__hold__tns",                    1.0,    "%.1f"),
  ("ホールド違反 [本]",          "timing__drv__hold_violation_count",    1.0,    "%.0f"),
  ("ホールド用バッファ [個]",    "design__instance__count__hold_buffer", 1.0,    "%.0f"),
  ("クロックスキュー(セットアップ)[ps]", "clock__skew__setup",          1.0,    "%.1f"),
  ("クロックスキュー(ホールド)[ps]",     "clock__skew__hold",           1.0,    "%.1f"),
  ("遷移時間の違反 [本]",        "timing__drv__max_slew",                1.0,    "%.0f"),
  ("容量の違反 [本]",            "timing__drv__max_cap",                 1.0,    "%.0f"),
  ("配線長 [um](配置・CTS は見積もり)", "route__wirelength",            1.0,    "%.0f"),
  ("DRC 違反 [個]",              "route__drc_errors",                    1.0,    "%.0f"),
  ("アンテナ違反 [本]",          "antenna__violating__nets",             1.0,    "%.0f"),
  ("電力 [mW]",                  "power__total",                         1000.0, "%.2f"),
  ("IR ドロップ VDD [mV]",       "design_powergrid__drop__worst__net:VDD", 1000.0, "%.1f"),
  ("IR ドロップ VSS [mV]",       "design_powergrid__drop__worst__net:VSS", 1000.0, "%.1f"),
]

# 実行時間をまとめる段階(ログの名前の先頭、見出し)
TIME_GROUPS = [
  (r"2_",      "フロアプラン"),
  (r"3_",      "配置"),
  (r"4_",      "CTS"),
  (r"5_1_",    "概略配線"),
  (r"5_[23]_", "詳細配線"),
  (r"6_",      "最終"),
]

# ORFS の do-step で動く段階(終わると metrics の JSON を書く)。JSON がなければ途中で止まった
STEP_RE = r"^([2-5]_\d_\w+|6_1_fill|6_report)$"


def load_metrics( logdir ):
  m = {}
  for p in sorted(glob.glob(os.path.join(logdir, "*.json"))):
    try:
      with open(p, encoding="utf-8") as f:
        d = json.load(f)
    except Exception:
      continue
    if( isinstance(d,dict) ):
      m.update(d)
  return m


def pick( m, stage, key ):
  """stage__key を探す(stage__key__xxx の形も見る)"""
  k = stage+"__"+key
  if( k in m ):
    return m[k]
  for kk in m:
    if( kk.startswith(k+"__") and not kk.endswith("__count") ):
      return m[kk]
  return None


def elapsed( logdir ):
  """段階ごとの実行時間 [秒] と、途中で止まった段階(ログはあるが metrics の JSON がない)を返す"""
  t = {}
  stopped = []
  for p in sorted(glob.glob(os.path.join(logdir, "*.log"))):
    stem = os.path.basename(p)[:-4]
    grp = None
    for (pat, label) in TIME_GROUPS:
      if( re.match(pat,stem) ):
        grp = label
        break
    if( grp is None ):
      continue
    with open(p, encoding="utf-8", errors="ignore") as f:
      s = f.read()
    for e in re.finditer(r"Elapsed time: (?:(\d+):)?(\d+):([\d.]+)", s):
      sec = float(e.group(3))+60*int(e.group(2))
      if( e.group(1) ):
        sec += 3600*int(e.group(1))
      t[grp] = t.get(grp, 0.0)+sec
    if( re.match(STEP_RE,stem) and not(os.path.exists(os.path.join(logdir,stem+".json"))) ):
      mem = re.findall(r"memory = ([\d.]+) \(MB\)", s)
      stopped.append((grp, stem, float(mem[-1]) if( len(mem)>0 ) else None))
  return t, stopped


def grt_wirelength( logdir ):
  """概略配線の配線長 [um](5_1_grt.log の GRT-0018)"""
  p = os.path.join(logdir, "5_1_grt.log")
  if( not(os.path.exists(p)) ):
    return None
  with open(p, encoding="utf-8", errors="ignore") as f:
    mm = re.findall(r"GRT-0018\] Total wirelength: ([\d.]+) um", f.read())
  return float(mm[-1]) if( len(mm)>0 ) else None


def fmt( v, scale, f ):
  if( v is None ):
    return "-"
  try:
    return f % (float(v)*scale)
  except Exception:
    return str(v)


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--name", required=True)
  ap.add_argument("--logs", required=True)
  ap.add_argument("--reports", required=True)
  ap.add_argument("--results", required=True)
  ap.add_argument("--syn", default="")
  ap.add_argument("--out", required=True)
  ap.add_argument("--lef", action="append", default=[], help="図に使う LEF(DEF のセルの大きさ)")
  ap.add_argument("--def", dest="deff", default="", help="図に使う DEF(既定は results の 6_final.def)")
  ap.add_argument("--def_label", default="6_final", help="図の見出しに書く段階の名前")
  a = ap.parse_args()
  os.makedirs(a.out, exist_ok=True)

  m = load_metrics(a.logs)
  with open(os.path.join(a.out, "metrics.json"), "w", encoding="utf-8") as f:
    json.dump(m, f, indent=1, sort_keys=True, ensure_ascii=False)
  # 概略配線の配線長は metrics にないのでログから取る(なければ見積もりの値になる)
  wl = grt_wirelength(a.logs)
  if( (wl is not None)and("globalroute__route__wirelength" not in m) ):
    m["globalroute__route__wirelength"] = wl

  L = []
  L.append("# 配置配線の結果(%s)" % a.name)
  L.append("")
  L.append("OpenROAD-flow-scripts(ASAP7)の各段階の値です。`pd/openroad/scripts/pd_summary.py` で作りました。")
  L.append("時間の単位は ps(ASAP7 のライブラリの単位)です。")
  L.append("")
  # 段階ごとの表
  have = [s for s in STAGES if( any(k.startswith(s[0]+"__") for k in m) )]
  L.append("| 項目 | " + " | ".join(s[1] for s in have) + " |")
  L.append("|---|" + "---:|"*len(have))
  for (title, key, scale, f) in ROWS:
    vals = [fmt(pick(m, s[0], key), scale, f) for s in have]
    if( all(v=="-" for v in vals) ):
      continue
    L.append("| %s | %s |" % (title, " | ".join(vals)))
  L.append("")
  # ダイの大きさ
  die = pick(m, "floorplan", "design__die__area")
  core = pick(m, "floorplan", "design__core__area")
  if( die is not None or core is not None ):
    L.append("- ダイの面積: %s um²、コアの面積: %s um²" % (fmt(die, 1.0, "%.0f"), fmt(core, 1.0, "%.0f")))
  # 実行時間
  t, stopped = elapsed(a.logs)
  if( len(t)>0 ):
    stop_grp = [g for (g, _stem, _mem) in stopped]
    parts = []
    tot = 0.0
    for (_pat, label) in TIME_GROUPS:
      if( label not in t ):
        continue
      parts.append("%s %.1f 分%s" % (label, t[label]/60.0, "(途中まで)" if( label in stop_grp ) else ""))
      tot += t[label]
    L.append("- 実行時間(CPU 2個): " + "、".join(parts) + "(合計 %.1f 分)" % (tot/60.0))
  for (g, stem, mem) in stopped:
    L.append("- 途中で止まった段階: %s(%s.log%s)" % (g, stem, "。最後に記録されたメモリ %.0f MB" % mem if( mem is not None ) else ""))
  L.append("")

  # レポートの写し
  copied = []
  for pat in ["2_floorplan_final.rpt", "3_detailed_place.rpt", "4_cts_final.rpt", "5_global_route.rpt",
              "io_latency.rpt", "5_route_drc.rpt", "drt_antennas.log", "6_finish.rpt", "VDD.rpt", "VSS.rpt",
              "congestion.rpt"]:
    for p in glob.glob(os.path.join(a.reports, pat)):
      shutil.copy(p, a.out)
      copied.append(os.path.basename(p))
  if( len(copied)>0 ):
    L.append("## レポート")
    L.append("")
    for c in copied:
      L.append("- [%s](%s)" % (c, c))
    L.append("")

  # 配置の図
  deff = a.deff if( a.deff!="" ) else os.path.join(a.results, "6_final.def")
  if( os.path.exists(deff) and len(a.lef)>0 ):
    png = os.path.join(a.out, "layout.png")
    cmd = [sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "plot_layout.py"),
           "--def", deff, "--out", png, "--title", "BAYER2RGB %s (%s)" % (a.name, a.def_label)]
    for l in a.lef:
      cmd += ["--lef", l]
    if( subprocess.call(cmd)==0 ):
      L.append("## 配置")
      L.append("")
      L.append("![配置](layout.png)")
      L.append("")
      L.append("黄色: SRAM マクロ、青: 標準セルの密度、赤: 端子")
      L.append("")

  with open(os.path.join(a.out, "summary.md"), "w", encoding="utf-8") as f:
    f.write("\n".join(L)+"\n")
  print("\n".join(L))
  return 0


if( __name__=="__main__" ):
  sys.exit(main())
