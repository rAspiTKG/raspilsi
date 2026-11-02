# ============================================================================
# 1. 設計の読み込み(Innovus、Stylus Common UI。雛形・未検証)
#   innovus -stylus -no_gui -files innovus/init.tcl -log <出力先>/innovus_01_init
#   入力: Genus のネットリストと SDC(pd/commercial/out/foundry/genus/)
# ============================================================================
source [file join [file dirname [info script]] common.tcl]

# ---- ライブラリ・制約(Genus が書き出した数値の SDC を使う)
set BEX_SDC_FILES [list $BEX_SDC_GENUS]
read_mmmc [file join $bex_inv_dir .. setup mmmc.tcl]
read_physical -lefs [concat [list $BEX_TECH_LEF] $BEX_STD_LEF]
read_netlist [file join $BEX_GENUS_OUT bayer_ex_genus.v] -top $BEX_DESIGN

set_db init_power_nets  $BEX_POWER_NET
set_db init_ground_nets $BEX_GROUND_NET
init_design

# ---- 電源の接続(標準セルの電源端子)
connect_global_net $BEX_POWER_NET  -type pg_pin -pin_base_name $BEX_POWER_PIN  -inst_base_name *
connect_global_net $BEX_GROUND_NET -type pg_pin -pin_base_name $BEX_GROUND_PIN -inst_base_name *
connect_global_net $BEX_POWER_NET  -type tie_hi -inst_base_name *
connect_global_net $BEX_GROUND_NET -type tie_lo -inst_base_name *

# ---- 配線層・使わないセル
set_db design_bottom_routing_layer $BEX_ROUTE_BOTTOM
set_db design_top_routing_layer    $BEX_ROUTE_TOP
foreach bex_p $BEX_DONT_USE {
  set_db [get_db base_cells $bex_p] .dont_use true
}

check_design -type {timing} -out_file [file join $bex_rpt 01_init_check_design.rpt]
check_timing -verbose > [file join $bex_rpt 01_init_check_timing.rpt]
write_db [file join $bex_db 01_init.db]
exit
