# ============================================================================
# 3. 配置(Innovus、Stylus Common UI。雛形・未検証)
#   タイミングを見た配置と最適化、定数セル(TIEHI / TIELO)の挿入
# ============================================================================
source [file join [file dirname [info script]] common.tcl]
bex_restore 02_floorplan

set_db place_global_timing_effort high
set_db place_global_cong_effort   auto
set_db opt_new_inst_prefix        bex_place_

place_opt_design -report_dir [file join $bex_rpt 03_place_opt]

# 定数は TIEHI / TIELO のセルからつなぐ
set_db add_tieoffs_cells $BEX_TIE_CELLS
add_tieoffs

bex_save 03_place pre_cts
exit
