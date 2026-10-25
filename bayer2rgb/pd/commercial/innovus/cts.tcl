# ============================================================================
# 4. クロックツリー(Innovus CCOpt、Stylus Common UI。雛形・未検証)
#   clk(400 MHz)と ctrl_clk(100 MHz)の2本。2つは非同期で、木をつながない
# ============================================================================
source [file join [file dirname [info script]] common.tcl]
b2r_restore 03_place

# ---- クロックの配線層(PDK の推奨に合わせる。太線・間隔の規則があれば -route_rule を足す)
create_route_type -name b2r_clk_rt \
  -bottom_preferred_layer $B2R_CLK_LAYER_BOTTOM -top_preferred_layer $B2R_CLK_LAYER_TOP
set_db cts_route_type_top   b2r_clk_rt
set_db cts_route_type_trunk b2r_clk_rt
set_db cts_route_type_leaf  b2r_clk_rt

# ---- 使うセルと目標(値は ns。PDK の推奨値に直す)
set_db cts_buffer_cells       $B2R_CTS_BUF_CELLS
set_db cts_inverter_cells     $B2R_CTS_INV_CELLS
set_db cts_clock_gating_cells $B2R_CTS_ICG_CELLS
set_db cts_target_max_transition_time 0.08
set_db cts_target_skew                0.05

create_clock_tree_spec -out_file [file join $b2r_rpt 04_cts.spec]
ccopt_design -report_dir [file join $b2r_rpt 04_ccopt]

# ---- 入出力の相手のクロック(仮想クロック clk_io / ctrl_clk_io)の遅れ
#   SDC は入出力の遅延を仮想クロックから測る(syn/constraints/bayer2rgb.sdc)。その遅れを
#   クロックツリーの実際の遅れに合わせないと、入力の経路に不要なホールド用バッファが入る
#   (仕様書 14.4)。update_io_latency で、仮想クロックの遅れをクロックツリーの遅れに
#   合わせる。ccopt_design の中で更新されるか、コマンド名が同じかは版によって違うので、
#   マニュアルで確認する。SoC で決めた値(B2R_CLK_LATENCY など)をそのまま使うときは
#   更新しない
if {[llength [info commands update_io_latency]] > 0} {
  update_io_latency
}

# ---- ホールドの修正(セットアップも崩さない)
opt_design -post_cts -hold -report_dir [file join $b2r_rpt 04_opt_hold]

report_clock_trees     > [file join $b2r_rpt 04_clock_trees.rpt]
report_skew_groups     > [file join $b2r_rpt 04_skew_groups.rpt]

b2r_save 04_cts post_cts
exit
