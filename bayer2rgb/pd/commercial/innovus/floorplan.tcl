# ============================================================================
# 2. フロアプラン(Innovus、Stylus Common UI。雛形・未検証)
#   コアの大きさ、端子の位置、SRAM マクロの配置、タップセル、電源配線
# ============================================================================
source [file join [file dirname [info script]] common.tcl]
b2r_restore 01_init

# ---- コアの大きさ(縦横比、使用率、コアのまわりの余白 [um])
#   GAMMA のまわりに配線が集中するので、使用率は控えめにしておく(仕様書 14.4)
set b2r_aspect 1.0
set b2r_util   0.50
set b2r_margin 5.0
create_floorplan -site $B2R_SITE \
  -core_density_size $b2r_aspect $b2r_util $b2r_margin $b2r_margin $b2r_margin $b2r_margin

# ---- 端子の位置
#   AXI4 マスタ(BAYER2RGB_MEM_*、clk)は下辺、AXI4-Lite(BAYER2RGB_REG_*、ctrl_clk、irq)は上辺。
#   左右の辺は SRAM マクロを置くために空けておく(ASAP7 の環境と同じ考え方)
set b2r_mem_pins [concat {clk rst_n} [get_db [get_db ports BAYER2RGB_MEM_*] .name]]
set b2r_reg_pins [concat {ctrl_clk ctrl_rst_n irq} [get_db [get_db ports BAYER2RGB_REG_*] .name]]
edit_pin -pin $b2r_mem_pins -side Bottom -layer $B2R_PIN_LAYER_V -spread_type center \
  -spacing 2 -unit TRACK -fixed_pin true -fix_overlap true
edit_pin -pin $b2r_reg_pins -side Top    -layer $B2R_PIN_LAYER_V -spread_type center \
  -spacing 2 -unit TRACK -fixed_pin true -fix_overlap true

# ---- SRAM マクロの配置
#   B2R_MACRO_PLACE_TCL があれば手で決めた位置(place_inst)、なければ自動で置く
set b2r_macros [get_db insts -if {.base_cell.class == block}]
if {[info exists B2R_MACRO_PLACE_TCL] && [file exists $B2R_MACRO_PLACE_TCL]} {
  source $B2R_MACRO_PLACE_TCL
} elseif {[llength $b2r_macros] > 0} {
  place_design -concurrent_macros
}
if {[llength $b2r_macros] > 0} {
  set_db $b2r_macros .place_status fixed
  # マクロのまわりに標準セルと配線を置かない幅 [um]
  create_place_halo -all_blocks -halo_deltas {2 2 2 2}
  create_route_halo -all_blocks -bottom_layer $B2R_ROUTE_BOTTOM -top_layer $B2R_PIN_LAYER_H -space 1
}

# ---- タップセル・エンドキャップ(PDK で要るときだけ)
if {$B2R_ENDCAP_LEFT != "" && $B2R_ENDCAP_RIGHT != ""} {
  set_db add_endcaps_left_edge  $B2R_ENDCAP_LEFT
  set_db add_endcaps_right_edge $B2R_ENDCAP_RIGHT
  add_endcaps
}
if {$B2R_TAP_CELL != ""} {
  add_well_taps -cell $B2R_TAP_CELL -cell_interval $B2R_TAP_INTERVAL -checker_board
}

# ---- 電源配線
#   電源の作り方はプロセスによって違うので、PDK のリファレンスフローの
#   スクリプトをそのまま使う(B2R_PDN_TCL)
if {[file exists $B2R_PDN_TCL]} {
  source $B2R_PDN_TCL
} else {
  puts "B2R: 電源配線のスクリプトがありません: $B2R_PDN_TCL"
}

check_floorplan -out_file [file join $b2r_rpt 02_floorplan_check.rpt]
b2r_save 02_floorplan pre_place
exit
