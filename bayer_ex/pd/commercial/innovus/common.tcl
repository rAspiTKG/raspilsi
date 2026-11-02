# ============================================================================
# Innovus の各段階で共通の設定(Stylus Common UI。雛形・未検証)
#   各段階のスクリプト(init / floorplan / place / cts / route / signoff)が最初に読む。
#   段階ごとに Innovus を起動し、前の段階のデータベースを read_db で読む。
# ============================================================================
set bex_inv_dir [file normalize [file dirname [info script]]]
source [file join $bex_inv_dir .. setup design_setup.tcl]
source [file join $bex_inv_dir .. setup foundry_setup.tcl]
set bex_rpt [file join $BEX_INNOVUS_OUT reports]
set bex_db  [file join $BEX_INNOVUS_OUT db]
file mkdir $BEX_INNOVUS_OUT $bex_rpt $bex_db

set_multi_cpu_usage -local_cpu $BEX_CPUS

# 前の段階のデータベースを読む
proc bex_restore {stage} {
  global bex_db
  read_db [file join $bex_db $stage.db]
}

# この段階のデータベースを保存し、タイミングのレポートを出す
#   mode: pre_place / pre_cts / post_cts / post_route
proc bex_save {stage mode} {
  global bex_db bex_rpt
  write_db [file join $bex_db $stage.db]
  time_design -$mode -report_dir [file join $bex_rpt $stage] -report_prefix $stage
  if {$mode == "post_cts" || $mode == "post_route"} {
    time_design -$mode -hold -report_dir [file join $bex_rpt $stage] -report_prefix ${stage}_hold
  }
  report_area > [file join $bex_rpt ${stage}_area.rpt]
}
