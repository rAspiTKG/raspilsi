# ============================================================================
# サインオフのタイミング解析(Cadence Tempus、Stylus Common UI。雛形・未検証)
#   tempus -stylus -no_gui -files tempus/sta.tcl -log <出力先>/tempus/tempus
#   入力: Innovus の最終ネットリスト・SDC と RC コーナーごとの SPEF(innovus/signoff.tcl)
#   全ビュー(B2R_VIEWS)のセットアップ・ホールド、クロストーク(SI)を見る
# ============================================================================
set b2r_dir [file normalize [file dirname [info script]]]
source [file join $b2r_dir .. setup design_setup.tcl]
source [file join $b2r_dir .. setup foundry_setup.tcl]
set b2r_rpt [file join $B2R_TEMPUS_OUT reports]
file mkdir $B2R_TEMPUS_OUT $b2r_rpt

set_multi_cpu_usage -local_cpu $B2R_CPUS

# 制約: Innovus が書き出した SDC(入出力の仮想クロックの遅れを CTS に合わせたもの)。
#   なければ Genus の SDC
set b2r_sdc_final [file join $B2R_INNOVUS_OUT bayer2rgb_final.sdc]
if {[file exists $b2r_sdc_final]} {
  set B2R_SDC_FILES [list $b2r_sdc_final]
} else {
  set B2R_SDC_FILES [list $B2R_SDC_GENUS]
}
read_mmmc [file join $b2r_dir .. setup mmmc.tcl]
read_netlist [file join $B2R_INNOVUS_OUT bayer2rgb_final.v] -top $B2R_DESIGN
init_design

foreach b2r_r [array names B2R_QRC] {
  read_spef -rc_corner rc_$b2r_r [file join $B2R_INNOVUS_OUT bayer2rgb_$b2r_r.spef]
}

# ---- 解析の条件(OCV、CPPR、クロストーク)
set_db timing_analysis_type      ocv
set_db timing_analysis_cppr      both
set_db delaycal_enable_si        true
set_propagated_clock [all_clocks]

# ---- レポート
check_timing -verbose                         > [file join $b2r_rpt check_timing.rpt]
report_analysis_summary                       > [file join $b2r_rpt summary.rpt]
report_timing -late  -max_paths 100 -nworst 1 > [file join $b2r_rpt setup.rpt]
report_timing -early -max_paths 100 -nworst 1 > [file join $b2r_rpt hold.rpt]
report_constraint -all_violators              > [file join $b2r_rpt violators.rpt]
report_clocks                                 > [file join $b2r_rpt clocks.rpt]
# CDC の経路(clk と ctrl_clk の間。set_max_delay の確認)
report_timing -late -from [get_clocks clk] -to [get_clocks ctrl_clk] -max_paths 20 > [file join $b2r_rpt cdc_clk2ctrl.rpt]
report_timing -late -from [get_clocks ctrl_clk] -to [get_clocks clk] -max_paths 20 > [file join $b2r_rpt cdc_ctrl2clk.rpt]

# ---- ゲートレベルのシミュレーション用の SDF(最も遅いビュー)
write_sdf -view [lindex [b2r_views_for setup] 0] [file join $B2R_TEMPUS_OUT bayer2rgb_final.sdf]
exit
