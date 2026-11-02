#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
検証環境が出したフレーム(+B2R_DUMP=<接頭辞>)を Python モデルと照合する

  python3 check_dumps.py 'dump/*.cfg.json'

各フレームについて次の3つが一致することを確かめる
  DUT の出力(.dut.hex) / SVモデルの出力(.ref.hex) / Pythonモデルの出力
"""
import glob
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from b2r_model import eff_h, eff_w, load_cfg, run  # noqa: E402


def read_hex( path ):
  with open(path, encoding="ascii") as f:
    txt = f.read().replace("\n", "")
  return np.frombuffer(bytes.fromhex(txt), dtype=np.uint8)


def first_diff( a, b, w ):
  idx = int(np.nonzero(a!=b)[0][0])
  y = idx//(w*3)
  x = (idx%(w*3))//3
  return "y=%d x=%d %s" % (y, x, "RGB"[idx%3])


def main():
  pattern = sys.argv[1] if( len(sys.argv)>1 ) else "dump/*.cfg.json"
  files = sorted(glob.glob(pattern))
  if( len(files)==0 ):
    print("照合するファイルがない: %s" % pattern)
    return 1
  n_ng = 0
  for cf in files:
    base = cf[:-len(".cfg.json")]
    cfg = load_cfg(cf)
    w = eff_w(cfg["width"])
    h = eff_h(cfg["height"])
    raw = None
    if( not(int(cfg["tpg_en"])) ):
      raw = read_hex(base+".in.hex").view("<u2").reshape(h, w)
    py = run(raw, cfg).reshape(-1)
    dut = read_hex(base+".dut.hex")
    ref = read_hex(base+".ref.hex")
    msg = []
    if( (dut.size!=py.size)or(ref.size!=py.size) ):
      msg.append("サイズが違う dut=%d ref=%d py=%d" % (dut.size, ref.size, py.size))
    else:
      if( not(np.array_equal(py,ref)) ):
        msg.append("SVモデルと不一致 %d バイト (%s)" % (int(np.count_nonzero(py!=ref)), first_diff(py, ref, w)))
      if( not(np.array_equal(py,dut)) ):
        msg.append("DUTと不一致 %d バイト (%s)" % (int(np.count_nonzero(py!=dut)), first_diff(py, dut, w)))
    if( len(msg)==0 ):
      print("OK  %s (%dx%d)" % (os.path.basename(base), w, h))
    else:
      n_ng += 1
      print("NG  %s (%dx%d): %s" % (os.path.basename(base), w, h, " / ".join(msg)))
  print("照合 %d フレーム、不一致 %d" % (len(files), n_ng))
  return 0 if( n_ng==0 ) else 1


if( __name__=="__main__" ):
  sys.exit(main())
