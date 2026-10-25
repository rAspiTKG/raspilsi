#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
RTLのポート宣言から端子表(Markdown)を作る

  python3 doc/tools/gen_pins.py <rtlディレクトリ> <出力ディレクトリ>

各モジュールについて <出力ディレクトリ>/<モジュール名>.md を作る。
列: 信号名 / 入出力 / 信号仕様 / ビット幅 / 極性
  - 入出力とビット幅はRTLから取る(PPC=8 の値。PPCに依存するものは式も書く)
  - vld/busy/data のインタフェースポートは .vld / .busy / .data の3行に展開する
  - 信号仕様は下の DESC に書く。説明のないポートがあるとエラーにする
"""
import os
import re
import sys

# PPC=8 のときの定数と型の幅(BAYER2RGB_PKG)
CONST = {
  "PPC": 8, "IN_BITS": 14, "OUT_BITS": 8, "MEM_AW": 40, "MEM_DW": 128, "MEM_IDW": 4, "MEM_BYTES": 16,
  "REG_AW": 12, "REG_DW": 32, "OFIFO_CW": 6, "LB_AW": 9, "BEAT_W": 112, "WIDTH_W": 12, "HEIGHT_W": 12,
  "COL_W": 9,
}
TYPE_W = {
  "cfg_t": 795, "ctl_t": 797, "evt_t": 4, "rd_evt_t": 2, "wr_evt_t": 3, "axreq_t": 59, "rbeat_t": 131,
  "wbeat_t": 145, "regreq_t": 49, "regrsp_t": 34, "obeat_t": 195, "stp_t": 136, "win_t": 445, "dm_t": 473,
  "fc_t": 361, "gm_t": 217,
}
# PPC に依存する幅(表に式も書く)
PPC_DEP = {"stp_t": "PPC×14+24", "win_t": "3×(PPC+2)×14+25", "dm_t": "PPC×56+25", "fc_t": "PPC×42+25",
           "gm_t": "PPC×24+25", "obeat_t": "PPC×24+3", "BEAT_W": "PPC×14", "LB_AW": "log2(3840/PPC)"}

# vld/busy/data インタフェースの data の幅(モジュール, ポート) → (幅, 型)
IF_W = {
  ("BAYER2RGB_AXIL_BRIDGE", "req"): (49, "regreq_t"), ("BAYER2RGB_AXIL_BRIDGE", "rsp"): (34, "regrsp_t"),
  ("BAYER2RGB_REG", "req"): (49, "regreq_t"), ("BAYER2RGB_REG", "rsp"): (34, "regrsp_t"),
  ("BAYER2RGB_AXIM_RD_BRIDGE", "ar"): (59, "axreq_t"), ("BAYER2RGB_AXIM_RD_BRIDGE", "r"): (131, "rbeat_t"),
  ("BAYER2RGB_RD_DMA", "ar"): (59, "axreq_t"), ("BAYER2RGB_RD_DMA", "r"): (131, "rbeat_t"),
  ("BAYER2RGB_RD_DMA", "pix"): (112, "BEAT_W"),
  ("BAYER2RGB_CORE", "pix"): (112, "BEAT_W"), ("BAYER2RGB_CORE", "rgb"): (195, "obeat_t"),
  ("BAYER2RGB_IN_CTRL", "pix"): (112, "BEAT_W"), ("BAYER2RGB_OUT_FIFO", "rgb"): (195, "obeat_t"),
  ("BAYER2RGB_WR_DMA", "rgb"): (195, "obeat_t"), ("BAYER2RGB_WR_DMA", "aw"): (59, "axreq_t"),
  ("BAYER2RGB_WR_DMA", "w"): (145, "wbeat_t"), ("BAYER2RGB_WR_DMA", "b"): (2, ""),
  ("BAYER2RGB_AXIM_WR_BRIDGE", "aw"): (59, "axreq_t"), ("BAYER2RGB_AXIM_WR_BRIDGE", "w"): (145, "wbeat_t"),
  ("BAYER2RGB_AXIM_WR_BRIDGE", "b"): (2, ""),
}

# ----------------------------------------------------------------------------
# 信号仕様
# ----------------------------------------------------------------------------
COMMON = {
  "clk": "映像系クロック(AXI4マスタ・画像処理)。400MHz",
  "rst_n": "映像系リセット。非同期アサート・同期解除(同期化は外部)",
  "ctrl_clk": "制御系クロック(AXI4-Liteスレーブ・レジスタ)",
  "ctrl_rst_n": "制御系リセット。非同期アサート・同期解除(同期化は外部)",
  "i_clr": "同期クリア(ソフトリセット)。1クロックのパルスで有効ビットを消す",
  "i_cfg": "フレームの設定(cfg_t)。フレームの開始時だけ変わる",
  "i_ctl": "フレームの設定 + start(開始パルス)+ sw_rst(ソフトリセットパルス)(ctl_t)",
}

AXIL = {
  "AWADDR": "書き込みアドレス(バイトアドレス。下位2ビットは見ない)", "AWPROT": "保護属性(使わない)",
  "AWVALID": "書き込みアドレスが有効", "AWREADY": "書き込みアドレスを受け付けた",
  "WDATA": "書き込みデータ", "WSTRB": "バイトイネーブル", "WVALID": "書き込みデータが有効",
  "WREADY": "書き込みデータを受け付けた", "BRESP": "書き込み応答(常にOKAY)", "BVALID": "書き込み応答が有効",
  "BREADY": "書き込み応答を受け取れる", "ARADDR": "読み出しアドレス(バイトアドレス。下位2ビットは見ない)",
  "ARPROT": "保護属性(使わない)", "ARVALID": "読み出しアドレスが有効", "ARREADY": "読み出しアドレスを受け付けた",
  "RDATA": "読み出しデータ(未定義のアドレスは0)", "RRESP": "読み出し応答(常にOKAY)", "RVALID": "読み出しデータが有効",
  "RREADY": "読み出しデータを受け取れる",
}

AXIM = {
  "AWID": "書き込みID(常に0)", "AWADDR": "書き込みアドレス(16バイト境界)", "AWLEN": "バーストのビート数-1(0〜15)",
  "AWSIZE": "1ビートのバイト数(常に4 = 16バイト)", "AWBURST": "バーストの種類(常に1 = INCR)",
  "AWLOCK": "排他アクセス(常に0)", "AWCACHE": "キャッシュ属性(AXI_ATTR.AWCACHE)",
  "AWPROT": "保護属性(AXI_ATTR.AWPROT)", "AWQOS": "QoS(AXI_ATTR.AWQOS)", "AWVALID": "書き込み要求が有効",
  "AWREADY": "書き込み要求を受け付けた",
  "WDATA": "書き込みデータ(RGB888をR,G,B順に詰めたもの。バイト0が下位)",
  "WSTRB": "バイトイネーブル(ラインの最後の端数ビートだけ下位8バイト)", "WLAST": "バーストの最後のビート",
  "WVALID": "書き込みデータが有効", "WREADY": "書き込みデータを受け付けた",
  "BID": "応答ID(見ない)", "BRESP": "書き込み応答(OKAY以外は IRQ_STATUS.WR_ERR)", "BVALID": "書き込み応答が有効",
  "BREADY": "書き込み応答を受け取れる(常に受け取る)",
  "ARID": "読み出しID(常に0)", "ARADDR": "読み出しアドレス(16バイト境界)", "ARLEN": "バーストのビート数-1(0〜15)",
  "ARSIZE": "1ビートのバイト数(常に4 = 16バイト)", "ARBURST": "バーストの種類(常に1 = INCR)",
  "ARLOCK": "排他アクセス(常に0)", "ARCACHE": "キャッシュ属性(AXI_ATTR.ARCACHE)",
  "ARPROT": "保護属性(AXI_ATTR.ARPROT)", "ARQOS": "QoS(AXI_ATTR.ARQOS)", "ARVALID": "読み出し要求が有効",
  "ARREADY": "読み出し要求を受け付けた", "RID": "応答ID(見ない)",
  "RDATA": "読み出しデータ(16bit×8画素。各16bitの下位14bitを使う)", "RRESP": "読み出し応答(OKAY以外は IRQ_STATUS.RD_ERR)",
  "RLAST": "バーストの最後のビート", "RVALID": "読み出しデータが有効", "RREADY": "読み出しデータを受け取れる",
}

# インタフェースポートの説明: (モジュール, ポート) → (vld, busy, data)
IF_DESC = {
  ("BAYER2RGB_AXIL_BRIDGE", "req"): ("REGへのアクセス要求が有効", "REGが要求を受け取れない",
                                     "要求 {we, strb[3:0], addr[11:0], wdata[31:0]}(regreq_t)"),
  ("BAYER2RGB_AXIL_BRIDGE", "rsp"): ("REGからの応答が有効", "応答を受け取れない(AXI側の応答を出している)",
                                     "応答 {resp[1:0], rdata[31:0]}(regrsp_t)"),
  ("BAYER2RGB_REG", "req"): ("アクセス要求が有効", "要求を受け取れない(応答を返している)",
                             "要求 {we, strb, addr, wdata}(regreq_t)"),
  ("BAYER2RGB_REG", "rsp"): ("応答が有効", "AXIL_BRIDGEが応答を受け取れない", "応答 {resp, rdata}(regrsp_t)"),
  ("BAYER2RGB_AXIM_RD_BRIDGE", "ar"): ("読み出し要求が有効", "要求を受け取れない(スキッドが満杯)",
                                       "要求 {qos, prot, cache, len, addr}(axreq_t)"),
  ("BAYER2RGB_AXIM_RD_BRIDGE", "r"): ("読み出しデータが有効", "RD_DMAがデータを受け取れない",
                                      "データ {resp, last, data[127:0]}(rbeat_t)"),
  ("BAYER2RGB_RD_DMA", "ar"): ("読み出し要求が有効", "BRIDGEが要求を受け取れない", "要求(axreq_t)"),
  ("BAYER2RGB_RD_DMA", "r"): ("読み出しデータが有効", "データを受け取れない(通常は0。バッファの空きを予約済み)",
                              "データ(rbeat_t)"),
  ("BAYER2RGB_RD_DMA", "pix"): ("画素ビートが有効", "COREが受け取れない", "PPC画素 × 14bit。画素 i は [14i+13:14i]"),
  ("BAYER2RGB_CORE", "pix"): ("画素ビートが有効", "受け取れない(クレジット不足・掃き出し中)",
                              "PPC画素 × 14bit。画素 i は [14i+13:14i]"),
  ("BAYER2RGB_CORE", "rgb"): ("出力ビートが有効", "WR_DMAが受け取れない",
                              "{eof, eol, sof, rgb[PPC×24-1:0]}(obeat_t)。rgbのバイト3i/3i+1/3i+2が画素iのR/G/B"),
  ("BAYER2RGB_IN_CTRL", "pix"): ("画素ビートが有効", "受け取れない(クレジット不足・掃き出しステップ)",
                                 "PPC画素 × 14bit"),
  ("BAYER2RGB_OUT_FIFO", "rgb"): ("出力ビートが有効(FIFOが空でない)", "WR_DMAが受け取れない", "出力ビート(obeat_t)"),
  ("BAYER2RGB_WR_DMA", "rgb"): ("COREの出力ビートが有効", "受け取れない(詰め替え中・バッファが満杯)",
                                "出力ビート(obeat_t)"),
  ("BAYER2RGB_WR_DMA", "aw"): ("書き込み要求が有効", "BRIDGEが要求を受け取れない", "要求(axreq_t)"),
  ("BAYER2RGB_WR_DMA", "w"): ("書き込みデータが有効", "BRIDGEがデータを受け取れない",
                              "データ {last, strb[15:0], data[127:0]}(wbeat_t)"),
  ("BAYER2RGB_WR_DMA", "b"): ("書き込み応答が有効", "応答を受け取れない(常に0)", "BRESP"),
  ("BAYER2RGB_AXIM_WR_BRIDGE", "aw"): ("書き込み要求が有効", "要求を受け取れない(スキッドが満杯)", "要求(axreq_t)"),
  ("BAYER2RGB_AXIM_WR_BRIDGE", "w"): ("書き込みデータが有効", "データを受け取れない(スキッドが満杯)",
                                      "データ(wbeat_t)"),
  ("BAYER2RGB_AXIM_WR_BRIDGE", "b"): ("書き込み応答が有効", "WR_DMAが応答を受け取れない", "BRESP"),
}

DESC = {
  "BAYER2RGB": {"irq": "割り込み。IRQ_STATUS と IRQ_ENABLE の論理積のOR(レベル、ctrl_clk同期)"},
  "BAYER2RGB_REG": {
    "o_cfg": "現在のレジスタ値(cfg_t)。STARTのときにCDCが取り込む",
    "o_start": "フレーム開始の要求(1クロックのパルス)。CDCが受け付けられるときだけ出す",
    "o_sw_rst": "ソフトリセットの要求(1クロックのパルス)",
    "i_cdc_busy": "CDCが要求を受け渡し中",
    "i_evt": "映像系からのイベント {frame_done, rd_err, wr_err, srst_done}(各1クロックのパルス)",
    "o_irq": "割り込み(レベル)",
  },
  "BAYER2RGB_CDC": {
    "i_cfg": "REGの現在の設定(cfg_t)。STARTのとき REG_UPDATE=1 なら取り込む",
    "i_start": "フレーム開始の要求(パルス)", "i_sw_rst": "ソフトリセットの要求(パルス)",
    "o_busy": "要求の受け渡し中(この間は次の要求を出さない)",
    "o_evt": "映像系からのイベント(evt_t、ctrl_clkの1クロックのパルス)",
    "o_ctl": "フレームの設定 + start + sw_rst(ctl_t、clk同期。start と sw_rst は1クロックのパルス)",
    "i_rd_evt": "RD_DMAの状態 {busy(レベル), rd_err(パルス)}",
    "i_wr_evt": "WR_DMAの状態 {busy(レベル), frame_done(パルス), wr_err(パルス)}",
  },
  "BAYER2RGB_RD_DMA": {"o_evt": "状態 {busy(フレーム処理中・ソフトリセットの後始末中), rd_err(パルス)}"},
  "BAYER2RGB_WR_DMA": {"o_evt": "状態 {busy, frame_done(全バーストの応答を受けた、パルス), wr_err(パルス)}"},
  "BAYER2RGB_IN_CTRL": {
    "i_fifo_cnt": "出力FIFOの格納数(クレジットの判定に使う)",
    "o_cfg": "後段へ配る設定(cfg_t、1段受け直したもの)",
    "o_clr": "後段へ配るクリア(ソフトリセットの1クロックのパルス)",
    "o_stp": "ステップ {vld, fcol, frow, line, col, pix}(stp_t)",
  },
  "BAYER2RGB_BLC": {"i_stp": "ステップ(stp_t)", "o_stp": "黒レベルを引いたステップ(stp_t、レイテンシ1)"},
  "BAYER2RGB_WB": {"i_stp": "ステップ(stp_t)", "o_stp": "WBゲインを掛けたステップ(stp_t、レイテンシ2)"},
  "BAYER2RGB_LBUF": {
    "i_stp": "ステップ(stp_t)",
    "o_win": "3×(PPC+2)画素の窓 {vld, sof, eol, eof, y, oc, win}(win_t、レイテンシ2)",
    "o_sram0_ren": "SRAM0(2ライン前)の読み出し", "o_sram0_raddr": "SRAM0の読み出しアドレス(列番号)",
    "i_sram0_rdata": "SRAM0の読み出しデータ(レイテンシ1)", "o_sram0_wen": "SRAM0の書き込み(読み出しの次のクロック)",
    "o_sram0_waddr": "SRAM0の書き込みアドレス", "o_sram0_wdata": "SRAM0の書き込みデータ(SRAM1の読み出し値)",
    "o_sram1_ren": "SRAM1(1ライン前)の読み出し", "o_sram1_raddr": "SRAM1の読み出しアドレス(列番号)",
    "i_sram1_rdata": "SRAM1の読み出しデータ(レイテンシ1)", "o_sram1_wen": "SRAM1の書き込み(読み出しの次のクロック)",
    "o_sram1_waddr": "SRAM1の書き込みアドレス", "o_sram1_wdata": "SRAM1の書き込みデータ(入力のビート)",
  },
  "BAYER2RGB_DMSC": {"i_win": "窓(win_t)", "o_dm": "RGB(各14bit)とエッジ量(dm_t、レイテンシ2)"},
  "BAYER2RGB_FCS": {"i_dm": "RGBとエッジ量(dm_t)", "o_fc": "彩度を抑えたRGB(fc_t、レイテンシ3)"},
  "BAYER2RGB_GAMMA": {"i_fc": "RGB(各14bit、fc_t)", "o_gm": "RGB(各8bit、gm_t、レイテンシ3)"},
  "BAYER2RGB_OUT_FMT": {"i_gm": "RGB(各8bit、gm_t)", "o_vld": "出力ビートが有効(レイテンシ1)",
                        "o_data": "出力ビート {eof, eol, sof, rgb}(obeat_t)"},
  "BAYER2RGB_OUT_FIFO": {"i_vld": "書き込み(止められない。あふれないことはクレジットで保証)",
                         "i_data": "書き込むビート(obeat_t)", "o_cnt": "格納数(先読み2段と読み出し中を含む)"},
  "BAYER2RGB_SKID": {"i_vld": "入力が有効", "o_busy": "入力を受け取れない(FFから出す)", "i_data": "入力データ",
                     "o_vld": "出力が有効(FFから出す)", "i_busy": "出力先が受け取れない", "o_data": "出力データ(FFから出す)"},
  "BAYER2RGB_SFIFO": {"i_wvld": "書き込みが有効", "o_wbusy": "満杯(書き込めない)", "i_wdata": "書き込みデータ",
                      "o_rvld": "読み出しデータが有効(空でない)", "i_rbusy": "読み出し側が受け取れない",
                      "o_rdata": "読み出しデータ(先頭)", "o_cnt": "格納数"},
  "BAYER2RGB_SRAM_1R1W": {"clk": "クロック", "i_ren": "読み出し", "i_raddr": "読み出しアドレス", "o_rdata": "読み出しデータ(レイテンシ1。読まないときは保持)",
                          "i_wen": "書き込み", "i_waddr": "書き込みアドレス", "i_wdata": "書き込みデータ"},
  "BAYER2RGB_SYNC2": {"clk": "同期化先のクロック", "rst_n": "同期化先のリセット(Lowで INIT にする)",
                      "i_d": "同期化する信号(別クロックのFFの出力)", "o_q": "2段同期化した信号"},
}


def eval_w( expr ):
  e = expr
  for k, v in sorted(CONST.items(), key=lambda kv: -len(kv[0])):
    e = re.sub(r"\b%s\b" % k, str(v), e)
  sym = re.search(r"[A-Za-z_]", e)
  if( sym ):
    return None
  return int(eval(e))  # noqa: S307  (定数式だけ)


def parse_ports( path ):
  """モジュール名とポートの並び [(dir, type, range, name, comment)] を返す"""
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
    s = s.lstrip(",").strip()
    cm = ""
    if( "//" in s ):
      s, cm = s.split("//", 1)
      s = s.strip()
      cm = cm.strip()
    mi = re.match(r"^BAYER2RGB_VBD_IF\.(src|dst)\s+(\w+)$", s)
    if( mi ):
      ports.append(("if_"+mi.group(1), "", "", mi.group(2), cm))
      continue
    mp = re.match(r"^(input|output)\s+(\w+)\s*(\[[^\]]+\])?\s*(\w+)$", s)
    if( mp ):
      ports.append((mp.group(1), mp.group(2), mp.group(3) or "", mp.group(4), cm))
  return mod, ports


def width_of( typ, rng ):
  if( typ in TYPE_W ):
    w = TYPE_W[typ]
    dep = PPC_DEP.get(typ)
    return ("%d(%s)" % (w, dep)) if( dep ) else str(w), w
  if( rng=="" ):
    return "1", 1
  hi, lo = rng[1:-1].split(":")
  hv = eval_w(hi)
  lv = eval_w(lo)
  if( (hv is None)or(lv is None) ):
    expr = "%s-%s+1" % (hi, lo)
    expr = re.sub(r"-1-0\+1$", "", expr)
    return expr, None
  w = hv-lv+1
  for k, dep in PPC_DEP.items():
    if( k in hi ):
      return "%d(%s)" % (w, dep), w
  return str(w), w


def polarity( name, w ):
  clks = ("clk", "ctrl_clk")
  if( name in clks ):
    return "立ち上がり"
  if( name.endswith("rst_n") ):
    return "Low"
  sync = name.endswith(("_d", "_q"))
  if( (w==1)and(not(sync)) ):
    return "High"
  return "-"


def describe( mod, name ):
  mdesc = DESC.get(mod, {})
  if( name in mdesc ):
    return mdesc[name]
  if( name in COMMON ):
    return COMMON[name]
  m = re.match(r"^BAYER2RGB_(REG|MEM)_(\w+)$", name)
  if( m ):
    table = AXIL if( m.group(1)=="REG" ) else AXIM
    return table[m.group(2)]
  raise KeyError("説明がない: %s.%s" % (mod, name))


def table( mod, ports ):
  rows = ["| 信号名 | 入出力 | 信号仕様 | ビット幅 | 極性 |", "|---|---|---|---|---|"]
  for d, typ, rng, name, _cm in ports:
    if( d.startswith("if_") ):
      src = (d=="if_src")
      dw, dt = IF_W[(mod, name)]
      dv, db, dd = IF_DESC[(mod, name)]
      dep = PPC_DEP.get(dt)
      wtxt = ("%d(%s)" % (dw, dep)) if( dep ) else str(dw)
      rows.append("| %s.vld | %s | %s | 1 | High |" % (name, "出力" if( src ) else "入力", dv))
      rows.append("| %s.busy | %s | %s | 1 | High |" % (name, "入力" if( src ) else "出力", db))
      rows.append("| %s.data | %s | %s | %s | - |" % (name, "出力" if( src ) else "入力", dd, wtxt))
      continue
    wtxt, w = width_of(typ, rng)
    rows.append("| %s | %s | %s | %s | %s |" % (name, "入力" if( d=="input" ) else "出力", describe(mod, name), wtxt,
                                               polarity(name, w)))
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
    skip = fn in ("BAYER2RGB_PKG.sv", "BAYER2RGB_VBD_IF.sv")
    if( not(fn.endswith(".sv"))or(skip) ):
      continue
    mod, ports = parse_ports(os.path.join(rtl, fn))
    if( mod is None ):
      continue
    with open(os.path.join(out, mod+".md"), "w", encoding="utf-8") as f:
      f.write(table(mod, ports))
    n += 1
  print("端子表 %d モジュール: %s" % (n, out))
  return 0


if( __name__=="__main__" ):
  sys.exit(main())
