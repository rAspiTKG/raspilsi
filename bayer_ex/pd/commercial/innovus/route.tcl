# ============================================================================
# 5. 配線(Innovus NanoRoute、Stylus Common UI。雛形・未検証)
#   タイミングとクロストークを見た配線、配線後の最適化(セットアップ・ホールド)
# ============================================================================
source [file join [file dirname [info script]] common.tcl]
bex_restore 04_cts

set_db route_design_with_timing_driven true
set_db route_design_with_si_driven     true
set_db route_design_antenna_diode_insertion true

route_design

# 配線後の抽出は Quantus(サインオフと同じ精度にするときは signoff)
set_db extract_rc_engine post_route
set_db delaycal_enable_si true
opt_design -post_route -setup -hold -report_dir [file join $bex_rpt 05_opt_post_route]

bex_save 05_route post_route
exit
