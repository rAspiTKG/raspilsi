# ============================================================================
# SRAM マクロの配置(ORFS の MACRO_PLACEMENT_TCL として読む)
#
#   この版の OpenROAD の自動配置(rtl_macro_placer)は、階層つきのネットリストで
#   異常終了したので、決まった規則で置く。PPC が変わってマクロの大きさが変わっても使える。
#
#   - マクロの端子は左辺(M4)にある。コアの左端に置くものは左右を反転し(MY)、
#     右端に置くものはそのまま(R0)にして、端子をコアの内側へ向ける
#   - 面積の大きい順に左端の列へ下から積み、入らなくなったら右端の列へ積む
#   - 位置は行の高さ(0.27 um)と M4 の配線格子(0.048 um)の両方に合う 2.16 um 単位、
#     横は 0.432 um 単位にそろえる
#   - マクロどうし・コアの端との間は MACRO_PLACE_HALO の値だけ空ける
# ============================================================================
set b2r_block [ord::get_db_block]
set b2r_dbu   [[ord::get_db_tech] getDbUnitsPerMicron]
set b2r_core  [$b2r_block getCoreArea]
lassign $::env(MACRO_PLACE_HALO) b2r_hx b2r_hy

proc b2r_snap {v step org} {
  # org から step の倍数になるように切り上げる(単位は DBU)
  return [expr {$org+int(ceil(double($v-$org)/$step))*$step}]
}

set b2r_ystep [expr {round(2.16*$b2r_dbu)}]
set b2r_xstep [expr {round(0.432*$b2r_dbu)}]
set b2r_hxd   [expr {round($b2r_hx*$b2r_dbu)}]
set b2r_hyd   [expr {round($b2r_hy*$b2r_dbu)}]
set b2r_cx0   [$b2r_core xMin]
set b2r_cy0   [$b2r_core yMin]
set b2r_cx1   [$b2r_core xMax]
set b2r_cy1   [$b2r_core yMax]

# マクロを面積の大きい順に並べる
set b2r_list {}
foreach b2r_inst [$b2r_block getInsts] {
  set b2r_m [$b2r_inst getMaster]
  if {[$b2r_m getType] == "BLOCK"} {
    lappend b2r_list [list [expr {double([$b2r_m getWidth])*[$b2r_m getHeight]}] $b2r_inst]
  }
}
set b2r_list [lsort -real -decreasing -index 0 $b2r_list]

# 左の列 → 右の列の順に下から積む
set b2r_col 0
set b2r_y   [b2r_snap [expr {$b2r_cy0+$b2r_hyd}] $b2r_ystep $b2r_cy0]
foreach b2r_e $b2r_list {
  set b2r_inst [lindex $b2r_e 1]
  set b2r_m    [$b2r_inst getMaster]
  set b2r_w    [$b2r_m getWidth]
  set b2r_h    [$b2r_m getHeight]
  if {$b2r_y+$b2r_h+$b2r_hyd > $b2r_cy1} {
    incr b2r_col
    set b2r_y [b2r_snap [expr {$b2r_cy0+$b2r_hyd}] $b2r_ystep $b2r_cy0]
  }
  if {$b2r_col == 0} {
    set b2r_x [b2r_snap [expr {$b2r_cx0+$b2r_hxd}] $b2r_xstep $b2r_cx0]
    set b2r_o MY
  } elseif {$b2r_col == 1} {
    set b2r_x [expr {$b2r_cx1-$b2r_hxd-$b2r_w}]
    set b2r_x [expr {$b2r_cx0+int(floor(double($b2r_x-$b2r_cx0)/$b2r_xstep))*$b2r_xstep}]
    set b2r_o R0
  } else {
    utl::error FLW 9001 "マクロがコアの左右の列に入りません(CORE_UTILIZATION を下げてください)"
  }
  $b2r_inst setOrient $b2r_o
  $b2r_inst setLocation $b2r_x $b2r_y
  $b2r_inst setPlacementStatus FIRM
  puts [format "B2R: %-50s %-24s %s (%.3f, %.3f)" [$b2r_inst getName] [$b2r_m getName] $b2r_o \
    [expr {double($b2r_x)/$b2r_dbu}] [expr {double($b2r_y)/$b2r_dbu}]]
  set b2r_y [b2r_snap [expr {$b2r_y+$b2r_h+2*$b2r_hyd}] $b2r_ystep $b2r_cy0]
}
