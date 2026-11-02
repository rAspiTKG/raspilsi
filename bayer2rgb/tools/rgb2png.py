#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
RGB888(R,G,B順、余白なし)を PNG にする。メモリの形式のまま(ライン間隔あり)も読める

  python3 rgb2png.py --in out.rgb --size 640x480 --png out.png [--stride 1920]
  python3 rgb2png.py --hex dump/x_f0.dut.hex --size 64x32 --png dut.png
"""
import argparse
import sys

import numpy as np


def main():
  ap = argparse.ArgumentParser(description="RGB888 → PNG")
  ap.add_argument("--in", dest="inp", help="バイナリ")
  ap.add_argument("--hex", help="16進テキスト(検証環境のダンプ)")
  ap.add_argument("--size", required=True, help="幅x高さ")
  ap.add_argument("--stride", type=int, default=0, help="ライン間隔(バイト)。0なら幅×3")
  ap.add_argument("--png", required=True)
  args = ap.parse_args()
  w, h = [int(v) for v in args.size.lower().split("x")]
  stride = args.stride if( args.stride>0 ) else w*3
  if( args.hex ):
    with open(args.hex, encoding="ascii") as f:
      d = np.frombuffer(bytes.fromhex(f.read().replace("\n", "")), dtype=np.uint8)
  else:
    d = np.fromfile(args.inp, dtype=np.uint8)
  if( d.size<(stride*(h-1))+(w*3) ):
    print("データが足りない")
    return 1
  rows = [d[y*stride:(y*stride)+(w*3)] for y in range(h)]
  img = np.stack(rows).reshape(h, w, 3)
  from PIL import Image
  Image.fromarray(img, "RGB").save(args.png)
  print("%s: %dx%d" % (args.png, w, h))
  return 0


if( __name__=="__main__" ):
  sys.exit(main())
