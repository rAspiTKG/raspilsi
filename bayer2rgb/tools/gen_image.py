#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
合成したBayer画像を作る(16bitリトルエンディアン、下位14bitが画素、ライン間の余白なし)

  python3 gen_image.py --size 640x480 --kind blocks --phase 0 --out in.raw [--png preview.png]
  python3 gen_image.py --from-png scene.png --phase 0 --out in.raw   (RGB画像をBayerに間引く)

kind
  noise    一様乱数              gradient なめらかなグラデーション
  blocks   色付きの矩形(偽色の確認)  stripes  細かい縞・市松(高周波)
  extreme  0 / 16383 / 乱数 の混在   dark     暗部(黒レベル付近)
  bright   明部(WBでクリップ)       zoneplate 同心円の縞(エイリアスの確認)
"""
import argparse
import sys

import numpy as np

KINDS = ["noise", "gradient", "blocks", "stripes", "extreme", "dark", "bright", "zoneplate"]


def mosaic( rgb, phase ):
  """RGB(14bit、高さ×幅×3)を Bayer に間引く"""
  h, w, _ = rgb.shape
  yy, xx = np.mgrid[0:h, 0:w]
  site = (((yy&1)^((phase>>1)&1))*2)+((xx&1)^(phase&1))
  ch = np.select([site==0, site==3], [0, 2], 1)
  return np.take_along_axis(rgb, ch[..., None], axis=2)[..., 0]


def make( kind, w, h, phase, rng ):
  yy, xx = np.mgrid[0:h, 0:w].astype(np.int64)
  if( kind=="noise" ):
    v = rng.integers(0, 16384, size=(h, w))
  elif( kind=="gradient" ):
    v = ((xx*12000)//w)+((yy*4000)//h)
  elif( kind=="blocks" ):
    bs = 8*int(rng.integers(1, 5))
    col = rng.integers(0, 16384, size=(64, 3))
    idx = (((yy//bs)*7)+((xx//bs)*3))%64
    v = mosaic(col[idx], phase)
  elif( kind=="stripes" ):
    sel = (xx//64)%3
    v = np.select([sel==0, sel==1],
                  [np.where((xx&1)!=0, 15000, 1000), np.where(((xx^yy)&1)!=0, 14000, 500)],
                  np.where((((xx>>1)^(yy>>1))&1)!=0, 16000, 2000))
  elif( kind=="extreme" ):
    r = rng.integers(0, 3, size=(h, w))
    v = np.select([r==0, r==1], [0, 16383], rng.integers(0, 16384, size=(h, w)))
  elif( kind=="dark" ):
    v = rng.integers(0, 601, size=(h, w))
  elif( kind=="bright" ):
    v = rng.integers(12000, 16384, size=(h, w))
  elif( kind=="zoneplate" ):
    cx = w/2.0
    cy = h/2.0
    r2 = ((xx-cx)**2)+((yy-cy)**2)
    k = np.pi/max(w, h)
    g = (np.cos(k*r2*0.5)+1.0)*0.5
    v = (g*16383.0).astype(np.int64)
  else:
    raise ValueError(kind)
  return np.clip(v, 0, 16383).astype(np.uint16)


def main():
  ap = argparse.ArgumentParser(description="合成Bayer画像の生成")
  ap.add_argument("--size", default="256x64", help="幅x高さ")
  ap.add_argument("--kind", default="blocks", choices=KINDS)
  ap.add_argument("--phase", type=int, default=0, help="0:RGGB 1:GRBG 2:GBRG 3:BGGR")
  ap.add_argument("--from-png", help="RGB画像(PNGなど)をBayerに間引いて使う")
  ap.add_argument("--seed", type=int, default=1)
  ap.add_argument("--garbage", action="store_true", help="上位2bitに乱数を入れる(DUTが無視することの確認)")
  ap.add_argument("--out", required=True)
  ap.add_argument("--png", help="Bayer画像をグレーのPNGでも保存する")
  args = ap.parse_args()
  rng = np.random.default_rng(args.seed)
  if( args.from_png ):
    from PIL import Image
    rgb = np.asarray(Image.open(args.from_png).convert("RGB"), dtype=np.int64)
    rgb = (rgb*16383)//255
    h = rgb.shape[0]&~1
    w = rgb.shape[1]&~7
    img = mosaic(rgb[:h, :w], args.phase).astype(np.uint16)
  else:
    w, h = [int(v) for v in args.size.lower().split("x")]
    img = make(args.kind, w, h, args.phase, rng)
  if( args.garbage ):
    img = img|(rng.integers(0, 4, size=img.shape).astype(np.uint16)<<14)
  img.astype("<u2").tofile(args.out)
  if( args.png ):
    from PIL import Image
    Image.fromarray(((img&0x3FFF)>>6).astype(np.uint8), "L").save(args.png)
  print("%s: %dx%d" % (args.out, img.shape[1], img.shape[0]))
  return 0


if( __name__=="__main__" ):
  sys.exit(main())
