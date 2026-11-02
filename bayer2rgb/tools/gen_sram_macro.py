#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
1R1W SRAM の仮マクロ(LEF / Liberty / Verilog のブラックボックス)を作る

  python3 tools/gen_sram_macro.py --platform asap7 --sizes 480x112,64x128,64x144,32x195 --outdir <出力>

公開PDK で配置配線を試すための「形と端子とタイミングの目安」だけを持つマクロです
(中身のレイアウトはない)。量産では SRAM コンパイラのマクロに置き換えます。

マクロ名: b2r_sram1r1w_<ワード数>x<ビット幅>
端子    : clk, ren, raddr[AW-1:0], rdata[DW-1:0], wen, waddr[AW-1:0], wdata[DW-1:0], VDD, VSS
          (1クロック。読み出しの遅れ1。同じアドレスの同時読み書きはしない)

asap7 の形は OpenROAD-flow-scripts の fakeregfile(FakeRAM 2.0 の出力)にそろえています。
  - 信号端子: 左の辺、M4、24nm 角、0.096um 間隔(M4 のトラック2本ごと)
  - 電源    : M4 の横の帯(VSS / VDD を 0.768um ずつずらして 1.536um 周期)
  - 配線禁止: M1〜M3 は全面、M4 は左右の端を除く
  - 大きさ  : 面積 = ビット数 × 0.06um2(1R1W を想定)。高さは端子が並ぶ長さ以上で、
              幅は 0.19um、高さは 1.4um の倍数に切り上げる
  - タイミング: アクセス時間 = 0.10 + 0.012 × log2(ビット数) [ns]、セットアップ・ホールド 0.05ns
"""
import argparse
import math
import os
import sys


# ============================================================================
# プラットフォームの値
# ============================================================================
PLATFORMS = {
  "asap7": {
    "pin_layer": "M4",
    "pin_w": 0.024,          # 端子の大きさ(um)
    "pin_pitch": 0.096,      # 端子の間隔(um)
    "pin_y0": 0.096,         # 最初の端子の下端(um)
    "pwr_w": 0.096,          # 電源の帯の太さ(um)
    "pwr_pitch": 1.536,      # 電源の帯の周期(um)
    "pwr_vss_y0": 0.048,
    "pwr_vdd_y0": 0.816,
    "pwr_x_margin": 0.096,   # 電源の帯の左右の余白(um)
    "obs_full": ["M1", "M2", "M3"],
    "obs_margin": 0.1,       # M4 の配線禁止の左右の余白(um)
    "snap_w": 0.19,
    "snap_h": 1.4,
    "area_per_bit": 0.06,    # um2
    "min_w": 4.18,
    "voltage": 0.7,
  },
}


def snap_up( v, s ):
  return math.ceil((v/s)-1e-9)*s


def macro_name( depth, width ):
  return "b2r_sram1r1w_%dx%d" % (depth, width)


def addr_bits( depth ):
  return max(1, (depth-1).bit_length())


# ============================================================================
# 端子の並び(下から): wdata, waddr, wen, clk, ren, raddr, rdata。グループの間は2つ空ける
# ============================================================================
def pin_list( depth, width ):
  aw = addr_bits(depth)
  groups = [
    [("wdata[%d]" % i, "INPUT") for i in range(width)],
    [("waddr[%d]" % i, "INPUT") for i in range(aw)],
    [("wen", "INPUT")],
    [("clk", "INPUT")],
    [("ren", "INPUT")],
    [("raddr[%d]" % i, "INPUT") for i in range(aw)],
    [("rdata[%d]" % i, "OUTPUT") for i in range(width)],
  ]
  out = []
  slot = 0
  for g in groups:
    for name, d in g:
      out.append((name, d, slot))
      slot += 1
    slot += 2
  return out, slot


def geometry( p, depth, width ):
  pins, nslot = pin_list(depth, width)
  span = p["pin_y0"]+(nslot*p["pin_pitch"])+p["pin_y0"]
  area = depth*width*p["area_per_bit"]
  h = max(span, math.sqrt(area*2.0))
  h = snap_up(h, p["snap_h"])
  w = max(p["min_w"], area/h)
  w = snap_up(w, p["snap_w"])
  return pins, round(w, 3), round(h, 3)


# ============================================================================
# LEF
# ============================================================================
def write_lef( path, p, name, depth, width, pins, w, h ):
  f = []
  f.append("# BAYER2RGB 用の 1R1W SRAM の仮マクロ(tools/gen_sram_macro.py で生成)")
  f.append("VERSION 5.7 ;")
  f.append('BUSBITCHARS "[]" ;')
  f.append("MACRO %s" % name)
  f.append("  FOREIGN %s 0 0 ;" % name)
  f.append("  SYMMETRY X Y R90 ;")
  f.append("  SIZE %.3f BY %.3f ;" % (w, h))
  f.append("  CLASS BLOCK ;")
  for pname, d, slot in pins:
    y = p["pin_y0"]+(slot*p["pin_pitch"])
    f.append("  PIN %s" % pname)
    f.append("    DIRECTION %s ;" % d)
    f.append("    USE %s ;" % ("CLOCK" if( pname=="clk" ) else "SIGNAL"))
    f.append("    SHAPE ABUTMENT ;")
    f.append("    PORT")
    f.append("      LAYER %s ;" % p["pin_layer"])
    f.append("      RECT %.3f %.3f %.3f %.3f ;" % (0.0, y, p["pin_w"], y+p["pin_w"]))
    f.append("    END")
    f.append("  END %s" % pname)
  for net, use, y0 in (("VSS", "GROUND", p["pwr_vss_y0"]), ("VDD", "POWER", p["pwr_vdd_y0"])):
    f.append("  PIN %s" % net)
    f.append("    DIRECTION INOUT ;")
    f.append("    USE %s ;" % use)
    f.append("    PORT")
    f.append("      LAYER %s ;" % p["pin_layer"])
    y = y0
    while( (y+p["pwr_w"])<=h ):
      f.append("      RECT %.3f %.3f %.3f %.3f ;" % (p["pwr_x_margin"], y, w-p["pwr_x_margin"], y+p["pwr_w"]))
      y += p["pwr_pitch"]
    f.append("    END")
    f.append("  END %s" % net)
  f.append("  OBS")
  for layer in p["obs_full"]:
    f.append("    LAYER %s ;" % layer)
    f.append("    RECT 0 0 %.3f %.3f ;" % (w, h))
  f.append("    LAYER %s ;" % p["pin_layer"])
  f.append("    RECT %.3f 0 %.3f %.3f ;" % (p["obs_margin"], w-p["obs_margin"], h))
  f.append("  END")
  f.append("END %s" % name)
  f.append("")
  f.append("END LIBRARY")
  with open(path, "w", encoding="utf-8") as fp:
    fp.write("\n".join(f)+"\n")


# ============================================================================
# Liberty(単位 ns / pF。ASAP7 の fakeram と同じ)
# ============================================================================
def write_lib( path, p, name, depth, width, w, h ):
  aw = addr_bits(depth)
  t_acc = 0.10+(0.012*math.log2(depth*width))
  t_su = 0.050
  t_hd = 0.050
  t_min = max(0.20, t_acc)
  tr = '"0.009, 0.227"'
  ld = '"0.005, 0.500"'

  def tbl2( v ):
    return '"%.3f, %.3f", "%.3f, %.3f"' % (v, v, v, v)

  def constraint( related, kind, v ):
    s = []
    s.append("    timing() {")
    s.append("      related_pin : %s ;" % related)
    s.append("      timing_type : %s ;" % kind)
    for c in ("rise_constraint", "fall_constraint"):
      s.append("      %s(%s_constraint) {" % (c, name))
      s.append("        index_1 (%s);" % tr)
      s.append("        index_2 (%s);" % tr)
      s.append("        values (%s);" % tbl2(v))
      s.append("      }")
    s.append("    }")
    return s

  def in_pin( kind, pname, bus_type=None ):
    s = []
    if( kind=="bus" ):
      s.append("  bus(%s) {" % pname)
      s.append("    bus_type : %s ;" % bus_type)
    else:
      s.append("  pin(%s) {" % pname)
    s.append("    direction : input ;")
    s.append("    capacitance : 0.005 ;")
    s += constraint("clk", "setup_rising", t_su)
    s += constraint("clk", "hold_rising", t_hd)
    s.append("  }")
    return s

  f = []
  f.append("/* BAYER2RGB 用の 1R1W SRAM の仮マクロ(tools/gen_sram_macro.py で生成) */")
  f.append("library(%s) {" % name)
  f.append("  technology (cmos) ;")
  f.append("  delay_model : table_lookup ;")
  f.append('  time_unit : "1ns" ;')
  f.append('  voltage_unit : "1V" ;')
  f.append('  current_unit : "1uA" ;')
  f.append('  leakage_power_unit : "1uW" ;')
  f.append("  capacitive_load_unit (1,pf) ;")
  f.append('  pulling_resistance_unit : "1kohm" ;')
  f.append("  nom_process : 1 ;")
  f.append("  nom_temperature : 25.0 ;")
  f.append("  nom_voltage : %.2f ;" % p["voltage"])
  f.append("  operating_conditions(typ) {")
  f.append("    process : 1 ;")
  f.append("    temperature : 25.0 ;")
  f.append("    voltage : %.2f ;" % p["voltage"])
  f.append("    tree_type : balanced_tree ;")
  f.append("  }")
  f.append("  default_operating_conditions : typ ;")
  f.append("  default_max_transition : 0.227 ;")
  f.append("  default_input_pin_cap : 0.0 ;")
  f.append("  default_output_pin_cap : 0.0 ;")
  f.append("  default_inout_pin_cap : 0.0 ;")
  f.append("  default_fanout_load : 1 ;")
  f.append("  default_cell_leakage_power : 0 ;")
  for k in ("slew_lower_threshold_pct_fall", "slew_lower_threshold_pct_rise"):
    f.append("  %s : 20.0 ;" % k)
  for k in ("slew_upper_threshold_pct_fall", "slew_upper_threshold_pct_rise"):
    f.append("  %s : 80.0 ;" % k)
  for k in ("input_threshold_pct_fall", "input_threshold_pct_rise", "output_threshold_pct_fall", "output_threshold_pct_rise"):
    f.append("  %s : 50.0 ;" % k)
  f.append("  slew_derate_from_library : 1.0 ;")
  f.append("  lu_table_template(%s_delay) {" % name)
  f.append("    variable_1 : input_net_transition ;")
  f.append("    variable_2 : total_output_net_capacitance ;")
  f.append('    index_1 ("1000, 1001");')
  f.append('    index_2 ("1000, 1001");')
  f.append("  }")
  f.append("  lu_table_template(%s_slew) {" % name)
  f.append("    variable_1 : total_output_net_capacitance ;")
  f.append('    index_1 ("1000, 1001");')
  f.append("  }")
  f.append("  lu_table_template(%s_constraint) {" % name)
  f.append("    variable_1 : related_pin_transition ;")
  f.append("    variable_2 : constrained_pin_transition ;")
  f.append('    index_1 ("1000, 1001");')
  f.append('    index_2 ("1000, 1001");')
  f.append("  }")
  for tname, bw in (("DATA", width), ("ADDR", aw)):
    f.append("  type (%s_%s) {" % (name, tname))
    f.append("    base_type : array ;")
    f.append("    data_type : bit ;")
    f.append("    bit_width : %d ;" % bw)
    f.append("    bit_from : %d ;" % (bw-1))
    f.append("    bit_to : 0 ;")
    f.append("    downto : true ;")
    f.append("  }")
  f.append("cell(%s) {" % name)
  f.append("  area : %.3f ;" % (w*h))
  f.append("  interface_timing : true ;")
  f.append("  dont_touch : true ;")
  f.append("  dont_use : true ;")
  f.append("  pin(clk) {")
  f.append("    direction : input ;")
  f.append("    capacitance : 0.025 ;")
  f.append("    clock : true ;")
  f.append("    min_period : %.3f ;" % t_min)
  f.append("  }")
  f.append("  bus(rdata) {")
  f.append("    bus_type : %s_DATA ;" % name)
  f.append("    direction : output ;")
  f.append("    max_capacitance : 0.500 ;")
  f.append("    timing() {")
  f.append('      related_pin : "clk" ;')
  f.append("      timing_type : rising_edge ;")
  f.append("      timing_sense : non_unate ;")
  for c in ("cell_rise", "cell_fall"):
    f.append("      %s(%s_delay) {" % (c, name))
    f.append("        index_1 (%s);" % tr)
    f.append("        index_2 (%s);" % ld)
    f.append("        values (%s);" % tbl2(t_acc))
    f.append("      }")
  for c in ("rise_transition", "fall_transition"):
    f.append("      %s(%s_slew) {" % (c, name))
    f.append("        index_1 (%s);" % ld)
    f.append('        values ("0.009, 0.227");')
    f.append("      }")
  f.append("    }")
  f.append("  }")
  f += in_pin("pin", "ren")
  f += in_pin("pin", "wen")
  f += in_pin("bus", "raddr", "%s_ADDR" % name)
  f += in_pin("bus", "waddr", "%s_ADDR" % name)
  f += in_pin("bus", "wdata", "%s_DATA" % name)
  f.append("}")
  f.append("}")
  with open(path, "w", encoding="utf-8") as fp:
    fp.write("\n".join(f)+"\n")
  return t_acc


# ============================================================================
# Verilog のブラックボックス
# ============================================================================
def verilog_bb( name, depth, width ):
  aw = addr_bits(depth)
  ra = "[%d:0]" % (aw-1)
  rd = "[%d:0]" % (width-1)
  fw = max(len(ra), len(rd))
  s = []
  s.append("(* blackbox *)")
  s.append("module %s (" % name)
  s.append("  input  wire %s clk" % "".ljust(fw))
  s.append(" ,input  wire %s ren" % "".ljust(fw))
  s.append(" ,input  wire %s raddr" % ra.ljust(fw))
  s.append(" ,output wire %s rdata" % rd.ljust(fw))
  s.append(" ,input  wire %s wen" % "".ljust(fw))
  s.append(" ,input  wire %s waddr" % ra.ljust(fw))
  s.append(" ,input  wire %s wdata" % rd.ljust(fw))
  s.append(");")
  s.append("endmodule")
  return "\n".join(s)


def main():
  ap = argparse.ArgumentParser(description="1R1W SRAM の仮マクロを作る")
  ap.add_argument("--platform", default="asap7", choices=sorted(PLATFORMS.keys()))
  ap.add_argument("--sizes", required=True, help="ワード数xビット幅 をカンマで区切る(例 480x112,64x128)")
  ap.add_argument("--outdir", required=True)
  a = ap.parse_args()
  p = PLATFORMS[a.platform]
  os.makedirs(a.outdir, exist_ok=True)
  sizes = []
  for t in a.sizes.split(","):
    d, wd = t.lower().split("x")
    sizes.append((int(d), int(wd)))
  bbs = ["// BAYER2RGB 用の 1R1W SRAM の仮マクロ(ブラックボックス。tools/gen_sram_macro.py で生成)"]
  rows = []
  for depth, width in sizes:
    name = macro_name(depth, width)
    pins, w, h = geometry(p, depth, width)
    write_lef(os.path.join(a.outdir, name+".lef"), p, name, depth, width, pins, w, h)
    t_acc = write_lib(os.path.join(a.outdir, name+".lib"), p, name, depth, width, w, h)
    bbs.append(verilog_bb(name, depth, width))
    rows.append("%-24s %4d x %4d  %7.3f x %7.3f um  面積 %8.1f um2  端子 %3d  アクセス %.3f ns" % (
      name, depth, width, w, h, w*h, len(pins)+2, t_acc))
  with open(os.path.join(a.outdir, "b2r_sram_macros.v"), "w", encoding="utf-8") as fp:
    fp.write("\n\n".join(bbs)+"\n")
  with open(os.path.join(a.outdir, "macros.txt"), "w", encoding="utf-8") as fp:
    fp.write("\n".join(rows)+"\n")
  print("\n".join(rows))
  return 0


if( __name__=="__main__" ):
  sys.exit(main())
