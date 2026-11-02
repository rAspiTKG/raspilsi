#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
仕様書を組み立てる

  python3 doc/tools/gen_spec.py

  入力: doc/spec/src/*.md(本文。ファイル名の順につなぐ)
        doc/spec/pins/<名前>.md(端子表・構造体の表。gen_pins.py が作る)
        doc/spec/wave/<名前>.json / .svg(波形図。gen_waves.py と render_wavedrom.js が作る)
  出力: doc/spec/BAYER_EX_spec.md

  本文の中の置き換え
    {{PINS:<名前>}}   端子表(モジュール名)、構造体のビットの並び(bayer4x2_t、cfg_t)、インタフェースの表
    {{WAVE:<名前>}}   波形図(SVG)と WaveDrom の JSON(<details> の中の ```wavedrom)
    {{CALC_TABLE}}    計算例の表(tools/bex_model.py の table)
"""
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SPEC = os.path.join(ROOT, "doc", "spec")

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


def calc_table():
  """tools/bex_model.py の計算例の表"""
  sys.path.insert(0, os.path.join(ROOT, "tools"))
  import bex_model   # noqa: E402
  import io
  import contextlib
  buf = io.StringIO()
  with contextlib.redirect_stdout(buf):
    bex_model.table()
  return buf.getvalue().rstrip("\n")


def main():
  srcdir = os.path.join(SPEC, "src")
  dst = os.path.join(SPEC, "BAYER_EX_spec.md")
  parts = []
  for fn in sorted(os.listdir(srcdir)):
    if( fn.endswith(".md") ):
      with open(os.path.join(srcdir, fn), encoding="utf-8") as f:
        parts.append(f.read().rstrip("\n")+"\n")
  text = "\n".join(parts)
  text = re.sub(r"\{\{WAVE:([A-Za-z0-9_]+)\}\}", rep_wave, text)
  text = re.sub(r"\{\{PINS:([A-Za-z0-9_]+)\}\}", rep_pins, text)
  text = text.replace("{{CALC_TABLE}}", calc_table())
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
