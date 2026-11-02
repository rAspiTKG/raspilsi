#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
回帰試験のログから機能カバレッジをまとめる

  python3 tools/merge_cov.py sim/logs/*_n*_s*.log [--md 出力.md]

各テストの終わりに bex_coverage が出す "[COVBIN] <ビン名> <回数>" を足し合わせ、
covergroup / coverpoint(cross)ごとのカバレッジと、当たっていないビンを示す。
"""
import argparse
import collections
import re
import sys

PAT = re.compile(r"\[COVBIN\]\s+(\S+)\s+(\d+)")


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("logs", nargs="+")
  ap.add_argument("--md", default=None, help="Markdown の出力先")
  a = ap.parse_args()

  hits = collections.OrderedDict()
  nlog = 0
  for path in a.logs:
    found = False
    with open(path, encoding="utf-8", errors="replace") as f:
      for line in f:
        m = PAT.search(line)
        if( m ):
          found = True
          hits[m.group(1)] = hits.get(m.group(1), 0)+int(m.group(2))
    if( found ):
      nlog += 1
  if( len(hits)==0 ):
    print("COVBIN がない")
    return 1

  # coverpoint / cross ごと
  groups = collections.OrderedDict()
  for name, n in hits.items():
    key = name.rsplit(".", 1)[0]
    groups.setdefault(key, []).append((name.rsplit(".", 1)[1], n))

  out = []
  out.append("| covergroup.coverpoint | ビン数 | 当たったビン | カバレッジ | 当たっていないビン |")
  out.append("|---|---:|---:|---:|---|")
  tot = 0
  tot_hit = 0
  for key, bins in groups.items():
    nb = len(bins)
    nh = sum(1 for b in bins if( b[1]>0 ))
    miss = [b[0] for b in bins if( b[1]==0 )]
    tot += nb
    tot_hit += nh
    out.append("| %s | %d | %d | %.1f%% | %s |" % (key, nb, nh, 100.0*nh/nb, ", ".join(miss) if( miss ) else "-"))
  out.append("| 合計 | %d | %d | %.1f%% | |" % (tot, tot_hit, 100.0*tot_hit/tot))
  text = "\n".join(out)
  print("ログ %d 本" % nlog)
  print(text)
  if( a.md ):
    with open(a.md, "w", encoding="utf-8") as f:
      f.write("機能カバレッジ(ログ %d 本の合計)\n\n" % nlog)
      f.write(text+"\n")
  return 0


if( __name__=="__main__" ):
  sys.exit(main())
