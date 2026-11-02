# ============================================================================
# クロックツリーを作った後の、入出力につながる FF のクロックの遅れを調べる
#
#   SDC の BEX_CLK_LATENCY(入出力の相手の仮想クロック clk_io の遅れ)を決めるために使う。
#   Innovus の CCOpt は入出力のクロックの遅れをクロックツリーに合わせて更新する
#   (update_io_latency)が、OpenROAD にはないので、この結果を見て config.mk の値を決める
#   (見込み → 実測)。
#
#   使い方: make io_latency(4_cts.odb を読む。ORFS の make run から呼ぶ)
#   出力  : 入力ポートからの経路の受け側の FF と、出力ポートへの経路の送り側の FF の
#           クロックの遅れ(最小・中央値・最大)、SDC に与える値の目安
# ============================================================================
source $::env(SCRIPTS_DIR)/load.tcl
load_design 4_cts.odb 4_cts.sdc
# 仮想クロックは伝搬できない(警告が出る)ので、実際のクロックだけ伝搬にする
set_propagated_clock [get_clocks clk]
estimate_parasitics -placement

# 版によってオプションの名前が違う(-group_count / -group_path_count)
proc bex_paths {args} {
  if {[catch {set pes [find_timing_paths {*}$args -group_count 100000 -endpoint_count 1]}]} {
    set pes [find_timing_paths {*}$args -group_path_count 100000 -endpoint_path_count 1]
  }
  return $pes
}

# 最小・中央値・最大 [ps](STA の内部の単位は秒)
proc bex_stat {vals} {
  set v [lsort -real $vals]
  set n [llength $v]
  if {$n == 0} {
    return "なし"
  }
  set mid [lindex $v [expr {$n/2}]]
  return [format "%d 個、最小 %.1f / 中央値 %.1f / 最大 %.1f ps" $n \
    [expr {[lindex $v 0]*1e12}] [expr {$mid*1e12}] [expr {[lindex $v end]*1e12}]]
}

proc bex_median {vals} {
  set v [lsort -real $vals]
  if {[llength $v] == 0} {
    return 0.0
  }
  return [lindex $v [expr {[llength $v]/2}]]
}

# FF のクロックの遅れ(その FF の D 端子で終わる経路の、受け側のクロックの遅れ)
proc bex_ff_latency {ck_pin} {
  set cell [get_cells -of_objects $ck_pin]
  foreach p [get_pins -of_objects $cell] {
    if {[get_property $p direction] == "input" && [string match */D [get_full_name $p]]} {
      set pes [bex_paths -to $p -path_delay min]
      if {[llength $pes] > 0} {
        return [[lindex $pes 0] target_clk_delay]
      }
    }
  }
  return ""
}

set bex_out [open [file join $::env(REPORTS_DIR) io_latency.rpt] w]
# 入力: 受け側の FF のクロックの遅れ(データの入力とリセット)
set ins [get_ports {i_vld i_busy i_data* i_cfg* rst_n}]
set lat_in {}
foreach pe [bex_paths -from $ins -path_delay min] {
  if {[$pe is_check]} {
    lappend lat_in [$pe target_clk_delay]
  }
}
# 出力: 送り側の FF のクロックの遅れ
#   経路の端子は終点から順に並ぶ。最初に出てくる FF のクロック端子が送り側。
#   find_timing_paths を呼ぶと前の結果が使えなくなるので、先にクロック端子を集める
set outs [get_ports {o_vld o_busy o_data*}]
set cks [dict create]
foreach pe [bex_paths -to $outs -path_delay max] {
  foreach p [[$pe path] pins] {
    if {[get_property $p is_register_clock]} {
      dict set cks [get_full_name $p] $p
      break
    }
  }
}
set lat_out {}
dict for {ckn ck} $cks {
  set l [bex_ff_latency $ck]
  if {$l != ""} {
    lappend lat_out $l
  }
}
set med [bex_median [concat $lat_in $lat_out]]
set msg [list \
  "BEX: clk 入力ポートから受ける FF: [bex_stat $lat_in]" \
  "BEX: clk 出力ポートへ送る FF  : [bex_stat $lat_out]" \
  [format "BEX: clk SDC に与える遅れの目安(入出力の FF の中央値): %.3f ns" [expr {$med*1e9}]]]
foreach m $msg {
  puts $m
  puts $bex_out $m
}
close $bex_out
report_clock_latency
report_clock_latency > [file join $::env(REPORTS_DIR) io_latency_clock.rpt]
