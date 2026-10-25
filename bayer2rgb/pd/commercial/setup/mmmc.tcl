# ============================================================================
# MMMC(複数モード・複数コーナー)の定義(Genus / Innovus / Tempus で共通。雛形)
#
#   read_mmmc で読む。読む前に次を決めておく
#     setup/design_setup.tcl と setup/foundry_setup.tcl を source 済み
#     B2R_SDC_FILES  制約ファイルの並び
#                    Genus: 共通の SDC / Innovus・Tempus: Genus が書き出した SDC
#   Stylus Common UI のコマンド(create_timing_condition を使う形)
#   設定の変数はグローバル変数なので、:: を付けて参照する(読み込む場所によらないように)
# ============================================================================

# ---- ライブラリ(コーナーごと)
foreach b2r_c [array names ::B2R_LIB] {
  create_library_set -name libs_$b2r_c -timing $::B2R_LIB($b2r_c)
  create_timing_condition -name tc_$b2r_c -library_sets [list libs_$b2r_c]
}

# ---- 配線の RC(Quantus の技術ファイル)
foreach b2r_r [array names ::B2R_QRC] {
  create_rc_corner -name rc_$b2r_r -temperature $::B2R_RC_TEMP($b2r_r) -qrc_tech $::B2R_QRC($b2r_r)
}

# ---- 動作モード(機能モードだけ)
create_constraint_mode -name func -sdc_files $::B2R_SDC_FILES

# ---- 解析ビュー
set b2r_setup_views {}
set b2r_hold_views  {}
foreach b2r_view $::B2R_VIEWS {
  lassign $b2r_view b2r_name b2r_lc b2r_rc b2r_use
  create_delay_corner -name dc_$b2r_name -timing_condition tc_$b2r_lc -rc_corner rc_$b2r_rc
  create_analysis_view -name $b2r_name -constraint_mode func -delay_corner dc_$b2r_name
  if {$b2r_use == "setup" || $b2r_use == "both"} {
    lappend b2r_setup_views $b2r_name
  }
  if {$b2r_use == "hold" || $b2r_use == "both"} {
    lappend b2r_hold_views $b2r_name
  }
}
set_analysis_view -setup $b2r_setup_views -hold $b2r_hold_views
