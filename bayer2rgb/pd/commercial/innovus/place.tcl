# ============================================================================
# 3. 配置(Innovus、Stylus Common UI。雛形・未検証)
#   タイミングを見た配置と最適化、定数セル(TIEHI / TIELO)の挿入
# ============================================================================
source [file join [file dirname [info script]] common.tcl]
b2r_restore 02_floorplan

set_db place_global_timing_effort high
set_db place_global_cong_effort   auto
# GAMMA(24チャネル × 37個の折れ点の選択)のまわりに配線が集中するので、配置の最大密度を抑える
# (ASAP7 では使用率 30%・密度 0.42 で収束した。仕様書 14.4。値は PDK に合わせて調整する)
set_db place_global_max_density   0.65
set_db opt_new_inst_prefix        b2r_place_

place_opt_design -report_dir [file join $b2r_rpt 03_place_opt]

# 定数は TIEHI / TIELO のセルからつなぐ
set_db add_tieoffs_cells $B2R_TIE_CELLS
add_tieoffs

b2r_save 03_place pre_cts
exit
