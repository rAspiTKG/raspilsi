# ============================================================================
# 1. 設計の読み込み(Innovus、Stylus Common UI。雛形・未検証)
#   innovus -stylus -no_gui -files innovus/init.tcl -log <出力先>/innovus/log/init
#   入力: Genus のネットリストと SDC(pd/commercial/out/<名前>/genus/)
# ============================================================================
source [file join [file dirname [info script]] common.tcl]

# ---- ライブラリ・制約(Genus が書き出した数値の SDC を使う)
set B2R_SDC_FILES [list $B2R_SDC_GENUS]
read_mmmc [file join $b2r_inv_dir .. setup mmmc.tcl]
read_physical -lefs [concat [list $B2R_TECH_LEF] $B2R_STD_LEF $B2R_MEM_LEF]
read_netlist [file join $B2R_GENUS_OUT bayer2rgb_genus.v] -top $B2R_DESIGN

set_db init_power_nets  $B2R_POWER_NET
set_db init_ground_nets $B2R_GROUND_NET
init_design

# ---- 電源の接続(標準セルとマクロの電源端子)
connect_global_net $B2R_POWER_NET  -type pg_pin -pin_base_name $B2R_POWER_PIN  -inst_base_name *
connect_global_net $B2R_GROUND_NET -type pg_pin -pin_base_name $B2R_GROUND_PIN -inst_base_name *
connect_global_net $B2R_POWER_NET  -type tie_hi -inst_base_name *
connect_global_net $B2R_GROUND_NET -type tie_lo -inst_base_name *

# ---- 配線層・使わないセル
set_db design_bottom_routing_layer $B2R_ROUTE_BOTTOM
set_db design_top_routing_layer    $B2R_ROUTE_TOP
foreach b2r_p $B2R_DONT_USE {
  set_db [get_db base_cells $b2r_p] .dont_use true
}

# ---- 同期化セルは最適化しない
foreach b2r_c $B2R_SYNC2_CELLS {
  set b2r_i [get_db insts -if ".base_cell.base_name == $b2r_c"]
  if {[llength $b2r_i] > 0} {
    set_db $b2r_i .dont_touch true
  }
}

check_design -type {timing} -out_file [file join $b2r_rpt 01_init_check_design.rpt]
check_timing -verbose > [file join $b2r_rpt 01_init_check_timing.rpt]
write_db [file join $b2r_db 01_init.db]
exit
