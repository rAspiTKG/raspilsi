# ============================================================================
# MMMC(複数モード・複数コーナー)の定義(Genus / Innovus / Tempus で共通。雛形)
#
#   read_mmmc で読む。読む前に次を決めておく
#     setup/design_setup.tcl と setup/foundry_setup.tcl を source 済み
#     BEX_SDC_FILES  制約ファイルの並び
#                    Genus: 共通の SDC / Innovus・Tempus: Genus が書き出した SDC
#   Stylus Common UI のコマンド(create_timing_condition を使う形)
#   設定の変数はグローバル変数なので、:: を付けて参照する(読み込む場所によらないように)
# ============================================================================

# ---- ライブラリ(コーナーごと)
foreach bex_c [array names ::BEX_LIB] {
  create_library_set -name libs_$bex_c -timing $::BEX_LIB($bex_c)
  create_timing_condition -name tc_$bex_c -library_sets [list libs_$bex_c]
}

# ---- 配線の RC(Quantus の技術ファイル)
foreach bex_r [array names ::BEX_QRC] {
  create_rc_corner -name rc_$bex_r -temperature $::BEX_RC_TEMP($bex_r) -qrc_tech $::BEX_QRC($bex_r)
}

# ---- 動作モード(機能モードだけ)
create_constraint_mode -name func -sdc_files $::BEX_SDC_FILES

# ---- 解析ビュー
set bex_setup_views {}
set bex_hold_views  {}
foreach bex_view $::BEX_VIEWS {
  lassign $bex_view bex_name bex_lc bex_rc bex_use
  create_delay_corner -name dc_$bex_name -timing_condition tc_$bex_lc -rc_corner rc_$bex_rc
  create_analysis_view -name $bex_name -constraint_mode func -delay_corner dc_$bex_name
  if {$bex_use == "setup" || $bex_use == "both"} {
    lappend bex_setup_views $bex_name
  }
  if {$bex_use == "hold" || $bex_use == "both"} {
    lappend bex_hold_views $bex_name
  }
}
set_analysis_view -setup $bex_setup_views -hold $bex_hold_views
