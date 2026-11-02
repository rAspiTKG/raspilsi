#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BAYER_EX の Python のリファレンスモデル(仕様書 6章の式)

  python3 tools/bex_model.py check <ダンプ>...   スコアボードのダンプ(+BEX_DUMP)を照合する
  python3 tools/bex_model.py table                仕様書の計算例の表を出す

  ダンプの1行: cfg <bypass> <phase> <blc×4> <gain×4> in <sof> <eol> <eof> <画素×8> out <sof> <eol> <eof> <画素×8>
  画素の順は pix[0][0..3]、pix[1][0..3](y=0 が上のライン)。値はすべて10進
"""
import sys

PIX_MAX = 16383
SITE_NAME = ["R", "Gr", "Gb", "B"]
PHASE_NAME = ["RGGB", "GRBG", "GBRG", "BGGR"]


def site( phase, y, x ):
  """色の位置 0:R 1:Gr 2:Gb 3:B"""
  return (((y%2)^((phase>>1)&1))*2)+((x%2)^(phase&1))


def pix( cfg, y, x, p ):
  """1画素の補正。cfg = (bypass, phase, [blc×4], [gain×4])"""
  bypass, phase, blc, gain = cfg
  if( bypass ):
    return p
  s = site(phase, y, x)
  d = p-blc[s]
  if( d<=0 ):
    return 0
  t = ((d*gain[s])+2048)//4096
  if( t>PIX_MAX ):
    return PIX_MAX
  return t


def xfer( cfg, flags, px ):
  """1転送。px は8画素(pix[0][0..3]、pix[1][0..3])"""
  out = []
  for i in range(8):
    out.append(pix(cfg, i//4, i%4, px[i]))
  return list(flags), out


def parse_line( line ):
  t = line.split()
  if( (len(t)!=35)or(t[0]!="cfg")or(t[11]!="in")or(t[23]!="out") ):
    raise ValueError("書式が違う: %s" % line.strip())
  v = [int(x) for x in t[1:11]]
  cfg = (v[0], v[1], v[2:6], v[6:10])
  fin = [int(x) for x in t[12:15]]
  pin = [int(x) for x in t[15:23]]
  fout = [int(x) for x in t[24:27]]
  pout = [int(x) for x in t[27:35]]
  return cfg, fin, pin, fout, pout


def check( paths ):
  n = 0
  bad = 0
  for path in paths:
    with open(path, encoding="utf-8") as f:
      for line in f:
        if( line.strip()=="" ):
          continue
        cfg, fin, pin, fout, pout = parse_line(line)
        ef, ep = xfer(cfg, fin, pin)
        n += 1
        if( (ef!=fout)or(ep!=pout) ):
          bad += 1
          if( bad<=10 ):
            print("不一致 %s: 期待 %s %s / DUT %s %s" % (path, ef, ep, fout, pout))
  print("照合 %d 転送、不一致 %d" % (n, bad))
  return 0 if( (bad==0)and(n>0) ) else 1


def table():
  """仕様書の計算例(RGGB、黒レベル 100/200/300/400、ゲイン 1.5/1.0/1.0/2.0)"""
  cfg = (0, 0, [100, 200, 300, 400], [0x1800, 0x1000, 0x1000, 0x2000])
  rows = ["| 位置 pix[y][x] | 色 | 入力 p | 黒レベル | p − 黒レベル | ゲイン | 出力 q |", "|---|---|---:|---:|---:|---|---:|"]
  samples = [(0, 0, 1000), (0, 1, 1100), (1, 0, 3000), (1, 1, 3100), (0, 0, 50), (1, 1, 12000)]
  for y, x, p in samples:
    s = site(cfg[1], y, x)
    q = pix(cfg, y, x, p)
    g = cfg[3][s]
    rows.append("| [%d][%d] | %s | %d | %d | %d | 0x%04X(%.3f倍) | %d |" % (y, x, SITE_NAME[s], p, cfg[2][s],
                                                                          max(p-cfg[2][s], 0), g, g/4096.0, q))
  print("\n".join(rows))
  return 0


def main():
  if( len(sys.argv)<2 ):
    print(__doc__)
    return 1
  if( sys.argv[1]=="check" ):
    return check(sys.argv[2:])
  if( sys.argv[1]=="table" ):
    return table()
  print(__doc__)
  return 1


if( __name__=="__main__" ):
  sys.exit(main())
