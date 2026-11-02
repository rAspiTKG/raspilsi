#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
コードカバレッジ(lcov 形式)を RTL のファイルごとにまとめる

  verilator_coverage --write-info sim/cov/coverage.info sim/cov/*.dat
  python3 tools/cov_summary.py sim/cov/coverage.info [--filter /rtl/] [--md 出力.md]

DA(行)と BRDA(分岐)の数を数える。--filter に一致するパスのファイルだけを対象にする。
"""
import argparse
import collections
import os
import sys


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("info")
  ap.add_argument("--filter", default="/rtl/")
  ap.add_argument("--md", default=None)
  a = ap.parse_args()

  lines = collections.OrderedDict()   # ファイル → {行: 回数}
  brs = collections.OrderedDict()     # ファイル → {(行, ブロック, 分岐): 回数}
  cur = None
  with open(a.info, encoding="utf-8", errors="replace") as f:
    for t in f:
      t = t.strip()
      if( t.startswith("SF:") ):
        cur = t[3:]
        lines.setdefault(cur, {})
        brs.setdefault(cur, {})
      elif( t.startswith("DA:") and (cur is not None) ):
        ln, cnt = t[3:].split(",")[:2]
        d = lines[cur]
        d[int(ln)] = d.get(int(ln), 0)+int(cnt)
      elif( t.startswith("BRDA:") and (cur is not None) ):
        p = t[5:].split(",")
        cnt = 0 if( p[3]=="-" ) else int(p[3])
        k = (p[0], p[1], p[2])
        b = brs[cur]
        b[k] = b.get(k, 0)+cnt
      elif( t=="end_of_record" ):
        cur = None

  out = []
  out.append("| ファイル | 行 | 実行した行 | 行カバレッジ | 分岐 | 通った分岐 | 分岐カバレッジ |")
  out.append("|---|---:|---:|---:|---:|---:|---:|")
  tl = 0
  th = 0
  tb = 0
  tbh = 0
  miss = []
  for path in sorted(lines):
    if( a.filter not in path ):
      continue
    d = lines[path]
    b = brs.get(path, {})
    nl = len(d)
    nh = sum(1 for v in d.values() if( v>0 ))
    nb = len(b)
    nbh = sum(1 for v in b.values() if( v>0 ))
    tl += nl
    th += nh
    tb += nb
    tbh += nbh
    for ln in sorted(d):
      if( d[ln]==0 ):
        miss.append("%s:%d" % (os.path.basename(path), ln))
    out.append("| %s | %d | %d | %s | %d | %d | %s |" % (
      os.path.basename(path), nl, nh, ("%.1f%%" % (100.0*nh/nl)) if( nl ) else "-",
      nb, nbh, ("%.1f%%" % (100.0*nbh/nb)) if( nb ) else "-"))
  out.append("| 合計 | %d | %d | %s | %d | %d | %s |" % (
    tl, th, ("%.1f%%" % (100.0*th/tl)) if( tl ) else "-", tb, tbh, ("%.1f%%" % (100.0*tbh/tb)) if( tb ) else "-"))
  text = "\n".join(out)
  print(text)
  if( miss ):
    print("実行していない行:", " ".join(miss[:200]))
  if( a.md ):
    with open(a.md, "w", encoding="utf-8") as f:
      f.write(text+"\n")
      if( miss ):
        f.write("\n実行していない行: " + ", ".join(miss) + "\n")
  return 0


if( __name__=="__main__" ):
  sys.exit(main())
