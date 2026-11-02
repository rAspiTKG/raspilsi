#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BAYER2RGB のリファレンスモデル(Python版、ビット一致)

RTL と検証環境のSVモデル(tb/uvm/b2r_ref_model.svh)と同じ整数演算で、
Bayer画像(16bit格納・下位14bitが画素)から RGB888(R,G,B順)を作る。

使い方
  python3 b2r_model.py --in in.raw --cfg cfg.json --out out.rgb [--png out.png]
  python3 b2r_model.py --in big.raw --raw-size 4000x3000 --crop 3840x2160 --cfg cfg.json --out out.rgb

  in.raw   : 16bitリトルエンディアン、ライン間の余白なし(幅×高さ×2バイト)
  cfg.json : 設定(キーは下の DEFAULT_CFG と同じ。省略したキーはリセット値)
  out.rgb  : RGB888、ライン間の余白なし(幅×高さ×3バイト)
"""
import argparse
import json
import sys

import numpy as np

# sRGBの折れ点(RTLのリセット値と同じ)
GM_SRGB = [0, 51, 103, 154, 203, 244, 281, 315, 346, 401, 451, 495, 537, 611, 677, 736, 791, 890, 978,
           1058, 1131, 1264, 1381, 1487, 1585, 1762, 1919, 2061, 2191, 2427, 2636, 2826, 3000, 3315, 3594,
           3847, 4080]

# リセット値
DEFAULT_CFG = {
  "width": 3840, "height": 2160, "phase": 0,
  "blc_en": 1, "wb_en": 1, "fcs_en": 1, "gamma_en": 1,
  "bypass": 0, "tpg_en": 0, "tpg_sel": 0, "tpg_color": 0,
  "blc": [0, 0, 0, 0], "wbg": [4096, 4096, 4096, 4096],
  "fcs_th": 256, "fcs_gain": 16, "gm_knot": GM_SRGB,
}

MAX_W = 3840
MAX_H = 2160
MIN_W = 16
MIN_H = 16


def eff_w( w ):
  """実効幅: [16, 3840] に収めて8画素単位に切り捨てる"""
  w = min(max(int(w), MIN_W), MAX_W)
  return w & ~7


def eff_h( h ):
  """実効高さ: [16, 2160] に収めて偶数に切り捨てる"""
  h = min(max(int(h), MIN_H), MAX_H)
  return h & ~1


def load_cfg( path ):
  cfg = dict(DEFAULT_CFG)
  if( path ):
    with open(path, encoding="utf-8") as f:
      cfg.update(json.load(f))
  return cfg


def gamma( x, knots, en ):
  """14bit → 8bit(折れ線ガンマまたは線形)"""
  x = x.astype(np.int64)
  if( not(en) ):
    return np.minimum((x+32)>>6, 255)
  seg = x>>4
  frac = (x&15)<<7
  for p in range(6, 14):
    m = (x>>p)==1
    seg = np.where(m, 4+(4*(p-6))+((x>>(p-2))&3), seg)
    frac = np.where(m, (x&((1<<(p-2))-1))<<(13-p), frac)
  k = np.asarray(knots, dtype=np.int64)
  k0 = k[seg]
  k1 = k[seg+1]
  y = k0+((((k1-k0)*frac)+1024)>>11)
  y = np.maximum(y, 0)
  return np.minimum((y+8)>>4, 255)


def test_pattern( cfg, w, h ):
  """テストパターン(入力は使わない)"""
  yy, xx = np.mgrid[0:h, 0:w].astype(np.int64)
  sel = int(cfg["tpg_sel"])
  out = np.zeros((h, w, 3), dtype=np.int64)
  if( sel==0 ):
    bw = w>>3
    bar = np.zeros_like(xx)
    for j in range(1, 8):
      bar = np.where(xx>=(j*bw), j, bar)
    out[..., 0] = np.where((bar&2)!=0, 0, 255)
    out[..., 1] = np.where((bar&4)!=0, 0, 255)
    out[..., 2] = np.where((bar&1)!=0, 0, 255)
  elif( sel==1 ):
    v = (xx>>4)&255
    out[..., 0] = v
    out[..., 1] = v
    out[..., 2] = v
  elif( sel==2 ):
    v = np.where((((xx>>6)^(yy>>6))&1)!=0, 255, 0)
    out[..., 0] = v
    out[..., 1] = v
    out[..., 2] = v
  else:
    c = int(cfg["tpg_color"])
    out[..., 0] = (c>>16)&255
    out[..., 1] = (c>>8)&255
    out[..., 2] = c&255
  return out.astype(np.uint8)


def run( raw16, cfg ):
  """raw16: 高さ×幅の uint16(実効サイズ)。戻り値: 高さ×幅×3 の uint8"""
  w = eff_w(cfg["width"])
  h = eff_h(cfg["height"])
  if( int(cfg["tpg_en"]) ):
    return test_pattern(cfg, w, h)
  if( raw16.shape!=(h,w) ):
    raise ValueError("入力のサイズ %s が実効サイズ %dx%d と違う" % (raw16.shape, w, h))
  ph = int(cfg["phase"])
  p = (raw16.astype(np.int64))&0x3FFF
  yy, xx = np.mgrid[0:h, 0:w]
  site = (((yy&1)^((ph>>1)&1))*2)+((xx&1)^(ph&1))
  # ---- BLC と WB
  if( int(cfg["blc_en"]) ):
    lvl = np.asarray(cfg["blc"], dtype=np.int64)[site]
    p = np.where(p>lvl, p-lvl, 0)
  if( int(cfg["wb_en"]) ):
    g = np.asarray(cfg["wbg"], dtype=np.int64)[site]
  else:
    g = 4096
  q = np.minimum(((p*g)+2048)>>12, 16383)
  # ---- 3×3 の窓(上下左右の端は reflect-101)
  qp = np.pad(q, 1, mode="reflect")
  c = qp[1:-1, 1:-1]
  n = qp[0:-2, 1:-1]
  s = qp[2:, 1:-1]
  wv = qp[1:-1, 0:-2]
  e = qp[1:-1, 2:]
  nw = qp[0:-2, 0:-2]
  ne = qp[0:-2, 2:]
  sw = qp[2:, 0:-2]
  se = qp[2:, 2:]
  # ---- バイリニア補間とエッジ量
  g4 = (n+s+wv+e+2)>>2
  d4 = (nw+ne+sw+se+2)>>2
  h2 = (wv+e+1)>>1
  v2 = (n+s+1)>>1
  erb = np.maximum(np.abs(n-s), np.abs(wv-e))
  eg = np.maximum(np.abs(nw-se), np.abs(ne-sw))
  if( int(cfg["bypass"]) ):
    rr = c
    gg = c
    bb = c
    edg = np.zeros_like(c)
  else:
    rr = np.select([site==0, site==1, site==2], [c, h2, v2], d4)
    gg = np.select([site==0, site==3], [g4, g4], c)
    bb = np.select([site==0, site==1, site==2], [d4, v2, h2], c)
    edg = np.where((site==0)|(site==3), erb, eg)
  # ---- エッジ部の彩度抑制
  yl = (rr+(2*gg)+bb+2)>>2
  th = int(cfg["fcs_th"])
  ex = np.where(edg>th, edg-th, 0)
  t = (ex*int(cfg["fcs_gain"]))>>6
  if( (not(int(cfg["fcs_en"])))or(int(cfg["bypass"])) ):
    k = np.full_like(t, 256)
  else:
    k = np.where(t>=256, 0, 256-t)
  out = np.zeros((h, w, 3), dtype=np.int64)
  for ch, xv in enumerate((rr, gg, bb)):
    v = yl+((((xv-yl)*k)+128)>>8)
    v = np.clip(v, 0, 16383)
    out[..., ch] = gamma(v, cfg["gm_knot"], int(cfg["gamma_en"]))
  return out.astype(np.uint8)


def read_raw16( path, w, h ):
  d = np.fromfile(path, dtype="<u2")
  if( d.size<(w*h) ):
    raise ValueError("%s の大きさが足りない (%d < %d)" % (path, d.size, w*h))
  return d[:w*h].reshape(h, w)


def main():
  ap = argparse.ArgumentParser(description="BAYER2RGB リファレンスモデル(Python)")
  ap.add_argument("--in", dest="inp", help="入力(16bit LE の Bayer、余白なし)")
  ap.add_argument("--cfg", help="設定(JSON)")
  ap.add_argument("--out", required=True, help="出力(RGB888、余白なし)")
  ap.add_argument("--png", help="出力をPNGでも保存する")
  ap.add_argument("--raw-size", help="入力ファイルのサイズ 幅x高さ(実効サイズと違うとき)")
  ap.add_argument("--crop", help="入力から切り出すサイズ 幅x高さ(左上から。設定の幅・高さもこれにする)")
  args = ap.parse_args()
  cfg = load_cfg(args.cfg)
  if( args.crop ):
    cw, chh = [int(v) for v in args.crop.lower().split("x")]
    cfg["width"] = cw
    cfg["height"] = chh
  w = eff_w(cfg["width"])
  h = eff_h(cfg["height"])
  raw = None
  if( not(int(cfg["tpg_en"])) ):
    if( not(args.inp) ):
      ap.error("--in が必要(テストパターン以外)")
    if( args.raw_size ):
      rw, rh = [int(v) for v in args.raw_size.lower().split("x")]
    else:
      rw, rh = w, h
    raw = read_raw16(args.inp, rw, rh)
    if( (rw<w)or(rh<h) ):
      ap.error("入力 %dx%d が実効サイズ %dx%d より小さい" % (rw, rh, w, h))
    raw = raw[:h, :w]
  out = run(raw, cfg)
  out.tofile(args.out)
  if( args.png ):
    from PIL import Image
    Image.fromarray(out, "RGB").save(args.png)
  print("%s: %dx%d" % (args.out, w, h))
  return 0


if( __name__=="__main__" ):
  sys.exit(main())
