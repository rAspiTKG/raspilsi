#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
仕様書を組み立てる

  python3 doc/tools/gen_spec.py

  入力: doc/spec/src/*.md(本文。ファイル名の順につなぐ)
        doc/spec/pins/<モジュール名>.md(端子表。gen_pins.py が作る)
        doc/spec/wave/<名前>.json / .svg(波形図。gen_waves.py と render_wavedrom.js が作る)
        rtl/BAYER2RGB_PKG.sv(ガンマの既定の折れ点)
  出力: doc/spec/BAYER2RGB_spec.md

  本文の中の置き換え
    {{PINS:<モジュール名>}}  端子表
    {{WAVE:<名前>}}          波形図(SVG)と WaveDrom の JSON(<details> の中の ```wavedrom)
    {{GAMMA_KNOTS}}          ガンマの既定の折れ点の表
"""
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SPEC = os.path.join(ROOT, "doc", "spec")

# ガンマの折れ点の入力値(BAYER2RGB_GAMMA と同じ)
GM_X = [0, 16, 32, 48]
for p in range(6, 14):
  for q in range(4):
    GM_X.append((1 << p)+(q << (p-2)))
GM_X.append(16384)


def wave_json( spec ):
  """1信号1行の JSON(WaveDrom のエディタにそのまま貼れる)"""
  sig = spec["signal"]
  out = ["{\"signal\": ["]
  for i, e in enumerate(sig):
    sep = "," if( i<len(sig)-1 ) else ""
    if( isinstance(e,list) ):
      out.append("  [" + json.dumps(e[0], ensure_ascii=False) + ",")
      for j, x in enumerate(e[1:]):
        out.append("    " + json.dumps(x, ensure_ascii=False) + ("," if( j<len(e)-2 ) else ""))
      out.append("  ]" + sep)
    else:
      out.append("  " + json.dumps(e, ensure_ascii=False) + sep)
  rest = [k for k in spec if( k!="signal" )]
  out.append("]" + ("," if( len(rest)>0 ) else ""))
  for i, k in enumerate(rest):
    out.append(" " + json.dumps(k) + ": " + json.dumps(spec[k], ensure_ascii=False) + ("," if( i<len(rest)-1 ) else ""))
  out.append("}")
  return "\n".join(out)


def rep_wave( m ):
  name = m.group(1)
  path = os.path.join(SPEC, "wave", name+".json")
  with open(path, encoding="utf-8") as f:
    spec = json.load(f)
  title = spec.get("head", {}).get("text", name)
  s = []
  s.append("![%s](wave/%s.svg)" % (title, name))
  s.append("")
  s.append("<details><summary>WaveDrom の記述(wave/%s.json)</summary>" % name)
  s.append("")
  s.append("```wavedrom")
  s.append(wave_json(spec))
  s.append("```")
  s.append("")
  s.append("</details>")
  return "\n".join(s)


def rep_pins( m ):
  name = m.group(1)
  path = os.path.join(SPEC, "pins", name+".md")
  with open(path, encoding="utf-8") as f:
    return f.read().rstrip("\n")


def gamma_knots():
  path = os.path.join(ROOT, "rtl", "BAYER2RGB_PKG.sv")
  with open(path, encoding="utf-8") as f:
    src = f.read()
  m = re.search(r"GM_SRGB\s*=\s*\{(.*?)\};", src, re.S)
  vals = [int(v) for v in re.findall(r"12'd(\d+)", m.group(1))]
  vals.reverse()            # 連結の最後が knot[0]
  if( len(vals)!=37 ):
    raise ValueError("GM_SRGB の数が37でない")
  rows = ["| 番号 | 入力 x(14bit) | 既定値(8.4固定小数点) | 8bit 換算 | 番号 | 入力 x(14bit) | 既定値(8.4固定小数点) | 8bit 換算 |",
          "|---:|---:|---:|---:|---:|---:|---:|---:|"]
  half = (len(vals)+1)//2
  for i in range(half):
    c = []
    for k in (i, i+half):
      if( k<len(vals) ):
        c += ["%d" % k, "%d" % GM_X[k], "%d" % vals[k], "%.2f" % (vals[k]/16.0)]
      else:
        c += ["", "", "", ""]
    rows.append("| " + " | ".join(c) + " |")
  return "\n".join(rows)


def main():
  srcdir = os.path.join(SPEC, "src")
  dst = os.path.join(SPEC, "BAYER2RGB_spec.md")
  parts = []
  for fn in sorted(os.listdir(srcdir)):
    if( fn.endswith(".md") ):
      with open(os.path.join(srcdir, fn), encoding="utf-8") as f:
        parts.append(f.read().rstrip("\n")+"\n")
  text = "\n".join(parts)
  text = re.sub(r"\{\{WAVE:([A-Za-z0-9_]+)\}\}", rep_wave, text)
  text = re.sub(r"\{\{PINS:([A-Za-z0-9_]+)\}\}", rep_pins, text)
  text = text.replace("{{GAMMA_KNOTS}}", gamma_knots())
  left = re.findall(r"\{\{[^}]*\}\}", text)
  if( len(left)>0 ):
    raise ValueError("置き換えていない記述: %s" % left)
  zen = re.search("[\uff08\uff09]", text)   # 全角の括弧
  if( zen ):
    raise ValueError("全角の括弧がある")
  with open(dst, "w", encoding="utf-8") as f:
    f.write(text)
  print("written:", dst)
  return 0


if( __name__=="__main__" ):
  sys.exit(main())
