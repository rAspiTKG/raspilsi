# ============================================================================
# 合成後のタイミング解析(OpenSTA。sta -no_init -exit sta.tcl で実行)
#   配置前なので配線の遅れは入らない(見積もり)。配線後の値は配置配線の環境で見る
#
#   環境変数: DESIGN, NETLIST, SDC, LIBS(Liberty の並び), REPORT_DIR
#             BEX_TIME_UNIT などは SDC が読む(syn/constraints/bayer_ex.sdc)
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
proc bex_report_checks {file args} {
  if {[catch {report_checks -group_path_count 3 {*}$args > $file}]} {
    report_checks -group_count 3 {*}$args > $file
  }
}

# ---- 詳細(最も遅い・速い経路)
bex_report_checks $rpt/sta_setup.txt -path_delay max -fields {slew cap input} -digits 3
bex_report_checks $rpt/sta_hold.txt  -path_delay min -fields {slew cap input} -digits 3
report_check_types -max_slew -max_capacitance -max_fanout -violators > $rpt/sta_drv.txt

# ---- 経路の種類ごとの最も遅い経路(入力 → FF、FF → FF、FF → 出力、リセットの解除)
set f [open $rpt/sta_groups.txt w]
close $f
foreach {title a} [list \
  "入力 → FF"         [list -from [get_ports {i_vld i_busy i_data* i_cfg*}] -to [all_registers -data_pins]] \
  "FF → FF"           [list -from [all_registers -clock_pins] -to [all_registers -data_pins]] \
  "FF → 出力"         [list -from [all_registers -clock_pins] -to [all_outputs]] \
  "rst_n → FF(解除)" [list -from [get_ports rst_n]] \
] {
  set f [open $rpt/sta_groups.txt a]
  puts $f "==== $title"
  close $f
  if {[catch {report_checks -group_path_count 1 -path_delay max -digits 3 {*}$a >> $rpt/sta_groups.txt}]} {
    report_checks -group_count 1 -path_delay max -digits 3 {*}$a >> $rpt/sta_groups.txt
  }
}

# ---- 制約の漏れ(制約のない終点・クロックのない FF など)
check_setup -verbose > $rpt/sta_check_setup.txt

# ---- まとめ
report_clock_properties > $rpt/sta_summary.txt
report_worst_slack -max -digits 3 >> $rpt/sta_summary.txt
report_worst_slack -min -digits 3 >> $rpt/sta_summary.txt
report_tns -digits 3 >> $rpt/sta_summary.txt

# ---- 制約した入出力の本数(ビットの数)
set f [open $rpt/sta_ports.txt w]
puts $f [format "入力 i_vld i_busy i_data i_cfg: %d" [llength [get_ports {i_vld i_busy i_data* i_cfg*}]]]
puts $f [format "出力 o_vld o_busy o_data: %d" [llength [get_ports {o_vld o_busy o_data*}]]]
puts $f [format "すべての入力: %d(clk と rst_n を含む)、すべての出力: %d" [llength [all_inputs]] [llength [all_outputs]]]
close $f
