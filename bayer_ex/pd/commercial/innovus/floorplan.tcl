# ============================================================================
# 2. フロアプラン(Innovus、Stylus Common UI。雛形・未検証)
#   コアの大きさ、端子の位置、タップセル、電源配線
# ============================================================================
source [file join [file dirname [info script]] common.tcl]
bex_restore 01_init

# ---- コアの大きさ(縦横比、使用率、コアのまわりの余白 [um])
set bex_aspect 1.0
set bex_util   0.60
set bex_margin 2.0
create_floorplan -site $BEX_SITE \
  -core_density_size $bex_aspect $bex_util $bex_margin $bex_margin $bex_margin $bex_margin

# ---- 端子の位置(ASAP7 の環境と同じ考え方。データが左から右へ流れるように置く)
#   左辺: 入力側(i_vld、i_data、o_busy)    右辺: 出力側(o_vld、o_data、i_busy)
#   上辺: 設定(i_cfg)                      下辺: clk、rst_n
set bex_left   [concat {i_vld o_busy} [get_db [get_db ports i_data*] .name]]
set bex_right  [concat {o_vld i_busy} [get_db [get_db ports o_data*] .name]]
set bex_top    [get_db [get_db ports i_cfg*] .name]
set bex_bottom {clk rst_n}
edit_pin -pin $bex_left   -side Left   -layer $BEX_PIN_LAYER_H -spread_type center \
  -spacing 2 -unit TRACK -fixed_pin true -fix_overlap true
edit_pin -pin $bex_right  -side Right  -layer $BEX_PIN_LAYER_H -spread_type center \
  -spacing 2 -unit TRACK -fixed_pin true -fix_overlap true
edit_pin -pin $bex_top    -side Top    -layer $BEX_PIN_LAYER_V -spread_type center \
  -spacing 2 -unit TRACK -fixed_pin true -fix_overlap true
edit_pin -pin $bex_bottom -side Bottom -layer $BEX_PIN_LAYER_V -spread_type center \
  -spacing 4 -unit TRACK -fixed_pin true -fix_overlap true

# ---- タップセル・エンドキャップ(PDK で要るときだけ)
if {$BEX_ENDCAP_LEFT != "" && $BEX_ENDCAP_RIGHT != ""} {
  set_db add_endcaps_left_edge  $BEX_ENDCAP_LEFT
  set_db add_endcaps_right_edge $BEX_ENDCAP_RIGHT
  add_endcaps
}
if {$BEX_TAP_CELL != ""} {
  add_well_taps -cell $BEX_TAP_CELL -cell_interval $BEX_TAP_INTERVAL -checker_board
}

# ---- 電源配線
#   電源の作り方はプロセスによって違うので、PDK のリファレンスフローの
#   スクリプトをそのまま使う(BEX_PDN_TCL)
if {[file exists $BEX_PDN_TCL]} {
  source $BEX_PDN_TCL
} else {
  puts "BEX: 電源配線のスクリプトがありません: $BEX_PDN_TCL"
}

check_floorplan -out_file [file join $bex_rpt 02_floorplan_check.rpt]
bex_save 02_floorplan pre_place
exit
