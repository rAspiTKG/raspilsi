# ============================================================================
# 6. 仕上げと出力(Innovus、Stylus Common UI。雛形・未検証)
#   フィラー、配線の検査、寄生の抽出(Quantus)、出力(ネットリスト・DEF・SPEF・SDF・GDS)
#   出力は Tempus(tempus/sta.tcl)、Conformal(lec/)、Pegasus(DRC / LVS)が使う
#   (ネットリスト・DEF・SPEF・SDF・SDC・GDS)
# ============================================================================
source [file join [file dirname [info script]] common.tcl]
b2r_restore 05_route

# ---- フィラー(デカップ付きのフィラーを先に並べる)
set_db add_fillers_cells [concat $B2R_DECAP_CELLS $B2R_FILLER_CELLS]
add_fillers
route_eco -fix_drc

# ---- 検査
check_drc          -out_file [file join $b2r_rpt 06_check_drc.rpt]
check_connectivity -out_file [file join $b2r_rpt 06_check_connectivity.rpt]
check_process_antenna -out_file [file join $b2r_rpt 06_check_antenna.rpt]

# ---- 寄生の抽出(Quantus、サインオフの精度)と RC コーナーごとの SPEF
set_db extract_rc_engine post_route
set_db extract_rc_effort_level signoff
extract_rc
foreach b2r_r [array names B2R_QRC] {
  write_parasitics -rc_corner rc_$b2r_r -spef_file [file join $B2R_INNOVUS_OUT bayer2rgb_$b2r_r.spef]
}

# ---- タイミング・電力
time_design -post_route       -report_dir [file join $b2r_rpt 06_signoff] -report_prefix 06_signoff
time_design -post_route -hold -report_dir [file join $b2r_rpt 06_signoff] -report_prefix 06_signoff_hold
report_power -out_file [file join $b2r_rpt 06_power.rpt]

# ---- 出力
write_db      [file join $b2r_db 06_signoff.db]
write_netlist [file join $B2R_INNOVUS_OUT bayer2rgb_final.v]
write_netlist -include_pg_ports -exclude_insts_of_cells [concat $B2R_FILLER_CELLS] \
  [file join $B2R_INNOVUS_OUT bayer2rgb_final_pg.v]
write_def -routing [file join $B2R_INNOVUS_OUT bayer2rgb_final.def]
write_sdf -view [lindex [b2r_views_for setup] 0] [file join $B2R_INNOVUS_OUT bayer2rgb_final.sdf]
# 制約(CTS で更新した入出力の仮想クロックの遅れを含む)。Tempus はこれを読む
write_sdc -view [lindex [b2r_views_for setup] 0] [file join $B2R_INNOVUS_OUT bayer2rgb_final.sdc]
write_stream [file join $B2R_INNOVUS_OUT bayer2rgb_final.gds] \
  -map_file $B2R_STREAM_MAP -merge $B2R_GDS_FILES -mode all
exit
