# ============================================================================
# BAYER2RGB の設計の設定(Genus / Innovus / Tempus で共通。雛形)
#
#   環境変数で変えられる値(Makefile が渡す)
#     B2R_PPC          1クロックの画素数(1/2/4/8、既定 8)
#     B2R_CLK_PERIOD   clk の周期 [ns](既定 2.5 = 400 MHz)
#     B2R_CTRL_PERIOD  ctrl_clk の周期 [ns](既定 10.0 = 100 MHz)
#     B2R_CLK_LATENCY  入出力の相手の clk の遅れ [ns](既定 0.0。SDC の仮想クロック clk_io の遅れ)
#     B2R_CTRL_LATENCY 入出力の相手の ctrl_clk の遅れ [ns](既定 0.0。ctrl_clk_io の遅れ)
#                      CTS の後は CCOpt が実際の遅れに合わせる(innovus/cts.tcl)。
#                      SoC で値が決まっているときに与える
#     B2R_CPUS         使う CPU の数(既定 8)
# ============================================================================
proc b2r_env {name def} {
  if {[info exists ::env($name)] && $::env($name) != ""} {
    return $::env($name)
  }
  return $def
}

set B2R_ROOT        [file normalize [file join [file dirname [info script]] .. .. ..]]
set B2R_DESIGN      BAYER2RGB
set B2R_PPC         [b2r_env B2R_PPC 8]
set B2R_CLK_PERIOD  [b2r_env B2R_CLK_PERIOD 2.5]
set B2R_CTRL_PERIOD [b2r_env B2R_CTRL_PERIOD 10.0]
set B2R_CLK_LATENCY  [b2r_env B2R_CLK_LATENCY 0.0]
set B2R_CTRL_LATENCY [b2r_env B2R_CTRL_LATENCY 0.0]
set B2R_CPUS        [b2r_env B2R_CPUS 8]

# 出力先
set B2R_OUT         [file join $B2R_ROOT pd commercial out foundry_ppc$B2R_PPC]
set B2R_GENUS_OUT   [file join $B2R_OUT genus]
set B2R_INNOVUS_OUT [file join $B2R_OUT innovus]
set B2R_TEMPUS_OUT  [file join $B2R_OUT tempus]

# ----------------------------------------------------------------------------
# RTL(rtl/rtl.f の順。SRAM と同期化のラッパは Foundry のプロセス用に差し替える)
# ----------------------------------------------------------------------------
proc b2r_rtl_files {} {
  global B2R_ROOT
  set files {}
  set fp [open [file join $B2R_ROOT rtl rtl.f] r]
  while {[gets $fp line] >= 0} {
    set line [string trim $line]
    if {$line == "" || [string match "//*" $line]} {
      continue
    }
    if {$line == "BAYER2RGB_SRAM_1R1W.sv" || $line == "BAYER2RGB_SYNC2.sv"} {
      lappend files [file join $B2R_ROOT syn rtl foundry $line]
    } else {
      lappend files [file join $B2R_ROOT rtl $line]
    }
  }
  close $fp
  return $files
}
set B2R_DEFINES     [list SYNTHESIS BAYER2RGB_PPC=$B2R_PPC]

# ----------------------------------------------------------------------------
# タイミング制約
#   論理合成は共通の SDC(syn/constraints/bayer2rgb.sdc)を読む。
#   SDC の変数はグローバル変数と環境変数の両方で渡す(どちらでも読めるように)
#   配置配線と STA は Genus が書き出した SDC を使う
# ----------------------------------------------------------------------------
set B2R_SDC_RTL     [file join $B2R_ROOT syn constraints bayer2rgb.sdc]
set B2R_SDC_GENUS   [file join $B2R_GENUS_OUT bayer2rgb_genus.sdc]

# B2R_VIEWS(setup/foundry_setup.tcl)から、用途(setup / hold)のビュー名を取り出す
proc b2r_views_for {use} {
  global B2R_VIEWS
  set r {}
  foreach v $B2R_VIEWS {
    lassign $v name lc rc u
    if {$u == $use || $u == "both"} {
      lappend r $name
    }
  }
  return $r
}

proc b2r_sdc_vars {} {
  global B2R_TIME_UNIT B2R_CAP_UNIT B2R_CLK_PERIOD B2R_CTRL_PERIOD B2R_CLK_LATENCY B2R_CTRL_LATENCY
  foreach v {B2R_TIME_UNIT B2R_CAP_UNIT B2R_CLK_PERIOD B2R_CTRL_PERIOD B2R_CLK_LATENCY B2R_CTRL_LATENCY} {
    set ::env($v) [set $v]
  }
}
