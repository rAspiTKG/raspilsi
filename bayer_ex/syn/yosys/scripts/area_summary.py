#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Yosys の stat(階層つき)の結果を、モジュールごとの面積の表(Markdown)にまとめる

  python3 area_summary.py reports/area.txt > reports/area_summary.md

  - モジュールの面積は、そのモジュールの中のセルだけ(下の階層は含めない)
  - 同じモジュールが複数あるときは個数を掛ける
  - $paramod(sv2v)や 名前$インスタンス(yosys-slang)は元のモジュール名にまとめる
    (パラメータやインスタンスの違うものは足す)
"""
import re
import sys


def base_name( mod ):
  """元のモジュール名(sv2v: $paramod...\\名前...、yosys-slang: 名前$インスタンスのパス)"""
  m = re.match(r"\$paramod(?:\$[0-9a-f]+)?\\([A-Za-z0-9_]+)", mod)
  if( m ):
    return m.group(1)
  return mod.lstrip("\\").split("$")[0]


def main():
  if( len(sys.argv)<2 ):
    print(__doc__)
    return 1
  text = open(sys.argv[1], encoding="utf-8", errors="ignore").read()
  # モジュールごとのセル数と面積("=== 名前 ===" で区切る)
  mods = {}
  parts = re.split(r"^=== (.+) ===$", text, flags=re.M)
  for i in range(1, len(parts)-1, 2):
    name = parts[i].strip()
    body = parts[i+1]
    if( name=="design hierarchy" ):
      continue
    ca = re.search(r"Chip area for module .*: ([0-9.]+)\s*$", body, re.M)
    if( ca is None ):
      continue
    # セルの種類ごとの数(下の階層のモジュールのインスタンスは数えない)
    nc = 0
    cl = re.search(r"Number of cells:\s+\d+\n((?:\s{5}\S+\s+\d+\n)*)", body)
    if( cl ):
      for c in re.finditer(r"^\s+(\S+)\s+(\d+)$", cl.group(1), re.M):
        t = c.group(1)
        if( t.startswith("$paramod") or t.startswith("BAYER_EX") or t.startswith("\\") ):
          continue
        nc += int(c.group(2))
    mods[name] = (nc, float(ca.group(1)), 0)
  # 階層(インスタンスの数)
  hier = {}
  h = re.search(r"=== design hierarchy ===\n\n?(.*?)\n\n", text, re.S)
  top = None
  stack = []
  if( h ):
    for ln in h.group(1).split("\n"):
      mm = re.match(r"^(\s+)(\S+)\s*(\d*)\s*$", ln)
      if( not mm ):
        continue
      ind = len(mm.group(1))
      name = mm.group(2)
      cnt = int(mm.group(3)) if( mm.group(3) ) else 1
      while( len(stack)>0 and stack[-1][0]>=ind ):
        stack.pop()
      mult = cnt
      if( len(stack)>0 ):
        mult = cnt*stack[-1][1]
      else:
        top = name
      stack.append((ind, mult))
      hier[name] = hier.get(name, 0)+mult
  tot = re.search(r"Chip area for top module '([^']+)': ([0-9.]+)", text)
  total = float(tot.group(2)) if( tot ) else 0.0
  # 元のモジュール名でまとめる
  rows = {}
  for mod, (nc, area, macro) in mods.items():
    k = base_name(mod)
    n = hier.get(mod, hier.get("\\"+mod, 0))
    if( n==0 and mod.lstrip("\\")==(top or "").lstrip("\\") ):
      n = 1
    r = rows.setdefault(k, [0, 0, 0.0])
    r[0] += n
    r[1] += nc*n
    r[2] += area*n
  print("| モジュール | 個数 | セル数 | 面積 [um²] | 割合 |")
  print("|---|---:|---:|---:|---:|")
  for k in sorted(rows, key=lambda x: -rows[x][2]):
    n, nc, area = rows[k]
    pct = 100.0*area/total if( total>0 ) else 0.0
    print("| %s | %d | %d | %.1f | %.1f%% |" % (k, n, nc, area, pct))
  allc = sum(r[1] for r in rows.values())
  print("| 合計 | | %d | %.1f | 100.0%% |" % (allc, total))
  return 0


if( __name__=="__main__" ):
  sys.exit(main())
