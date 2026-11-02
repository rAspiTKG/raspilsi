# ============================================================================
# Innovus の各段階で共通の設定(Stylus Common UI。雛形・未検証)
#   各段階のスクリプト(init / floorplan / place / cts / route / signoff)が最初に読む。
#   段階ごとに Innovus を起動し、前の段階のデータベースを read_db で読む。
# ============================================================================
set b2r_inv_dir [file normalize [file dirname [info script]]]
source [file join $b2r_inv_dir .. setup design_setup.tcl]
source [file join $b2r_inv_dir .. setup foundry_setup.tcl]
set b2r_rpt [file join $B2R_INNOVUS_OUT reports]
set b2r_db  [file join $B2R_INNOVUS_OUT db]
file mkdir $B2R_INNOVUS_OUT $b2r_rpt $b2r_db

set_multi_cpu_usage -local_cpu $B2R_CPUS

# 前の段階のデータベースを読む
proc b2r_restore {stage} {
  global b2r_db
  read_db [file join $b2r_db $stage.db]
}

# この段階のデータベースを保存し、タイミングのレポートを出す
#   mode: pre_place / pre_cts / post_cts / post_route
proc b2r_save {stage mode} {
  global b2r_db b2r_rpt
  write_db [file join $b2r_db $stage.db]
  time_design -$mode -report_dir [file join $b2r_rpt $stage] -report_prefix $stage
  if {$mode == "post_cts" || $mode == "post_route"} {
    time_design -$mode -hold -report_dir [file join $b2r_rpt $stage] -report_prefix ${stage}_hold
  }
  report_area > [file join $b2r_rpt ${stage}_area.rpt]
}
