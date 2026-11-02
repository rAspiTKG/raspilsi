#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
シミュレーションの波形(VCD)から、ブロックごとの WaveDrom の JSON を作る

  cd sim
  make build TRACE=vcd
  ./obj_core_vcd/Vtb_top +UVM_TESTNAME=bex_wave_test +verilator+seed+1 +WAVES
  python3 ../doc/tools/gen_waves.py waves.vcd ../doc/spec/wave

出力: <出力ディレクトリ>/<名前>.json(WaveDrom)
      SVG にするには doc/tools/render_wavedrom.js を使う(node と wavedrom パッケージが必要)
"""
import bisect
import json
import os
import re
import sys

P = "tb_top.u_dut."
CLK = "tb_top.clk"

# ============================================================================
# VCD の読み込み
# ============================================================================
class Vcd:
  def __init__( self, path ):
    self.path = path
    self.vars = {}      # 階層名 → (id, 幅)
    self.changes = {}   # id → ([時刻], [値])
    self._read_header()

  def _read_header( self ):
    scope = []
    with open(self.path, encoding="ascii", errors="replace") as f:
      for line in f:
        tok = line.split()
        if( len(tok)==0 ):
          continue
        if( tok[0]=="$scope" ):
          scope.append(tok[2])
        elif( tok[0]=="$upscope" ):
          scope.pop()
        elif( tok[0]=="$var" ):
          self.vars[".".join(scope+[tok[4]])] = (tok[3], int(tok[2]))
        elif( tok[0]=="$enddefinitions" ):
          break

  def load( self, names ):
    """names の信号の変化を読む"""
    want = {}
    for n in names:
      if( n not in self.vars ):
        raise KeyError("信号が見つからない: %s" % n)
      vid = self.vars[n][0]
      want[vid] = True
      self.changes.setdefault(vid, ([], []))
    t = 0
    body = False
    with open(self.path, encoding="ascii", errors="replace") as f:
      for line in f:
        if( not(body) ):
          body = line.startswith("$enddefinitions")
          continue
        line = line.strip()
        if( line=="" ):
          continue
        c = line[0]
        if( c=="#" ):
          t = int(line[1:])
        elif( c in "bB" ):
          val, vid = line[1:].split()
          if( vid in want ):
            self.changes[vid][0].append(t)
            self.changes[vid][1].append(val)
        elif( c in "01xXzZ" ):
          vid = line[1:]
          if( vid in want ):
            self.changes[vid][0].append(t)
            self.changes[vid][1].append(c)

  def ivalue( self, name, t ):
    """時刻 t の変化を反映した後の値(不定なら None)"""
    ts, vs = self.changes[self.vars[name][0]]
    i = bisect.bisect_right(ts, t)-1
    if( i<0 ):
      return None
    v = vs[i]
    xz = re.search(r"[xXzZ]", v)
    if( xz ):
      return None
    return int(v, 2)

  def rising( self, clk, t0=0, t1=1 << 62 ):
    ts, vs = self.changes[self.vars[clk][0]]
    out = []
    prev = "0"
    for t, v in zip(ts, vs):
      if( (v=="1")and(prev!="1")and(t>=t0)and(t<t1) ):
        out.append(t)
      prev = v
    return out


# ============================================================================
# 波形の行
# ============================================================================
class Row:
  """kind: bit / hex / dec / seq(値ごとに prefix+番号) / enum
  clk: この行を標本化するクロック(既定は図の基準クロック)
  valid: この信号が0のときは x で表示する
  invalid: この信号が1のときは x で表示する(掃き出しステップの画素など)
  each: 1クロックごとに別の値として描く(同じ値が続いてもまとめない。パイプラインの各ステップ用)"""

  def __init__( self, label, name, kind="bit", clk=None, valid=None, prefix="D", enum=None, digits=0, bits=None,
                invalid=None, each=False ):
    self.label = label
    self.name = name
    self.kind = kind
    self.clk = clk
    self.valid = valid
    self.prefix = prefix
    self.enum = enum
    self.digits = digits
    self.bits = bits
    self.invalid = invalid
    self.each = each


class Wave:
  def __init__( self, name, title, clk, anchor, ncyc, rows, back=2, note="", hscale=1 ):
    self.hscale = hscale
    self.name = name
    self.title = title
    self.clk = clk
    self.anchor = anchor     # (信号, 値, 何回目か) → その立ち上がり(値になった)時刻
    self.ncyc = ncyc
    self.rows = rows         # Row または ("グループ名", [Row...])
    self.back = back
    self.note = note


def all_rows( w ):
  for r in w.rows:
    if( isinstance(r,tuple) ):
      for x in r[1]:
        yield x
    else:
      yield r


def anchor_time( vcd, anchor ):
  sig, val, nth = anchor
  ts, vs = vcd.changes[vcd.vars[sig][0]]
  cnt = 0
  prev = None
  for t, v in zip(ts, vs):
    xz = re.search(r"[xXzZ]", v)
    iv = None if( xz ) else int(v, 2)
    if( (iv==val)and(prev!=val)and(t>0) ):
      if( cnt==nth ):
        return t
      cnt += 1
    prev = iv
  raise ValueError("アンカーが見つからない: %s=%d (%d回目)" % (sig, val, nth))


def fmt( r, v, seqmap, width=0 ):
  if( v is None ):
    return None
  if( r.kind=="hex" ):
    s = "%x" % v
    if( r.bits is not None ):
      s = s.zfill((r.bits[0]-r.bits[1]+4)//4)
    else:
      s = s.zfill((width+3)//4)
    if( (r.digits>0)and(len(s)>r.digits) ):
      s = "…"+s[-r.digits:]
    return s
  if( r.kind=="dec" ):
    return "%d" % v
  if( r.kind=="enum" ):
    return r.enum.get(v, "%d" % v)
  if( r.kind=="seq" ):
    if( v not in seqmap ):
      seqmap[v] = "%s%d" % (r.prefix, len(seqmap))
    return seqmap[v]
  return "%d" % v


def sample_row( vcd, r, edges, seqmap ):
  """seqmap: 図の中で共有する(同じ値には同じラベルを付け、入力と出力の対応がわかるようにする)"""
  wave = ""
  data = []
  prev = None
  for t in edges:
    v = vcd.ivalue(r.name, t)
    if( (v is not None)and(r.bits is not None) ):
      v = (v>>r.bits[1])&((1<<(r.bits[0]-r.bits[1]+1))-1)
    if( r.valid is not None ):
      vv = vcd.ivalue(r.valid, t)
      if( not(vv) ):
        v = None
    if( r.invalid is not None ):
      vv = vcd.ivalue(r.invalid, t)
      if( vv ):
        v = None
    if( r.kind=="bit" ):
      ch = "x" if( v is None ) else ("1" if( v ) else "0")
      wave += "." if( ch==prev ) else ch
      prev = ch
      continue
    txt = fmt(r, v, seqmap, vcd.vars[r.name][1])
    key = "x" if( txt is None ) else "="+txt
    if( (key==prev)and(not(r.each)or(txt is None)) ):
      wave += "."
    elif( txt is None ):
      wave += "x"
    else:
      wave += "="
      data.append(txt)
    prev = key
  return wave, data


def build( vcd, w ):
  t_anchor = anchor_time(vcd, w.anchor)
  base = vcd.rising(w.clk)
  i0 = max(0, bisect.bisect_left(base, t_anchor)-w.back)
  edges = base[i0:i0+w.ncyc]
  per_base = base[1]-base[0]
  t_end = edges[-1]+per_base
  out = []
  seqmap = {}
  clocks = [w.clk]
  for r in all_rows(w):
    if( (r.clk is not None)and(r.clk not in clocks) ):
      clocks.append(r.clk)
  # クロックの行
  for ck in clocks:
    ce = [t for t in vcd.rising(ck) if( (t>=edges[0]-per_base)and(t<t_end) )]
    if( ck==w.clk ):
      out.append({"name": ck.split(".")[-1], "wave": "p"+("."*(len(edges)-1))})
    else:
      per = vcd.rising(ck)[1]-vcd.rising(ck)[0]
      ratio = int(round(per/per_base))
      ce = [t for t in ce if( (t>=edges[0])and(t+per<=t_end) )]
      out.append({"name": ck.split(".")[-1], "wave": "p"+("."*(len(ce)-1)), "period": ratio,
                  "phase": -round((ce[0]-edges[0])/per_base, 2) if( len(ce)>0 ) else 0})

  def one( r ):
    if( (r.clk is None)or(r.clk==w.clk) ):
      wv, data = sample_row(vcd, r, edges, seqmap)
      d = {"name": r.label, "wave": wv}
    else:
      per = vcd.rising(r.clk)[1]-vcd.rising(r.clk)[0]
      ratio = int(round(per/per_base))
      ce = [t for t in vcd.rising(r.clk) if( (t>=edges[0])and(t+per<=t_end) )]
      wv, data = sample_row(vcd, r, ce, seqmap)
      d = {"name": r.label, "wave": wv, "period": ratio,
           "phase": -round((ce[0]-edges[0])/per_base, 2) if( len(ce)>0 ) else 0}
    if( len(data)>0 ):
      d["data"] = data
    return d

  for r in w.rows:
    if( isinstance(r,tuple) ):
      out.append({})
      grp = [r[0]]
      for x in r[1]:
        grp.append(one(x))
      out.append(grp)
    else:
      out.append(one(r))
  spec = {"signal": out, "head": {"text": w.title}, "config": {"hscale": w.hscale}}
  if( w.note ):
    spec["foot"] = {"text": w.note}
  return spec



# ============================================================================
# 図の定義(bex_wave_test の波形を前提にする。DUT は BAYER_EX_CORE)
# ============================================================================
def R( label, name, kind="bit", **kw ):
  return Row(label, P+name, kind, **kw)


def T( label, name, kind="bit", **kw ):
  """tb_top の信号(DUT の外)"""
  return Row(label, "tb_top."+name, kind, **kw)


def waves():
  W = []
  # ---- vld/busy/data(入力側): スキッドが埋まって o_busy=1 になり、送り側が保持する
  W.append(Wave("vbd_if", "vld/busy/data(入力側): vld=1 かつ busy=0 で転送。busy=1 の間は vld と data を保持",
                CLK, (P+"r_skd_vld", 1, 0), 18, [
                  R("i_vld", "i_vld"), R("o_busy", "o_busy"),
                  R("i_pix.data", "i_pix.data.pix[0][0]", "seq", prefix="D", valid=P+"i_vld"),
                ], back=6, hscale=2, note="データのラベル D0, D1, … は転送ごとの値(画素 pix[0][0])。o_busy は FF から出す"))
  # ---- BAYER_EX: 1フレームの入出力
  W.append(Wave("top_frame", "BAYER_EX: 1フレーム(16×4画素 = 8転送)。o_data の画素は補正後(RGGB、R: 黒レベル 100・1.5倍)",
                CLK, (P+"i_vld", 1, 0), 24, [
                  ("入力", [
                    R("i_vld", "i_vld"), R("o_busy", "o_busy"),
                    R("i_data.sof", "i_pix.data.sof", valid=P+"i_vld"),
                    R("i_data.eol", "i_pix.data.eol", valid=P+"i_vld"),
                    R("i_data.eof", "i_pix.data.eof", valid=P+"i_vld"),
                    R("i_data.pix[0][0]", "i_pix.data.pix[0][0]", "dec", valid=P+"i_vld"),
                  ]),
                  ("出力", [
                    R("o_vld", "o_vld"), R("i_busy", "i_busy"),
                    R("o_data.sof", "o_pix.data.sof", valid=P+"o_vld"),
                    R("o_data.eol", "o_pix.data.eol", valid=P+"o_vld"),
                    R("o_data.eof", "o_pix.data.eof", valid=P+"o_vld"),
                    R("o_data.pix[0][0]", "o_pix.data.pix[0][0]", "dec", valid=P+"o_vld"),
                  ]),
                ], back=1, hscale=1,
                note="入力は5転送目の前に2クロックあけ、出力は i_busy で8クロック止めた。o_busy=1 の間、6転送目を保持"))
  # ---- CORE: 1転送がパイプラインを進む(レイテンシ3)
  W.append(Wave("core_pipe", "BAYER_EX_CORE: 入力の転送から3クロック後に o_vld=1(入力段 → 1段目 → 2段目)。値は R の画素 pix[0][0]",
                CLK, (P+"i_vld", 1, 0), 10, [
                  R("i_vld", "i_vld"), R("i_pix.data", "i_pix.data.pix[0][0]", "dec", valid=P+"i_vld"),
                  R("r_in_vld", "r_in_vld"), R("r_in_data", "r_in_data.pix[0][0]", "dec", valid=P+"r_in_vld"),
                  R("u_pixcor.r_vld1", "u_pixcor.r_vld1"),
                  R("u_pixcor.r_data1", "u_pixcor.r_data1.pix[0][0]", "dec", valid=P+"u_pixcor.r_vld1"),
                  R("o_vld", "o_vld"), R("o_pix.data", "o_pix.data.pix[0][0]", "dec", valid=P+"o_vld"),
                  R("i_busy", "i_busy"), R("s_en", "s_en"),
                ], back=1, hscale=2,
                note="r_data1 は 1000 − 100 = 900、o_pix.data は 900 × 1.5 = 1350。i_busy=1 で s_en=0 になり全段を保持"))
  # ---- CORE: 出力を止めたときの動き(スキッド)
  W.append(Wave("core_stall", "BAYER_EX_CORE: i_busy=1 で PIXCOR を止め(s_en=0)、入力段が埋まった後の転送をスキッドで受ける(o_busy=1)",
                CLK, (P+"r_skd_vld", 1, 0), 20, [
                  R("i_vld", "i_vld"), R("o_busy (r_skd_vld)", "r_skd_vld"),
                  R("i_pix.data", "i_pix.data.pix[0][0]", "dec", valid=P+"i_vld"),
                  R("r_in_vld", "r_in_vld"), R("r_in_data", "r_in_data.pix[0][0]", "dec", valid=P+"r_in_vld"),
                  R("r_skd_data", "r_skd_data.pix[0][0]", "dec", valid=P+"r_skd_vld"),
                  R("s_en", "s_en"), R("u_pixcor.r_vld1", "u_pixcor.r_vld1"),
                  R("o_vld", "o_vld"), R("i_busy", "i_busy"),
                  R("o_pix.data", "o_pix.data.pix[0][0]", "dec", valid=P+"o_vld"),
                ], back=6, hscale=2, note="画素 pix[0][0] の値で転送を示す。o_vld=1 の間に i_busy=1 なら s_en=0(全段を保持)"))
  # ---- PIXCOR: 計算
  W.append(Wave("pixcor", "BAYER_EX_PIXCOR: 1段目で黒レベルを引き、2段目でゲインをかける(RGGB、黒レベル R/Gr/Gb/B = 100/200/300/400、ゲイン 1.5/1.0/1.0/2.0)",
                CLK, (P+"u_pixcor.i_vld", 1, 0), 8, [
                  R("i_en(1: 進める)", "u_pixcor.i_en"), R("i_vld", "u_pixcor.i_vld"),
                  R("i_data.pix[0][0](R)", "u_pixcor.i_data.pix[0][0]", "dec", valid=P+"u_pixcor.i_vld", each=True),
                  R("i_data.pix[0][1](Gr)", "u_pixcor.i_data.pix[0][1]", "dec", valid=P+"u_pixcor.i_vld", each=True),
                  R("i_data.pix[1][1](B)", "u_pixcor.i_data.pix[1][1]", "dec", valid=P+"u_pixcor.i_vld", each=True),
                  R("r_vld1", "u_pixcor.r_vld1"),
                  R("r_data1.pix[0][0]", "u_pixcor.r_data1.pix[0][0]", "dec", valid=P+"u_pixcor.r_vld1", each=True),
                  R("r_data1.pix[0][1]", "u_pixcor.r_data1.pix[0][1]", "dec", valid=P+"u_pixcor.r_vld1", each=True),
                  R("r_data1.pix[1][1]", "u_pixcor.r_data1.pix[1][1]", "dec", valid=P+"u_pixcor.r_vld1", each=True),
                  R("o_vld", "u_pixcor.o_vld"),
                  R("o_data.pix[0][0]", "u_pixcor.o_data.pix[0][0]", "dec", valid=P+"u_pixcor.o_vld", each=True),
                  R("o_data.pix[0][1]", "u_pixcor.o_data.pix[0][1]", "dec", valid=P+"u_pixcor.o_vld", each=True),
                  R("o_data.pix[1][1]", "u_pixcor.o_data.pix[1][1]", "dec", valid=P+"u_pixcor.o_vld", each=True),
                ], back=1, hscale=3, note="R: (1000−100)×1.5 = 1350、Gr: (1100−200)×1.0 = 900、B: (3100−400)×2.0 = 5400"))
  # ---- PIXCOR: bypass
  W.append(Wave("pixcor_bypass", "BAYER_EX_PIXCOR: bypass=1 のときは入力の画素をそのまま出す(レイテンシは同じ2)",
                CLK, (P+"r_cfg.bypass", 1, 0), 10, [
                  R("i_cfg.bypass", "u_pixcor.i_cfg.bypass"), R("i_vld", "u_pixcor.i_vld"),
                  R("i_data.pix[0][0]", "u_pixcor.i_data.pix[0][0]", "dec", valid=P+"u_pixcor.i_vld", each=True),
                  R("r_vld1", "u_pixcor.r_vld1"),
                  R("r_data1.pix[0][0]", "u_pixcor.r_data1.pix[0][0]", "dec", valid=P+"u_pixcor.r_vld1", each=True),
                  R("o_vld", "u_pixcor.o_vld"),
                  R("o_data.pix[0][0]", "u_pixcor.o_data.pix[0][0]", "dec", valid=P+"u_pixcor.o_vld", each=True),
                ], back=1, hscale=2))
  # ---- リセット
  W.append(Wave("reset", "リセット: 出力を止めたまま4転送を入れ(出力段・1段目・入力段・スキッド)、rst_n=0 で中のデータを捨てる",
                CLK, (P+"rst_n", 0, 1), 16, [
                  R("rst_n", "rst_n"), R("i_vld", "i_vld"), R("o_busy", "o_busy"),
                  R("r_in_vld", "r_in_vld"), R("u_pixcor.r_vld1", "u_pixcor.r_vld1"),
                  R("o_vld", "o_vld"), R("i_busy", "i_busy"),
                ], back=10, hscale=2, note="rst_n は非同期にかかり、5クロック後の立ち上がりで解除する。リセット中は o_vld=0、o_busy=0"))
  return W


def main():
  if( len(sys.argv)<3 ):
    print(__doc__)
    return 1
  vcd = Vcd(sys.argv[1])
  outdir = sys.argv[2]
  os.makedirs(outdir, exist_ok=True)
  ws = waves()
  names = {CLK}
  for w in ws:
    names.add(w.anchor[0])
    for r in all_rows(w):
      names.add(r.name)
      if( r.valid ):
        names.add(r.valid)
      if( r.invalid ):
        names.add(r.invalid)
  vcd.load(sorted(names))
  for w in ws:
    spec = build(vcd, w)
    with open(os.path.join(outdir, w.name+".json"), "w", encoding="utf-8") as fp:
      json.dump(spec, fp, ensure_ascii=False, indent=1)
    print("written:", w.name)
  return 0


if( __name__=="__main__" ):
  sys.exit(main())
