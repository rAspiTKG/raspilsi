#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
RTL のポート宣言から端子表(Markdown)を作る

  python3 doc/tools/gen_pins.py <rtlディレクトリ> <出力ディレクトリ>

各モジュールについて <出力ディレクトリ>/<モジュール名>.md を作る。
列: 信号名 / 入出力 / 信号仕様 / ビット幅 / 極性
  - 入出力とビット幅は RTL から取る
  - data だけのインタフェースのポート(BAYER_EX_DATA_IF.src / .dst)は <ポート名>.data の1行にする
  - 信号仕様は下の DESC に書く。説明のないポートがあるとエラーにする
構造体のビットの並び(bayer4x2_t.md、cfg_t.md)と、インタフェースの表(BAYER_EX_DATA_IF.md)も作る。
"""
import os
import re
import sys

PIX_W = 14
GAIN_W = 16

# 構造体のフィールド(上位から順。SystemVerilog の packed struct と同じ順)
#   (名前, ビット幅, 説明)
BAYER4X2 = [("sof", 1, "フレームの最初の転送"), ("eol", 1, "2ラインの最後(右端)の転送"),
            ("eof", 1, "フレームの最後の転送")]
for _y in (1, 0):
  for _x in (3, 2, 1, 0):
    BAYER4X2.append(("pix[%d][%d]" % (_y, _x), PIX_W, "%sのライン(y=%d)の x=%d の画素" % ("下" if( _y==1 ) else "上", _y, _x)))

CFG = [("bypass", 1, "1: 補正しない(入力の画素をそのまま出す)"),
       ("phase", 2, "Bayer の並び 0:RGGB 1:GRBG 2:GBRG 3:BGGR")]
for _i, _n in ((3, "B"), (2, "Gb"), (1, "Gr"), (0, "R")):
  CFG.append(("blc[%d]" % _i, PIX_W, "%s の黒レベル(0〜16383)" % _n))
for _i, _n in ((3, "B"), (2, "Gb"), (1, "Gr"), (0, "R")):
  CFG.append(("gain[%d]" % _i, GAIN_W, "%s のゲイン(U4.12。0x1000 = 1.0倍、0〜15.9998倍)" % _n))

TYPE_W = {"bayer4x2_t": sum(f[1] for f in BAYER4X2), "cfg_t": sum(f[1] for f in CFG)}

# ----------------------------------------------------------------------------
# 信号仕様
# ----------------------------------------------------------------------------
COMMON = {
  "clk": "クロック。400MHz(すべての FF)",
  "rst_n": "リセット。非同期アサート・同期解除(同期化は外部)",
  "i_cfg": "設定 {bypass, phase, blc[3:0], gain[3:0]}(cfg_t)。コアの中にデータがないときだけ変える",
}

DESC = {
  "BAYER_EX": {
    "i_vld": "入力の data が有効",
    "o_busy": "入力を受け取れない(FF から出す。スキッドが埋まったとき 1)",
    "i_data": "入力の転送(bayer4x2_t。Bayer の水平4画素 × 垂直2ラインと sof / eol / eof)",
    "o_vld": "出力の data が有効(FF から出す)",
    "i_busy": "出力先が受け取れない",
    "o_data": "出力の転送(bayer4x2_t。画素は補正後、sof / eol / eof は入力のまま。FF から出す)",
  },
  "BAYER_EX_CORE": {
    "i_vld": "入力の data(i_pix.data)が有効",
    "o_busy": "入力を受け取れない(FF から出す。スキッドが埋まったとき 1)",
    "i_pix": "入力の転送(bayer4x2_t。Bayer の水平4画素 × 垂直2ラインと sof / eol / eof)",
    "o_vld": "出力の data(o_pix.data)が有効(FF から出す)",
    "i_busy": "出力先が受け取れない",
    "o_pix": "出力の転送(bayer4x2_t。画素は補正後、sof / eol / eof は入力のまま。FF から出す)",
  },
  "BAYER_EX_PIXCOR": {
    "i_en": "1: パイプラインを進める / 0: 全段を保持する(出力が止められているとき)",
    "i_cfg": "設定(cfg_t。CORE が FF で受け直したもの)",
    "i_vld": "i_data が有効(CORE の入力段)",
    "i_data": "入力の転送(bayer4x2_t)",
    "o_vld": "o_data が有効(レイテンシ2。FF から出す)",
    "o_data": "補正した転送(bayer4x2_t。FF から出す)",
  },
}


def parse_ports( path ):
  """モジュール名とポートの並び [(dir, type, range, name)] を返す"""
  txt = open(path, encoding="utf-8").read()
  m = re.search(r"^module\s+(\w+)", txt, re.M)
  if( m is None ):
    return None, []
  mod = m.group(1)
  body = txt[m.end():]
  ports = []
  for line in body.split("\n"):
    s = line.strip()
    if( s.startswith(");") ):
      if( len(ports)>0 ):
        break
      continue
    if( s.startswith("//") ):
      continue
    s = s.lstrip(",").strip()
    if( "//" in s ):
      s = s.split("//", 1)[0].strip()
    mi = re.match(r"^BAYER_EX_DATA_IF\.(src|dst)\s+(\w+)$", s)
    if( mi ):
      ports.append(("if_"+mi.group(1), "bayer4x2_t", "", mi.group(2)))
      continue
    mp = re.match(r"^(input|output)\s+(\w+)\s*(\[[^\]]+\])?\s*(\w+)$", s)
    if( mp ):
      ports.append((mp.group(1), mp.group(2), mp.group(3) or "", mp.group(4)))
  return mod, ports


def width_of( typ, rng ):
  if( typ in TYPE_W ):
    return "%d(%s)" % (TYPE_W[typ], typ), TYPE_W[typ]
  if( rng=="" ):
    return "1", 1
  hi, lo = rng[1:-1].split(":")
  w = int(hi)-int(lo)+1
  return str(w), w


def polarity( name, w ):
  if( name=="clk" ):
    return "立ち上がり"
  if( name.endswith("rst_n") ):
    return "Low"
  if( w==1 ):
    return "High"
  return "-"


def describe( mod, name ):
  mdesc = DESC.get(mod, {})
  if( name in mdesc ):
    return mdesc[name]
  if( name in COMMON ):
    return COMMON[name]
  raise KeyError("説明がない: %s.%s" % (mod, name))


def table( mod, ports ):
  rows = ["| 信号名 | 入出力 | 信号仕様 | ビット幅 | 極性 |", "|---|---|---|---|---|"]
  for d, typ, rng, name in ports:
    if( d.startswith("if_") ):
      src = (d=="if_src")
      rows.append("| %s.data | %s | %s | %d(bayer4x2_t) | - |" % (name, "出力" if( src ) else "入力", describe(mod, name),
                                                                 TYPE_W["bayer4x2_t"]))
      continue
    wtxt, w = width_of(typ, rng)
    rows.append("| %s | %s | %s | %s | %s |" % (name, "入力" if( d=="input" ) else "出力", describe(mod, name), wtxt,
                                               polarity(name, w)))
  return "\n".join(rows)+"\n"


def struct_table( fields ):
  """構造体のフィールドとビットの位置(上位から)"""
  rows = ["| フィールド | ビットの位置 | ビット幅 | 内容 |", "|---|---|---:|---|"]
  hi = sum(f[1] for f in fields)-1
  for name, w, desc in fields:
    lo = hi-w+1
    pos = "[%d]" % hi if( w==1 ) else "[%d:%d]" % (hi, lo)
    rows.append("| %s | %s | %d | %s |" % (name, pos, w, desc))
    hi = lo-1
  return "\n".join(rows)+"\n"


def if_table():
  rows = ["| メンバ | 型 | ビット幅 | modport src(送り側) | modport dst(受け側) | modport mon(監視) |",
          "|---|---|---:|---|---|---|",
          "| data | bayer4x2_t | %d | output | input | input |" % TYPE_W["bayer4x2_t"]]
  return "\n".join(rows)+"\n"


def main():
  if( len(sys.argv)<3 ):
    print(__doc__)
    return 1
  rtl = sys.argv[1]
  out = sys.argv[2]
  os.makedirs(out, exist_ok=True)
  n = 0
  for fn in sorted(os.listdir(rtl)):
    if( not(fn.endswith(".sv")) ):
      continue
    mod, ports = parse_ports(os.path.join(rtl, fn))
    if( (mod is None)or(len(ports)==0) ):
      continue
    with open(os.path.join(out, mod+".md"), "w", encoding="utf-8") as f:
      f.write(table(mod, ports))
    n += 1
  with open(os.path.join(out, "bayer4x2_t.md"), "w", encoding="utf-8") as f:
    f.write(struct_table(BAYER4X2))
  with open(os.path.join(out, "cfg_t.md"), "w", encoding="utf-8") as f:
    f.write(struct_table(CFG))
  with open(os.path.join(out, "BAYER_EX_DATA_IF.md"), "w", encoding="utf-8") as f:
    f.write(if_table())
  print("端子表 %d モジュール、構造体 2、インタフェース 1: %s" % (n, out))
  return 0


if( __name__=="__main__" ):
  sys.exit(main())
