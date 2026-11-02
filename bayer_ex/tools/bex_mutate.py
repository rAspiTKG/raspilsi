#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
変異テスト: RTL にわざと誤りを1つずつ入れ、検証環境が見つけるか(テストが失敗するか)を確かめる

  cd sim
  python3 ../tools/bex_mutate.py                   # 全部の変異
  python3 ../tools/bex_mutate.py m2_round m6_sat   # 指定した変異だけ
  python3 ../tools/bex_mutate.py --list            # 変異の一覧

  変異ごとに rtl/ を sim/mut/<名前>/rtl にコピーして1か所を書き換え、
  make build(RTL_F と OBJ を指定。ほかの設定は make と同じ)でビルドして、主なテストを流す。
  結果は sim/mut/result.md(Markdown の表)。UVM_HOME などは make と同じ環境変数を使う。
  ビルドはメモリを使うので、1つずつ順に行う。
"""
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM = os.path.join(ROOT, "sim")
OUT = os.path.join(SIM, "mut")

# (名前, ファイル, 元の文字列, 書き換えた文字列, 内容)
MUTANTS = [
  ("m1_site", "BAYER_EX_PKG.sv",
   "f_site = {ypar^phase[1], xpar^phase[0]};",
   "f_site = {ypar^phase[0], xpar^phase[1]};",
   "色の位置の計算で phase の2ビットを入れ替える(PKG の f_site)"),
  ("m2_round", "BAYER_EX_PIXCOR.sv",
   "MW'(1<<(GAIN_FRAC-1))",
   "MW'((1<<(GAIN_FRAC-1))-1)",
   "ゲインの丸めの定数を 2048 → 2047(PIXCOR)"),
  ("m3_skid", "BAYER_EX_CORE.sv",
   "      end else if( s_take ) begin\n        r_skd_vld <= 1'b1;\n      end",
   "      end else if( s_take ) begin\n        r_skd_vld <= 1'b0;\n      end",
   "スキッドに受け取らない。止まっている間の転送を落とす(CORE)"),
  ("m4_hold", "BAYER_EX_PIXCOR.sv",
   "    if( i_en&&r_vld1 ) begin",
   "    if( r_vld1 ) begin",
   "2段目のデータが、止まっている間(i_en=0)も変わる(PIXCOR)"),
  ("m5_bypass", "BAYER_EX_PIXCOR.sv",
   "        if( i_cfg.bypass ) begin\n          s_q2[y][x] = r_data1.pix[y][x];",
   "        if( 1'b0 ) begin\n          s_q2[y][x] = r_data1.pix[y][x];",
   "bypass=1 でも2段目のゲインをかける(PIXCOR)"),
  ("m6_sat", "BAYER_EX_PIXCOR.sv",
   "s_q2[y][x] = PIX_W'(PIX_MAX);",
   "s_q2[y][x] = PIX_W'(s_t[y][x]);",
   "ゲインの結果を飽和させず、下位14ビットを出す(PIXCOR)"),
]

# (テスト名, 実行する回数)。シードは 11, 12, …
TESTS = [("bex_smoke_test", 1), ("bex_bypass_test", 1), ("bex_phase_test", 1), ("bex_edge_test", 1),
         ("bex_stall_test", 1), ("bex_random_test", 2)]

# エラーの ID の説明
ID_TEXT = {"SB": "スコアボード", "SVA": "アサーション", "TIMEOUT": "出力が終わらない", "STALL": "o_busy=1 にならない"}


def build( name ):
  d = os.path.join(OUT, name)
  rtl_f = os.path.join(d, "rtl", "rtl.f")
  obj = os.path.join(d, "obj")
  with open(os.path.join(d, "build.log"), "w") as f:
    rc = subprocess.call(["make", "--no-print-directory", "-C", SIM, "build", "RTL_F="+rtl_f, "OBJ="+obj],
                         stdout=f, stderr=subprocess.STDOUT)
  return rc==0, os.path.join(obj, "Vtb_top")


def run_tests( name, binp ):
  """失敗したテストと、エラーの ID ごとの数を返す"""
  d = os.path.join(OUT, name)
  failed = []
  ids = {}
  for (t, ns) in TESTS:
    for k in range(ns):
      log = os.path.join(d, "%s_s%d.log" % (t, k+1))
      with open(log, "w") as f:
        subprocess.call([binp, "+UVM_TESTNAME="+t, "+verilator+seed+%d" % (k+11), "+verilator+rand+reset+2",
                         "+UVM_VERBOSITY=UVM_LOW"], stdout=f, stderr=subprocess.STDOUT, cwd=d)
      txt = open(log, encoding="utf-8", errors="ignore").read()
      if( ("TEST PASSED" not in txt)or("%Error" in txt) ):
        failed.append(t.replace("bex_", "").replace("_test", "")+("(%d)" % (k+1) if( ns>1 ) else ""))
      for m in re.finditer(r"^UVM_(?:ERROR|FATAL) [^\n]*?\[([A-Z_]+)\]", txt, re.M):
        ids[m.group(1)] = ids.get(m.group(1), 0)+1
  return failed, ids


def main():
  args = sys.argv[1:]
  if( "--list" in args ):
    for (name, fn, _old, _new, desc) in MUTANTS:
      print("%-10s %-20s %s" % (name, fn, desc))
    return 0
  names = [m[0] for m in MUTANTS]
  for a in args:
    if( a not in names ):
      print("不明な変異: %s(--list で一覧)" % a)
      return 1
  os.makedirs(OUT, exist_ok=True)
  n_test = sum([ns for (_t, ns) in TESTS])
  rows = []
  for (name, fn, old, new, desc) in MUTANTS:
    if( (len(args)>0)and(name not in args) ):
      continue
    d = os.path.join(OUT, name)
    shutil.rmtree(d, ignore_errors=True)
    rtl = os.path.join(d, "rtl")
    os.makedirs(rtl)
    for f in os.listdir(os.path.join(ROOT, "rtl")):
      if( f.endswith(".sv")or(f.endswith(".f")) ):
        shutil.copy(os.path.join(ROOT, "rtl", f), rtl)
    p = os.path.join(rtl, fn)
    s = open(p, encoding="utf-8").read()
    if( s.count(old)!=1 ):
      print("%s: 書き換える文字列が %d か所ある(1か所のはず)。RTL が変わったら MUTANTS を直す" % (name, s.count(old)))
      return 1
    open(p, "w", encoding="utf-8").write(s.replace(old, new))
    print("%s: ビルド" % name, flush=True)
    ok, binp = build(name)
    if( not(ok) ):
      rows.append((name, desc, "ビルド失敗", "-", "-"))
      continue
    failed, ids = run_tests(name, binp)
    if( len(failed)==0 ):
      res = "見逃し"
      ftxt = "なし"
    else:
      res = "検出"
      ftxt = "%d / %d 本: %s" % (len(failed), n_test, "、".join(failed))
    itxt = "、".join(["%s %d 件" % (ID_TEXT.get(k, k), v) for (k, v) in sorted(ids.items())])
    rows.append((name, desc, res, ftxt, itxt if( itxt!="" ) else "-"))
    print("%s: %s %s" % (name, res, ftxt), flush=True)
  path = os.path.join(OUT, "result.md")
  with open(path, "w", encoding="utf-8") as f:
    f.write("| 変異 | 入れた誤り | 結果 | 失敗したテスト | 出たエラー |\n|---|---|---|---|---|\n")
    for r in rows:
      f.write("| %s | %s | %s | %s | %s |\n" % r)
  n_det = len([r for r in rows if( r[2]=="検出" )])
  print("検出 %d / %d。結果: %s" % (n_det, len(rows), path))
  return 0 if( n_det==len(rows) ) else 1


if( __name__=="__main__" ):
  sys.exit(main())
