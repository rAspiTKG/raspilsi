#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Liberty を Yosys / ABC で読める形にそろえ、1つにまとめる

  python3 tools/liberty_prep.py --out merged.lib --name asap7_merged lib1.lib.gz lib2.lib ...
  python3 tools/liberty_prep.py --outdir <ディレクトリ> lib1.lib.gz lib2.lib ...   (1つずつ変換)

  - .gz は展開する
  - original_pin を含む行をコメントにする(yosys-abc が読めないため)
  - 「: !A ;」のような引用符のない関数を引用符で囲む
  - --out: 最初のファイルのヘッダ(cell より前)と、全ファイルの cell をつないで1つにする
           (ABC に渡すライブラリは1つだけなので)
"""
import argparse
import gzip
import os
import re
import sys


def load( path ):
  if( path.endswith(".gz") ):
    with gzip.open(path, "rt", encoding="utf-8", errors="ignore") as f:
      text = f.read()
  else:
    with open(path, encoding="utf-8", errors="ignore") as f:
      text = f.read()
  text = text.encode("ascii", "ignore").decode("ascii")
  text = re.sub(r"(.*original_pin.*)", r"/* \1 */;", text)
  text = re.sub(r":\s+(!.*)\s+;", r': "\1" ;', text)
  return text


def split_cells( text ):
  """ヘッダ(最初の cell の前)と cell のブロックの並びに分ける"""
  lines = text.split("\n")
  head = []
  cells = []
  depth = 0
  cur = None
  for ln in lines:
    if( cur is None ):
      is_cell = re.match(r"^\s*cell\s*\(", ln)
      if( is_cell ):
        cur = [ln]
        depth = ln.count("{")-ln.count("}")
      elif( len(cells)==0 ):
        head.append(ln)
      continue
    cur.append(ln)
    depth += ln.count("{")-ln.count("}")
    if( depth<=0 ):
      cells.append("\n".join(cur))
      cur = None
  return head, cells


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("libs", nargs="+")
  ap.add_argument("--out", help="まとめた Liberty の出力先")
  ap.add_argument("--name", default="merged", help="まとめたライブラリの名前")
  ap.add_argument("--outdir", help="1つずつ変換したファイルの出力先")
  a = ap.parse_args()
  if( a.outdir ):
    os.makedirs(a.outdir, exist_ok=True)
    for p in a.libs:
      base = os.path.basename(p)
      if( base.endswith(".gz") ):
        base = base[:-3]
      with open(os.path.join(a.outdir, base), "w", encoding="ascii") as f:
        f.write(load(p))
  if( a.out ):
    head = None
    allcells = []
    for p in a.libs:
      h, cells = split_cells(load(p))
      if( head is None ):
        head = h
      allcells += cells
    out = []
    for ln in head:
      m = re.match(r"^(\s*)library\s*\(", ln)
      if( m ):
        out.append("%slibrary (%s) {" % (m.group(1), a.name))
      else:
        out.append(ln)
    out += allcells
    out.append("}")
    with open(a.out, "w", encoding="ascii") as f:
      f.write("\n".join(out)+"\n")
    print("%s: セル %d 個" % (a.out, len(allcells)))
  return 0


if( __name__=="__main__" ):
  sys.exit(main())
