# ============================================================================
# クロックツリーを作った後の、入出力につながる FF のクロックの遅れを調べる
#
#   SDC の B2R_CLK_LATENCY / B2R_CTRL_LATENCY(入出力の相手の仮想クロック clk_io /
#   ctrl_clk_io の遅れ)を決めるために使う。Innovus の CCOpt は入出力のクロックの遅れを
#   クロックツリーに合わせて更新する(update_io_latency)が、OpenROAD にはないので、
#   この結果を見て config.mk の値を決める(見込み → 見積もり → 実測)。
#
#   使い方: make io_latency(4_cts.odb を読む。ORFS の make run から呼ぶ)
#   出力  : 入力ポートからの経路の受け側の FF と、出力ポートへの経路の送り側の FF の
#           クロックの遅れ(最小・中央値・最大)、クロック全体の遅れ、SDC に与える値の目安
# ============================================================================
source $::env(SCRIPTS_DIR)/load.tcl
load_design 4_cts.odb 4_cts.sdc
# 仮想クロックは伝搬できない(警告が出る)ので、実際のクロックだけ伝搬にする
set_propagated_clock [get_clocks {clk ctrl_clk}]
estimate_parasitics -placement

# 版によってオプションの名前が違う(-group_count / -group_path_count)
proc b2r_paths {args} {
  if {[catch {set pes [find_timing_paths {*}$args -group_count 100000 -endpoint_count 1]}]} {
    set pes [find_timing_paths {*}$args -group_path_count 100000 -endpoint_path_count 1]
  }
  return $pes
}

# 最小・中央値・最大 [ps](STA の内部の単位は秒)
proc b2r_stat {vals} {
  set v [lsort -real $vals]
  set n [llength $v]
  if {$n == 0} {
    return "なし"
  }
  set mid [lindex $v [expr {$n/2}]]
  return [format "%d 個、最小 %.1f / 中央値 %.1f / 最大 %.1f ps" $n \
    [expr {[lindex $v 0]*1e12}] [expr {$mid*1e12}] [expr {[lindex $v end]*1e12}]]
}

proc b2r_median {vals} {
  set v [lsort -real $vals]
  if {[llength $v] == 0} {
    return 0.0
  }
  return [lindex $v [expr {[llength $v]/2}]]
}

# FF のクロックの遅れ(その FF の D 端子で終わる経路の、受け側のクロックの遅れ)
proc b2r_ff_latency {ck_pin} {
  set cell [get_cells -of_objects $ck_pin]
  foreach p [get_pins -of_objects $cell] {
    if {[get_property $p direction] == "input" && [string match */D [get_full_name $p]]} {
      set pes [b2r_paths -to $p -path_delay min]
      if {[llength $pes] > 0} {
        return [[lindex $pes 0] target_clk_delay]
      }
    }
  }
  return ""
}

set b2r_ports {
  clk      {BAYER2RGB_MEM_* rst_n}      {BAYER2RGB_MEM_*}
  ctrl_clk {BAYER2RGB_REG_* ctrl_rst_n} {BAYER2RGB_REG_* irq}
}
set b2r_out [open [file join $::env(REPORTS_DIR) io_latency.rpt] w]
foreach {clk in_pat out_pat} $b2r_ports {
  set ins {}
  foreach p [all_inputs] {
    set n [get_full_name $p]
    foreach pat $in_pat {
      if {[string match $pat $n]} {
        lappend ins $p
        break
      }
    }
  }
  set outs {}
  foreach p [all_outputs] {
    set n [get_full_name $p]
    foreach pat $out_pat {
      if {[string match $pat $n]} {
        lappend outs $p
        break
      }
    }
  }
  # 入力: 受け側の FF のクロックの遅れ
  set lat_in {}
  foreach pe [b2r_paths -from $ins -path_delay min] {
    if {[$pe is_check]} {
      lappend lat_in [$pe target_clk_delay]
    }
  }
  # 出力: 送り側の FF のクロックの遅れ
  #   経路の端子は終点から順に並ぶ。最初に出てくる FF のクロック端子が送り側。
  #   find_timing_paths を呼ぶと前の結果が使えなくなるので、先にクロック端子を集める
  set cks [dict create]
  foreach pe [b2r_paths -to $outs -path_delay max] {
    foreach p [[$pe path] pins] {
      if {[get_property $p is_register_clock]} {
        dict set cks [get_full_name $p] $p
        break
      }
    }
  }
  set lat_out {}
  dict for {ckn ck} $cks {
    set l [b2r_ff_latency $ck]
    if {$l != ""} {
      lappend lat_out $l
    }
  }
  set med [b2r_median [concat $lat_in $lat_out]]
  set msg [list \
    "B2R: $clk 入力ポートから受ける FF: [b2r_stat $lat_in]" \
    "B2R: $clk 出力ポートへ送る FF  : [b2r_stat $lat_out]" \
    [format "B2R: $clk SDC に与える遅れの目安(入出力の FF の中央値): %.3f ns" [expr {$med*1e9}]]]
  foreach m $msg {
    puts $m
    puts $b2r_out $m
  }
}
close $b2r_out
report_clock_latency
report_clock_latency > [file join $::env(REPORTS_DIR) io_latency_clock.rpt]
