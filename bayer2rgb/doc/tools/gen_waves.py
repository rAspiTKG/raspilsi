#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
シミュレーションの波形(VCD)から、ブロックごとの WaveDrom の JSON を作る

  cd sim
  make build TRACE=vcd
  ./obj_ppc8_vcd/Vtb_top +UVM_TESTNAME=b2r_wave_test +verilator+seed+1 +WAVES
  python3 ../doc/tools/gen_waves.py waves.vcd ../doc/spec/wave

出力: <出力ディレクトリ>/<名前>.json(WaveDrom)
      SVGにするには doc/tools/render_wavedrom.js を使う(node と wavedrom パッケージが必要)
"""
import bisect
import json
import os
import re
import sys

P = "tb_top.u_dut."
CLK = "tb_top.clk"
CCLK = "tb_top.ctrl_clk"


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
# 区間ごとにまとめた図(1フレームの全体の流れ)
#   基準クロックの binクロックを1目盛りにし、その区間で条件が1回でも成り立てば1とする
# ============================================================================
class BinWave:
  def __init__( self, name, title, clk, start, end, binc, rows, before=4, after=4, note="", hscale=1 ):
    self.name = name
    self.title = title
    self.clk = clk
    self.start = start       # (信号, 値, 何回目か): 時刻0
    self.end = end           # (信号, 値, 何回目か): 終わり
    self.binc = binc
    self.rows = rows         # (ラベル, [信号...], "and" / "andn"(2つ目以降を反転))
    self.before = before
    self.after = after
    self.note = note
    self.hscale = hscale


def binwave_names( bw ):
  out = [bw.start[0], bw.end[0]]
  for r in bw.rows:
    out.extend(r[1])
  return out


def build_bin( vcd, bw ):
  base = vcd.rising(bw.clk)
  t0 = anchor_time(vcd, bw.start)
  t1 = anchor_time(vcd, bw.end)
  i0 = bisect.bisect_left(base, t0)
  i1 = bisect.bisect_left(base, t1)
  nb0 = bw.before
  nb = nb0+((i1-i0)//bw.binc)+1+bw.after
  first = i0-(nb0*bw.binc)
  out = []
  # 時刻の行(START の立ち上がりを0とし、4目盛りごとに数字を書く)
  wv = ""
  data = []
  for b in range(nb):
    if( (b>=nb0)and((b-nb0)%4==0) ):
      wv += "="
      data.append("%d" % ((b-nb0)*bw.binc))
    elif( b==0 ):
      wv += "x"     # 先頭を "." にすると WaveDrom の描画がずれる
    else:
      wv += "."
  out.append({"name": "clk数", "wave": wv, "data": data})
  out.append({})
  for label, sigs, mode in bw.rows:
    wv = ""
    prev = None
    for b in range(nb):
      hit = False
      for k in range(bw.binc):
        t = base[first+(b*bw.binc)+k]
        ok = True
        for j, sg in enumerate(sigs):
          v = vcd.ivalue(sg, t)
          v = 0 if( v is None ) else v
          if( (mode=="andn")and(j>0) ):
            v = 1-v
          ok = ok and (v==1)
        if( ok ):
          hit = True
          break
      ch = "1" if( hit ) else "0"
      wv += "." if( ch==prev ) else ch
      prev = ch
    out.append({"name": label, "wave": wv})
  spec = {"signal": out, "head": {"text": bw.title}, "config": {"hscale": bw.hscale}}
  if( bw.note ):
    spec["foot"] = {"text": bw.note}
  return spec


def binwaves():
  B = []
  B.append(BinWave("top_frame", "BAYER2RGB: 1フレーム(40×16画素)の流れ。1目盛り = clk 8クロック、その間に転送があれば1",
                   CLK, (P+"u_cdc.o_ctl.start", 1, 0), (P+"irq", 1, 0), 8, [
                     ("REG 書き込み", [P+"BAYER2RGB_REG_WVALID", P+"BAYER2RGB_REG_WREADY"], "and"),
                     ("start(映像系)", [P+"u_cdc.o_ctl.start"], "and"),
                     ("MEM AR", [P+"BAYER2RGB_MEM_ARVALID", P+"BAYER2RGB_MEM_ARREADY"], "and"),
                     ("MEM R", [P+"BAYER2RGB_MEM_RVALID", P+"BAYER2RGB_MEM_RREADY"], "and"),
                     ("CORE 入力(pix)", [P+"s_pix.vld", P+"s_pix.busy"], "andn"),
                     ("CORE 出力(rgb)", [P+"s_rgb.vld", P+"s_rgb.busy"], "andn"),
                     ("MEM AW", [P+"BAYER2RGB_MEM_AWVALID", P+"BAYER2RGB_MEM_AWREADY"], "and"),
                     ("MEM W", [P+"BAYER2RGB_MEM_WVALID", P+"BAYER2RGB_MEM_WREADY"], "and"),
                     ("MEM B", [P+"BAYER2RGB_MEM_BVALID", P+"BAYER2RGB_MEM_BREADY"], "and"),
                     ("frame_done(映像系)", [P+"u_wr_dma.o_evt.frame_done"], "and"),
                     ("STATUS.BUSY", [P+"u_reg.s_busy"], "and"),
                     ("irq", [P+"irq"], "and"),
                   ], before=3, after=6,
                   note="clk数は映像系の start を0とした clk の数。REG 書き込み・STATUS.BUSY・irq は ctrl_clk 側の信号"))
  return B


# ============================================================================
# 図の定義(b2r_wave_test の波形を前提にする)
# ============================================================================
def R( label, name, kind="bit", **kw ):
  return Row(label, P+name, kind, **kw)


def waves():
  W = []
  # ---- 共通: vld/busy/data(COREへの入力)
  W.append(Wave("vbd_if", "vld/busy/data: vld=1 かつ busy=0 のクロックで転送。busy=1 の間は vld と data を保持",
                CLK, (P+"s_pix.busy", 1, 0), 16, [
                  R("pix.vld", "s_pix.vld"), R("pix.busy", "s_pix.busy"),
                  R("pix.data", "s_pix.data", "seq", valid=P+"s_pix.vld"),
                ], back=4))
  # ---- AXIL_BRIDGE
  W.append(Wave("axil_bridge", "AXIL_BRIDGE: 書き込み(AW+W → req → rsp → B)と読み出し(AR → req → rsp → R)",
                CCLK, (P+"BAYER2RGB_REG_AWVALID", 1, 0), 20, [
                  ("AXI4-Lite", [
                    R("AWVALID", "BAYER2RGB_REG_AWVALID"), R("AWREADY", "BAYER2RGB_REG_AWREADY"),
                    R("AWADDR", "BAYER2RGB_REG_AWADDR", "hex", valid=P+"BAYER2RGB_REG_AWVALID"),
                    R("WVALID", "BAYER2RGB_REG_WVALID"), R("WREADY", "BAYER2RGB_REG_WREADY"),
                    R("BVALID", "BAYER2RGB_REG_BVALID"), R("BREADY", "BAYER2RGB_REG_BREADY"),
                    R("ARVALID", "BAYER2RGB_REG_ARVALID"), R("ARREADY", "BAYER2RGB_REG_ARREADY"),
                    R("ARADDR", "BAYER2RGB_REG_ARADDR", "hex", valid=P+"BAYER2RGB_REG_ARVALID"),
                    R("RVALID", "BAYER2RGB_REG_RVALID"), R("RREADY", "BAYER2RGB_REG_RREADY"),
                    R("RDATA", "BAYER2RGB_REG_RDATA", "hex", valid=P+"BAYER2RGB_REG_RVALID"),
                  ]),
                  ("REGとの間", [
                    R("req.vld", "s_req.vld"), R("req.busy", "s_req.busy"),
                    R("req.data.we", "s_req.data", "dec", bits=(48, 48), valid=P+"s_req.vld"),
                    R("rsp.vld", "s_rsp.vld"), R("rsp.busy", "s_rsp.busy"),
                  ]),
                ], back=1, hscale=2))
  # ---- REG: START の書き込みから CDC への要求まで
  W.append(Wave("reg_start", "REG: START の書き込み → o_start(CDCが空いていれば1クロック)→ i_cdc_busy",
                CCLK, (P+"u_reg.r_start_o", 1, 0), 14, [
                  R("req.vld", "s_req.vld"), R("req.data.we", "s_req.data", "dec", bits=(48, 48), valid=P+"s_req.vld"),
                  R("req.data.addr", "s_req.data", "hex", bits=(43, 32), valid=P+"s_req.vld"),
                  R("rsp.vld", "s_rsp.vld"),
                  R("r_start_pend", "u_reg.r_start_pend"), R("o_start", "u_reg.o_start"),
                  R("i_cdc_busy", "u_reg.i_cdc_busy"), R("r_frm_busy", "u_reg.r_frm_busy"),
                ], back=6))
  # ---- REG: フレーム完了から割り込みまで
  W.append(Wave("reg_irq", "REG: i_evt.frame_done → IRQ_STATUS.FRAME_DONE → o_irq(IRQ_ENABLE=1)→ 書き込み1でクリア",
                CCLK, (P+"u_reg.i_evt.frame_done", 1, 0), 28, [
                  R("i_evt.frame_done", "u_reg.i_evt.frame_done"), R("r_frm_busy", "u_reg.r_frm_busy"),
                  R("IRQ_STATUS[0]", "u_reg.r_irq_status", "dec", bits=(0, 0)),
                  R("o_irq", "u_reg.o_irq"), R("FRAME_COUNT", "u_reg.r_frame_count", "dec"),
                  R("req.vld", "s_req.vld"), R("req.data.we", "s_req.data", "dec", bits=(48, 48), valid=P+"s_req.vld"),
                ], back=2))
  # ---- CDC: START の受け渡し
  W.append(Wave("cdc_start", "CDC: START の受け渡し(トグル + 2段同期 + ACK)。映像系は設定を r_cfg_v に移して start を出す",
                CLK, (P+"u_cdc.r_req_c", 1, 0), 28, [
                  ("制御系", [
                    R("i_start", "u_cdc.i_start", clk=CCLK), R("r_req_c", "u_cdc.r_req_c", clk=CCLK),
                    R("s_ack_c", "u_cdc.s_ack_c", clk=CCLK), R("o_busy", "u_cdc.o_busy", clk=CCLK),
                  ]),
                  ("映像系", [
                    R("s_req_v", "u_cdc.s_req_v"), R("r_req_d_v", "u_cdc.r_req_d_v"),
                    R("o_ctl.start", "u_cdc.o_ctl.start"),
                    R("o_ctl.cfg.width", "u_cdc.o_ctl.cfg.width", "dec"),
                  ]),
                ], back=6))
  # ---- CDC: イベントの受け渡し(frame_done)
  W.append(Wave("cdc_event", "CDC: イベントの受け渡し(frame_done)。保留ビット → トグル → 制御系で1クロックのパルス",
                CLK, (P+"u_cdc.r_ev_req_v", 1, 0), 30, [
                  ("映像系", [
                    R("i_wr_evt.frame_done", "u_cdc.i_wr_evt.frame_done"),
                    R("r_ev_pend_v.frame_done", "u_cdc.r_ev_pend_v.frame_done"),
                    R("r_ev_req_v", "u_cdc.r_ev_req_v"), R("r_ev_busy_v", "u_cdc.r_ev_busy_v"),
                    R("s_ev_ack_v", "u_cdc.s_ev_ack_v"),
                  ]),
                  ("制御系", [
                    R("s_ev_req_c", "u_cdc.s_ev_req_c", clk=CCLK),
                    R("o_evt.frame_done", "u_cdc.o_evt.frame_done", clk=CCLK),
                  ]),
                ], back=3))
  # ---- ソフトリセット
  W.append(Wave("sw_reset", "ソフトリセット: SW_RESET の書き込み → 映像系の sw_rst → DMAの後始末 → srst_done → BUSY=0",
                CLK, (P+"u_reg.o_sw_rst", 1, 0), 48, [
                  ("制御系", [
                    R("r_srst_pend", "u_reg.r_srst_pend", clk=CCLK),
                    R("o_sw_rst", "u_reg.o_sw_rst", clk=CCLK), R("r_srst_wait", "u_reg.r_srst_wait", clk=CCLK),
                    R("i_evt.srst_done", "u_reg.i_evt.srst_done", clk=CCLK),
                  ]),
                  ("映像系", [
                    R("o_ctl.sw_rst", "u_cdc.o_ctl.sw_rst"), R("s_clr(CORE)", "u_core.s_clr"),
                    R("rd_dma.r_abort", "u_rd_dma.r_abort"), R("rd_dma.r_ost", "u_rd_dma.r_ost", "dec"),
                    R("wr_dma.r_abort", "u_wr_dma.r_abort"), R("wr_dma.r_ost", "u_wr_dma.r_ost", "dec"),
                    R("r_abort_v(CDC)", "u_cdc.r_abort_v"),
                  ]),
                ], back=11))
  # ---- AXIM_RD_BRIDGE
  W.append(Wave("axim_rd_bridge", "AXIM_RD_BRIDGE: ar → AR、R → r(2段スキッドを通すので1クロック遅れる)",
                CLK, (P+"s_ar.vld", 1, 0), 22, [
                  R("ar.vld", "s_ar.vld"), R("ar.busy", "s_ar.busy"),
                  R("ARVALID", "BAYER2RGB_MEM_ARVALID"), R("ARREADY", "BAYER2RGB_MEM_ARREADY"),
                  R("ARADDR", "BAYER2RGB_MEM_ARADDR", "hex", digits=5, valid=P+"BAYER2RGB_MEM_ARVALID"),
                  R("ARLEN", "BAYER2RGB_MEM_ARLEN", "dec", valid=P+"BAYER2RGB_MEM_ARVALID"),
                  R("RVALID", "BAYER2RGB_MEM_RVALID"), R("RREADY", "BAYER2RGB_MEM_RREADY"),
                  R("RLAST", "BAYER2RGB_MEM_RLAST", valid=P+"BAYER2RGB_MEM_RVALID"),
                  R("RDATA", "BAYER2RGB_MEM_RDATA", "seq", valid=P+"BAYER2RGB_MEM_RVALID"),
                  R("r.vld", "s_r.vld"), R("r.busy", "s_r.busy"),
                ], back=2, hscale=2))
  # ---- RD_DMA
  W.append(Wave("rd_dma", "RD_DMA: start → ラインごとのバースト(40画素 = 5ビート)→ 読み出しバッファ → COREへ",
                CLK, (P+"u_rd_dma.i_ctl.start", 1, 0), 40, [
                  R("i_ctl.start", "u_rd_dma.i_ctl.start"), R("r_act", "u_rd_dma.r_act"),
                  R("ar.vld", "s_ar.vld"), R("ar.busy", "s_ar.busy"),
                  R("ar.addr", "u_rd_dma.r_ar_data.addr", "hex", digits=5, valid=P+"s_ar.vld"),
                  R("ar.len", "u_rd_dma.r_ar_data.len", "dec", valid=P+"s_ar.vld"),
                  R("r_credit", "u_rd_dma.r_credit", "dec"), R("r_ost", "u_rd_dma.r_ost", "dec"),
                  R("r.vld", "s_r.vld"), R("pix.vld", "s_pix.vld"), R("pix.busy", "s_pix.busy"),
                  R("pix.data", "s_pix.data", "seq", valid=P+"s_pix.vld"),
                ], back=2, hscale=2))
  # ---- IN_CTRL: ラインの終わり
  W.append(Wave("in_ctrl_line", "IN_CTRL: ラインの終わり。列K(=5)は入力なしの掃き出しステップ(fcol)",
                CLK, (P+"u_core.s_stp0.fcol", 1, 1), 18, [
                  R("pix.vld", "s_pix.vld"), R("pix.busy", "s_pix.busy"),
                  R("stp.vld", "u_core.s_stp0.vld"), R("stp.line", "u_core.s_stp0.line", "dec", valid=P+"u_core.s_stp0.vld"),
                  R("stp.col", "u_core.s_stp0.col", "dec", valid=P+"u_core.s_stp0.vld"),
                  R("stp.fcol", "u_core.s_stp0.fcol", valid=P+"u_core.s_stp0.vld"),
                  R("stp.frow", "u_core.s_stp0.frow", valid=P+"u_core.s_stp0.vld"),
                  R("i_fifo_cnt", "u_core.s_fifo_cnt", "dec"), R("r_infl", "u_core.u_in_ctrl.r_infl", "dec"),
                ], back=8))
  # ---- IN_CTRL: フレームの終わり(掃き出しライン)
  W.append(Wave("in_ctrl_frame", "IN_CTRL: フレームの終わり。ラインH(=16)は入力なしの掃き出しライン(frow)",
                CLK, (P+"u_core.s_stp0.frow", 1, 0), 16, [
                  R("pix.vld", "s_pix.vld"), R("pix.busy", "s_pix.busy"),
                  R("stp.vld", "u_core.s_stp0.vld"), R("stp.line", "u_core.s_stp0.line", "dec", valid=P+"u_core.s_stp0.vld"),
                  R("stp.col", "u_core.s_stp0.col", "dec", valid=P+"u_core.s_stp0.vld"),
                  R("stp.fcol", "u_core.s_stp0.fcol", valid=P+"u_core.s_stp0.vld"),
                  R("stp.frow", "u_core.s_stp0.frow", valid=P+"u_core.s_stp0.vld"),
                  R("r_act", "u_core.u_in_ctrl.r_act"),
                ], back=4))
  # ---- LBUF
  W.append(Wave("lbuf", "LBUF: ライン1の処理。SRAMを読み、次のクロックで書き戻す。窓は列 oc = col-1、ライン y = line-1",
                CLK, (P+"u_core.s_win.vld", 1, 0), 18, [
                  R("stp.vld", "u_core.s_stp2.vld"), R("stp.line", "u_core.s_stp2.line", "dec", valid=P+"u_core.s_stp2.vld"),
                  R("stp.col", "u_core.s_stp2.col", "dec", valid=P+"u_core.s_stp2.vld"),
                  R("sram0.ren", "u_core.s_sram0_ren"), R("sram0.raddr", "u_core.s_sram0_raddr", "dec", valid=P+"u_core.s_sram0_ren"),
                  R("sram0.wen", "u_core.s_sram0_wen"), R("sram0.waddr", "u_core.s_sram0_waddr", "dec", valid=P+"u_core.s_sram0_wen"),
                  R("sram1.ren", "u_core.s_sram1_ren"), R("sram1.wen", "u_core.s_sram1_wen"),
                  R("win.vld", "u_core.s_win.vld"), R("win.y", "u_core.s_win.y", "dec", valid=P+"u_core.s_win.vld"),
                  R("win.oc", "u_core.s_win.oc", "dec", valid=P+"u_core.s_win.vld"),
                  R("win.sof", "u_core.s_win.sof", valid=P+"u_core.s_win.vld"),
                  R("win.eol", "u_core.s_win.eol", valid=P+"u_core.s_win.vld"),
                ], back=4))
  # ---- CORE のパイプライン
  W.append(Wave("core_pipe", "CORE: ライン1・列1のステップ(最初の出力になる)が各段を進む様子。IN_CTRLの出力から出力FIFOの書き込みまで14クロック",
                CLK, (P+"u_core.s_stp0.line", 1, 0), 26, [
                  R("line", "u_core.s_stp0.line", "dec", valid=P+"u_core.s_stp0.vld"),
                  R("col", "u_core.s_stp0.col", "dec", valid=P+"u_core.s_stp0.vld"),
                  ("各段の出力 vld", [
                    R("IN_CTRL", "u_core.s_stp0.vld"), R("BLC", "u_core.s_stp1.vld"),
                    R("WB", "u_core.s_stp2.vld"), R("LBUF", "u_core.s_win.vld"),
                    R("DMSC", "u_core.s_dm.vld"), R("FCS", "u_core.s_fc.vld"),
                    R("GAMMA", "u_core.s_gm.vld"), R("OUT_FMT", "u_core.s_of_vld"),
                  ]),
                  R("fifo_cnt", "u_core.s_fifo_cnt", "dec"), R("rgb.vld", "s_rgb.vld"), R("rgb.busy", "s_rgb.busy"),
                ], back=1,
                note="各段の vld: IN_CTRL=s_stp0 / BLC=s_stp1 / WB=s_stp2 / LBUF=s_win / DMSC=s_dm / FCS=s_fc / GAMMA=s_gm / OUT_FMT=s_of_vld"))
  # ---- 画素処理ブロック(画素0 の値を10進で示す。wave_test の最初のフレームは blc=800, WB: R=1.75 G=1.0 B=1.5)
  W.append(Wave("blc", "BLC: q = max(p − blc[site], 0)。1クロック(この例は blc=800、ライン2 = R/Gr の行)",
                CLK, (P+"u_core.s_stp0.line", 2, 0), 12, [
                  R("i.vld", "u_core.s_stp0.vld"),
                  R("i.col", "u_core.s_stp0.col", "dec", valid=P+"u_core.s_stp0.vld"),
                  R("i.fcol", "u_core.s_stp0.fcol", valid=P+"u_core.s_stp0.vld"),
                  R("i.pix[0](R)", "u_core.s_stp0.pix[0]", "dec", valid=P+"u_core.s_stp0.vld", invalid=P+"u_core.s_stp0.fcol", each=True),
                  R("i.pix[1](Gr)", "u_core.s_stp0.pix[1]", "dec", valid=P+"u_core.s_stp0.vld", invalid=P+"u_core.s_stp0.fcol", each=True),
                  R("o.vld", "u_core.s_stp1.vld"),
                  R("o.pix[0](R)", "u_core.s_stp1.pix[0]", "dec", valid=P+"u_core.s_stp1.vld", invalid=P+"u_core.s_stp1.fcol", each=True),
                  R("o.pix[1](Gr)", "u_core.s_stp1.pix[1]", "dec", valid=P+"u_core.s_stp1.vld", invalid=P+"u_core.s_stp1.fcol", each=True),
                ], back=1, hscale=2))
  W.append(Wave("wb", "WB: min(16383, (q×g + 2048) >> 12)。2クロック(この例は R: g=1.75、Gr: g=1.0)",
                CLK, (P+"u_core.s_stp1.line", 2, 0), 12, [
                  R("i.vld", "u_core.s_stp1.vld"),
                  R("i.pix[0](R)", "u_core.s_stp1.pix[0]", "dec", valid=P+"u_core.s_stp1.vld", invalid=P+"u_core.s_stp1.fcol", each=True),
                  R("i.pix[1](Gr)", "u_core.s_stp1.pix[1]", "dec", valid=P+"u_core.s_stp1.vld", invalid=P+"u_core.s_stp1.fcol", each=True),
                  R("o.vld", "u_core.s_stp2.vld"),
                  R("o.pix[0](R)", "u_core.s_stp2.pix[0]", "dec", valid=P+"u_core.s_stp2.vld", invalid=P+"u_core.s_stp2.fcol", each=True),
                  R("o.pix[1](Gr)", "u_core.s_stp2.pix[1]", "dec", valid=P+"u_core.s_stp2.vld", invalid=P+"u_core.s_stp2.fcol", each=True),
                ], back=1, hscale=2))
  W.append(Wave("dmsc", "DMSC: 3ライン × (PPC+2) 画素の窓からバイリニア補間とエッジ量。2クロック(画素0 = R の位置)",
                CLK, (P+"u_core.s_win.y", 2, 0), 12, [
                  R("i.vld", "u_core.s_win.vld"),
                  R("i.oc", "u_core.s_win.oc", "dec", valid=P+"u_core.s_win.vld", each=True),
                  R("i.win[1][1](中心)", "u_core.s_win.win[1][1]", "dec", valid=P+"u_core.s_win.vld", each=True),
                  R("o.vld", "u_core.s_dm.vld"),
                  R("o.R", "u_core.s_dm.rgb[0][0]", "dec", valid=P+"u_core.s_dm.vld", each=True),
                  R("o.G", "u_core.s_dm.rgb[0][1]", "dec", valid=P+"u_core.s_dm.vld", each=True),
                  R("o.B", "u_core.s_dm.rgb[0][2]", "dec", valid=P+"u_core.s_dm.vld", each=True),
                  R("o.edg", "u_core.s_dm.edg[0]", "dec", valid=P+"u_core.s_dm.vld", each=True),
                ], back=1, hscale=2))
  W.append(Wave("fcs", "FCS: エッジ量が fcs_th を超えた分だけ色差を縮める。3クロック(この例は fcs_th=4000, fcs_gain=4)",
                CLK, (P+"u_core.s_dm.y", 2, 0), 13, [
                  R("i.vld", "u_core.s_dm.vld"),
                  R("i.R", "u_core.s_dm.rgb[0][0]", "dec", valid=P+"u_core.s_dm.vld", each=True),
                  R("i.G", "u_core.s_dm.rgb[0][1]", "dec", valid=P+"u_core.s_dm.vld", each=True),
                  R("i.B", "u_core.s_dm.rgb[0][2]", "dec", valid=P+"u_core.s_dm.vld", each=True),
                  R("i.edg", "u_core.s_dm.edg[0]", "dec", valid=P+"u_core.s_dm.vld", each=True),
                  R("o.vld", "u_core.s_fc.vld"),
                  R("o.R", "u_core.s_fc.rgb[0][0]", "dec", valid=P+"u_core.s_fc.vld", each=True),
                  R("o.G", "u_core.s_fc.rgb[0][1]", "dec", valid=P+"u_core.s_fc.vld", each=True),
                  R("o.B", "u_core.s_fc.rgb[0][2]", "dec", valid=P+"u_core.s_fc.vld", each=True),
                ], back=1, hscale=2))
  W.append(Wave("gamma", "GAMMA: 37点の折れ線で 14bit → 8bit。3クロック(既定の表は sRGB)",
                CLK, (P+"u_core.s_fc.y", 2, 0), 13, [
                  R("i.vld", "u_core.s_fc.vld"),
                  R("i.R", "u_core.s_fc.rgb[0][0]", "dec", valid=P+"u_core.s_fc.vld", each=True),
                  R("i.G", "u_core.s_fc.rgb[0][1]", "dec", valid=P+"u_core.s_fc.vld", each=True),
                  R("i.B", "u_core.s_fc.rgb[0][2]", "dec", valid=P+"u_core.s_fc.vld", each=True),
                  R("o.vld", "u_core.s_gm.vld"),
                  R("o.R", "u_core.s_gm.rgb[0][0]", "dec", valid=P+"u_core.s_gm.vld", each=True),
                  R("o.G", "u_core.s_gm.rgb[0][1]", "dec", valid=P+"u_core.s_gm.vld", each=True),
                  R("o.B", "u_core.s_gm.rgb[0][2]", "dec", valid=P+"u_core.s_gm.vld", each=True),
                ], back=1, hscale=2))
  W.append(Wave("out_fmt", "OUT_FMT: 画素の R,G,B をこの順にバイトへ詰め、sof/eol/eof を付ける。1クロック",
                CLK, (P+"u_core.s_gm.sof", 1, 0), 12, [
                  R("i.vld", "u_core.s_gm.vld"),
                  R("i.R", "u_core.s_gm.rgb[0][0]", "dec", valid=P+"u_core.s_gm.vld", each=True),
                  R("i.G", "u_core.s_gm.rgb[0][1]", "dec", valid=P+"u_core.s_gm.vld", each=True),
                  R("i.B", "u_core.s_gm.rgb[0][2]", "dec", valid=P+"u_core.s_gm.vld", each=True),
                  R("i.sof", "u_core.s_gm.sof", valid=P+"u_core.s_gm.vld"),
                  R("o_vld", "u_core.s_of_vld"),
                  R("o_data.rgb[23:0]", "u_core.s_of_data.rgb", "hex", bits=(23, 0), valid=P+"u_core.s_of_vld", each=True),
                  R("o_data.sof", "u_core.s_of_data.sof", valid=P+"u_core.s_of_vld"),
                ], back=2, hscale=2,
                note="o_data.rgb のバイト0/1/2 = 画素0 の R/G/B(16進は上位から B,G,R の順に見える)"))
  # ---- OUT_FIFO
  W.append(Wave("out_fifo", "OUT_FIFO: 書き込み(i_vld)から3クロックで読み出し側に出る。o_cnt は先読み分を含む",
                CLK, (P+"u_core.s_of_vld", 1, 0), 18, [
                  R("i_vld", "u_core.s_of_vld"), R("o_cnt", "u_core.s_fifo_cnt", "dec"),
                  R("rgb.vld", "s_rgb.vld"), R("rgb.busy", "s_rgb.busy"),
                  R("rgb.sof", "s_rgb.data", "dec", bits=(192, 192), valid=P+"s_rgb.vld"),
                  R("rgb.eol", "s_rgb.data", "dec", bits=(193, 193), valid=P+"s_rgb.vld"),
                ], back=2))
  # ---- WR_DMA: 最初のバースト
  W.append(Wave("wr_dma", "WR_DMA: 24バイトのビートを16バイトに詰める。バースト分そろったらAW、Wは並行して送る",
                CLK, (P+"s_aw.vld", 1, 0), 34, [
                  R("rgb.vld", "s_rgb.vld"), R("rgb.busy", "s_rgb.busy"),
                  R("r_cnt(8B単位)", "u_wr_dma.r_cnt", "dec"), R("s_push", "u_wr_dma.s_push"),
                  R("r_avail", "u_wr_dma.r_avail", "dec"),
                  R("aw.vld", "s_aw.vld"), R("aw.addr", "u_wr_dma.r_aw_data.addr", "hex", digits=5, valid=P+"s_aw.vld"),
                  R("aw.len", "u_wr_dma.r_aw_data.len", "dec", valid=P+"s_aw.vld"),
                  R("w.vld", "s_w.vld"), R("w.busy", "s_w.busy"),
                  R("w.last", "s_w.data", "dec", bits=(144, 144), valid=P+"s_w.vld"),
                  R("w.strb", "s_w.data", "hex", bits=(143, 128), valid=P+"s_w.vld"),
                  R("b.vld", "s_b.vld"), R("r_ost", "u_wr_dma.r_ost", "dec"),
                ], back=14, hscale=2))
  # ---- WR_DMA: フレームの終わり
  W.append(Wave("wr_dma_end", "WR_DMA: フレームの終わり。最後のビートは端数(WSTRB=00ff)、全バーストの応答で frame_done",
                CLK, (P+"u_wr_dma.r_done", 1, 0), 22, [
                  R("w.vld", "s_w.vld"), R("w.last", "s_w.data", "dec", bits=(144, 144), valid=P+"s_w.vld"),
                  R("w.strb", "s_w.data", "hex", bits=(143, 128), valid=P+"s_w.vld"),
                  R("BVALID", "BAYER2RGB_MEM_BVALID"), R("b.vld", "s_b.vld"),
                  R("r_aw_go", "u_wr_dma.r_aw_go"), R("r_ost", "u_wr_dma.r_ost", "dec"),
                  R("r_act", "u_wr_dma.r_act"), R("o_evt.frame_done", "u_wr_dma.o_evt.frame_done"),
                  R("o_evt.busy", "u_wr_dma.o_evt.busy"),
                ], back=18))
  # ---- AXIM_WR_BRIDGE
  W.append(Wave("axim_wr_bridge", "AXIM_WR_BRIDGE: aw/w → AW/W、B → b(2段スキッド)",
                CLK, (P+"s_aw.vld", 1, 0), 26, [
                  R("aw.vld", "s_aw.vld"), R("AWVALID", "BAYER2RGB_MEM_AWVALID"), R("AWREADY", "BAYER2RGB_MEM_AWREADY"),
                  R("AWADDR", "BAYER2RGB_MEM_AWADDR", "hex", digits=5, valid=P+"BAYER2RGB_MEM_AWVALID"),
                  R("AWLEN", "BAYER2RGB_MEM_AWLEN", "dec", valid=P+"BAYER2RGB_MEM_AWVALID"),
                  R("w.vld", "s_w.vld"), R("WVALID", "BAYER2RGB_MEM_WVALID"), R("WREADY", "BAYER2RGB_MEM_WREADY"),
                  R("WLAST", "BAYER2RGB_MEM_WLAST", valid=P+"BAYER2RGB_MEM_WVALID"),
                  R("BVALID", "BAYER2RGB_MEM_BVALID"), R("BREADY", "BAYER2RGB_MEM_BREADY"),
                  R("b.vld", "s_b.vld"),
                ], back=3, hscale=2))
  # ---- SKID(W チャネル)
  W.append(Wave("skid", "SKID: 出力が止まっても1ビート受け取る。o_busy はスキッド段が埋まったとき(FFから出す)",
                CLK, (P+"u_axim_wr_bridge.u_skid_w.r_skd_vld", 1, 0), 16, [
                  R("i_vld", "u_axim_wr_bridge.u_skid_w.i_vld"), R("o_busy", "u_axim_wr_bridge.u_skid_w.o_busy"),
                  R("i_data", "u_axim_wr_bridge.u_skid_w.i_data", "seq", valid=P+"u_axim_wr_bridge.u_skid_w.i_vld"),
                  R("o_vld", "u_axim_wr_bridge.u_skid_w.o_vld"), R("i_busy", "u_axim_wr_bridge.u_skid_w.i_busy"),
                  R("o_data", "u_axim_wr_bridge.u_skid_w.o_data", "seq", valid=P+"u_axim_wr_bridge.u_skid_w.o_vld"),
                ], back=4, hscale=2))
  # ---- SFIFO(読み出しバッファ)
  W.append(Wave("sfifo", "SFIFO(SRAM版、読み出しバッファ): 書き込みから3クロックで読み出し側に出る",
                CLK, (P+"u_rd_dma.u_rbuf.i_wvld", 1, 0), 18, [
                  R("i_wvld", "u_rd_dma.u_rbuf.i_wvld"), R("o_wbusy", "u_rd_dma.u_rbuf.o_wbusy"),
                  R("sram.wen", "u_rd_dma.u_rbuf.g_sram.s_push"), R("sram.ren", "u_rd_dma.u_rbuf.g_sram.s_ren"),
                  R("r_scnt", "u_rd_dma.u_rbuf.g_sram.r_scnt", "dec"), R("r_pcnt", "u_rd_dma.u_rbuf.g_sram.r_pcnt", "dec"),
                  R("o_rvld", "u_rd_dma.u_rbuf.o_rvld"), R("i_rbusy", "u_rd_dma.u_rbuf.i_rbusy"),
                  R("o_cnt", "u_rd_dma.u_rbuf.o_cnt", "dec"),
                ], back=2))
  # ---- SRAM(ラインバッファ)
  W.append(Wave("sram", "SRAM_1R1W: 読み出しレイテンシ1。読まないクロックは出力を保持する",
                CLK, (P+"u_core.s_sram1_wen", 1, 1), 12, [
                  R("i_ren", "u_core.s_sram1_ren"), R("i_raddr", "u_core.s_sram1_raddr", "dec", valid=P+"u_core.s_sram1_ren"),
                  R("o_rdata", "u_core.s_sram1_rdata", "seq"),
                  R("i_wen", "u_core.s_sram1_wen"), R("i_waddr", "u_core.s_sram1_waddr", "dec", valid=P+"u_core.s_sram1_wen"),
                  R("i_wdata", "u_core.s_sram1_wdata", "seq", valid=P+"u_core.s_sram1_wen"),
                ], back=3, hscale=2))
  # ---- SYNC2
  W.append(Wave("sync2", "SYNC2: 2段同期。i_d の変化は2つ目の clk の立ち上がりで o_q に出る",
                CLK, (P+"u_cdc.u_sync_req.i_d", 1, 0), 14, [
                  R("i_d(r_req_c)", "u_cdc.u_sync_req.i_d", clk=CCLK), R("u_sync.r_m", "u_cdc.u_sync_req.u_sync.r_m"),
                  R("o_q", "u_cdc.u_sync_req.o_q"),
                ], back=6))
  return W


def main():
  if( len(sys.argv)<3 ):
    print(__doc__)
    return 1
  vcd = Vcd(sys.argv[1])
  outdir = sys.argv[2]
  os.makedirs(outdir, exist_ok=True)
  ws = waves()
  bs = binwaves()
  names = {CLK, CCLK}
  for w in ws:
    names.add(w.anchor[0])
    for r in all_rows(w):
      names.add(r.name)
      if( r.valid ):
        names.add(r.valid)
      if( r.invalid ):
        names.add(r.invalid)
  for b in bs:
    names.update(binwave_names(b))
  vcd.load(sorted(names))
  specs = [(w.name, build(vcd, w)) for w in ws]
  specs += [(b.name, build_bin(vcd, b)) for b in bs]
  for name, spec in specs:
    with open(os.path.join(outdir, name+".json"), "w", encoding="utf-8") as fp:
      json.dump(spec, fp, ensure_ascii=False, indent=1)
    print("written:", name)
  return 0


if( __name__=="__main__" ):
  sys.exit(main())
