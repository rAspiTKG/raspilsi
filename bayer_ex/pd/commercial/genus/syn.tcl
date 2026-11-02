# ============================================================================
# BAYER_EX の論理合成(Cadence Genus、Stylus Common UI。雛形・未検証)
#
#   genus -batch -files genus/syn.tcl -log <出力先>/genus   (Makefile の make syn)
#
#   入力: rtl/ の RTL(トップは BAYER_EX)、syn/constraints/bayer_ex.sdc、setup/ の PDK・MMMC の設定
#   出力: <BEX_GENUS_OUT>/bayer_ex_genus.v   ネットリスト
#         <BEX_GENUS_OUT>/bayer_ex_genus.sdc 配置配線用の制約(数値に展開したもの)
#         <BEX_GENUS_OUT>/rtl2gate.do        Conformal LEC の dofile
#         <BEX_GENUS_OUT>/reports/           面積・タイミング・電力
# ============================================================================
set bex_dir [file normalize [file dirname [info script]]]
source [file join $bex_dir .. setup design_setup.tcl]
source [file join $bex_dir .. setup foundry_setup.tcl]
set bex_rpt [file join $BEX_GENUS_OUT reports]
file mkdir $BEX_GENUS_OUT $bex_rpt

set_db max_cpus_per_server $BEX_CPUS
set_db information_level 7

# ----------------------------------------------------------------------------
# ライブラリ・制約(MMMC)と物理情報
# ----------------------------------------------------------------------------
bex_sdc_vars
set BEX_SDC_FILES [list $BEX_SDC_RTL]
read_mmmc [file join $bex_dir .. setup mmmc.tcl]
read_physical -lefs [concat [list $BEX_TECH_LEF] $BEX_STD_LEF]

# 使わないセル
foreach bex_p $BEX_DONT_USE {
  set_db [get_db lib_cells */$bex_p] .dont_use true
}

# ----------------------------------------------------------------------------
# RTL の読み込みと展開
#   SystemVerilog のインタフェース(BAYER_EX_DATA_IF)は Genus が展開する
# ----------------------------------------------------------------------------
read_hdl -language sv -define $BEX_DEFINES [bex_rtl_files]
elaborate $BEX_DESIGN
check_design -unresolved > [file join $bex_rpt check_design.rpt]
init_design

# SDC が読めたかの確認(クロック 2つ: clk と入出力の仮想クロック clk_io)
check_timing_intent -verbose > [file join $bex_rpt check_timing_intent.rpt]

# ----------------------------------------------------------------------------
# 合成
#   クロックゲーティングは使わない(RTL は有効信号付きの FF で書いてある。
#   使うときは lp_insert_clock_gating を true にして、BEX_CTS_ICG_CELLS を用意する)
# ----------------------------------------------------------------------------
set_db lp_insert_clock_gating false
set_db syn_generic_effort high
set_db syn_map_effort     high
set_db syn_opt_effort     high

syn_generic
syn_map
syn_opt

# ----------------------------------------------------------------------------
# レポート
# ----------------------------------------------------------------------------
report_qor                         > [file join $bex_rpt qor.rpt]
report_area                        > [file join $bex_rpt area.rpt]
report_gates                       > [file join $bex_rpt gates.rpt]
report_timing -max_paths 50        > [file join $bex_rpt timing.rpt]
report_timing -unconstrained -max_paths 20 > [file join $bex_rpt timing_unconstrained.rpt]
report_power                       > [file join $bex_rpt power.rpt]
report_dp                          > [file join $bex_rpt datapath.rpt]
report_messages                    > [file join $bex_rpt messages.rpt]

# ----------------------------------------------------------------------------
# 出力
# ----------------------------------------------------------------------------
write_hdl > [file join $BEX_GENUS_OUT bayer_ex_genus.v]
write_sdc -view [lindex [bex_views_for setup] 0] > $BEX_SDC_GENUS
write_do_lec -golden_design rtl -revised_design [file join $BEX_GENUS_OUT bayer_ex_genus.v] \
  -logfile [file join $BEX_GENUS_OUT lec_rtl2gate.log] > [file join $BEX_GENUS_OUT rtl2gate.do]
write_db [file join $BEX_GENUS_OUT bayer_ex_genus.db]

exit
