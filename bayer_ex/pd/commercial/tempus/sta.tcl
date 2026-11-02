# ============================================================================
# サインオフのタイミング解析(Cadence Tempus、Stylus Common UI。雛形・未検証)
#   tempus -stylus -no_gui -files tempus/sta.tcl -log <出力先>/tempus
#   入力: Innovus の最終ネットリスト・SDC と RC コーナーごとの SPEF(innovus/signoff.tcl)
#   全ビュー(BEX_VIEWS)のセットアップ・ホールド、クロストーク(SI)を見る
# ============================================================================
set bex_dir [file normalize [file dirname [info script]]]
source [file join $bex_dir .. setup design_setup.tcl]
source [file join $bex_dir .. setup foundry_setup.tcl]
set bex_rpt [file join $BEX_TEMPUS_OUT reports]
file mkdir $BEX_TEMPUS_OUT $bex_rpt

set_multi_cpu_usage -local_cpu $BEX_CPUS

# 制約: Innovus が書き出した SDC(入出力の仮想クロックの遅れを CTS に合わせたもの)。
#   なければ Genus の SDC
set bex_sdc_final [file join $BEX_INNOVUS_OUT bayer_ex_final.sdc]
if {[file exists $bex_sdc_final]} {
  set BEX_SDC_FILES [list $bex_sdc_final]
} else {
  set BEX_SDC_FILES [list $BEX_SDC_GENUS]
}
read_mmmc [file join $bex_dir .. setup mmmc.tcl]
read_netlist [file join $BEX_INNOVUS_OUT bayer_ex_final.v] -top $BEX_DESIGN
init_design

foreach bex_r [array names BEX_QRC] {
  read_spef -rc_corner rc_$bex_r [file join $BEX_INNOVUS_OUT bayer_ex_$bex_r.spef]
}

# ---- 解析の条件(OCV、CPPR、クロストーク)
set_db timing_analysis_type      ocv
set_db timing_analysis_cppr      both
set_db delaycal_enable_si        true
set_propagated_clock [get_clocks clk]

# ---- レポート
check_timing -verbose                         > [file join $bex_rpt check_timing.rpt]
report_analysis_summary                       > [file join $bex_rpt summary.rpt]
report_timing -late  -max_paths 100 -nworst 1 > [file join $bex_rpt setup.rpt]
report_timing -early -max_paths 100 -nworst 1 > [file join $bex_rpt hold.rpt]
report_constraint -all_violators              > [file join $bex_rpt violators.rpt]
report_clocks                                 > [file join $bex_rpt clocks.rpt]

# ---- ゲートレベルのシミュレーション用の SDF(最も遅いビュー)
write_sdf -view [lindex [bex_views_for setup] 0] [file join $BEX_TEMPUS_OUT bayer_ex_final.sdf]
exit
