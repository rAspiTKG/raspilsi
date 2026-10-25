# ============================================================================
# 合成後のタイミング解析(OpenSTA。sta -no_init -exit sta.tcl で実行)
#   配置前なので配線の遅れは入らない(見積もり)。配線後の値は配置配線の環境で見る
#
#   環境変数: DESIGN, NETLIST, SDC, LIBS(Liberty の並び), REPORT_DIR
#             B2R_TIME_UNIT などは SDC が読む(syn/constraints/bayer2rgb.sdc)
# ============================================================================
foreach lib $::env(LIBS) {
  read_liberty $lib
}
read_verilog $::env(NETLIST)
link_design $::env(DESIGN)
read_sdc $::env(SDC)

set rpt $::env(REPORT_DIR)
file mkdir $rpt

# report_checks の経路数の指定は OpenSTA の版で名前が違う(-group_path_count / -group_count)
proc b2r_report_checks {file args} {
  if {[catch {report_checks -group_path_count 3 {*}$args > $file}]} {
    report_checks -group_count 3 {*}$args > $file
  }
}

# ---- 詳細(クロックの組み合わせごとに、最も遅い・速い経路)
b2r_report_checks $rpt/sta_setup.txt -path_delay max -fields {slew cap input} -digits 3
b2r_report_checks $rpt/sta_hold.txt  -path_delay min -fields {slew cap input} -digits 3
report_check_types -max_slew -max_capacitance -max_fanout -violators > $rpt/sta_drv.txt

# ---- まとめ
report_clock_properties > $rpt/sta_summary.txt
report_worst_slack -max -digits 3 >> $rpt/sta_summary.txt
report_worst_slack -min -digits 3 >> $rpt/sta_summary.txt
report_tns -digits 3 >> $rpt/sta_summary.txt

# ---- clk 側と ctrl_clk 側の間の経路(BAYER2RGB_CDC の乗せ換えだけのはず。仕様書 11章)
#   終点の数と、それぞれの最も遅い経路。入出力の仮想クロック(clk_io / ctrl_clk_io)からの
#   反対側への経路は 0 のはず
proc b2r_paths {from to} {
  set a [list -from [get_clocks $from] -to [get_clocks $to] -path_delay max]
  if {[catch {set pes [find_timing_paths {*}$a -group_count 100000 -endpoint_count 1]}]} {
    set pes [find_timing_paths {*}$a -group_path_count 100000 -endpoint_path_count 1]
  }
  return [llength $pes]
}
set f [open $rpt/sta_cdc.txt w]
foreach {from to} {
  clk         ctrl_clk
  ctrl_clk    clk
  clk_io      {ctrl_clk ctrl_clk_io}
  ctrl_clk_io {clk clk_io}
  clk         ctrl_clk_io
  ctrl_clk    clk_io
} {
  puts $f [format "%-12s -> %-22s 終点 %d" $from $to [b2r_paths $from $to]]
}
close $f
b2r_report_checks $rpt/sta_cdc_paths.txt -from [get_clocks clk] -to [get_clocks ctrl_clk] -path_delay max -digits 3
set f [open $rpt/sta_cdc_paths.txt a]
puts $f ""
close $f
if {[catch {report_checks -group_path_count 3 -from [get_clocks ctrl_clk] -to [get_clocks clk] -path_delay max -digits 3 >> $rpt/sta_cdc_paths.txt}]} {
  report_checks -group_count 3 -from [get_clocks ctrl_clk] -to [get_clocks clk] -path_delay max -digits 3 >> $rpt/sta_cdc_paths.txt
}
