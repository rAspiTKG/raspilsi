# ============================================================================
# BAYER_EX の設計の設定(Genus / Innovus / Tempus で共通。雛形)
#
#   環境変数で変えられる値(Makefile が渡す)
#     BEX_CLK_PERIOD   clk の周期 [ns](既定 2.5 = 400 MHz)
#     BEX_CLK_LATENCY  入出力の相手の clk の遅れ [ns](既定 0.0。SDC の仮想クロック clk_io の遅れ)
#                      CTS の後は CCOpt が実際の遅れに合わせる(innovus/cts.tcl)。
#                      SoC で値が決まっているときに与える
#     BEX_CPUS         使う CPU の数(既定 8)
# ============================================================================
proc bex_env {name def} {
  if {[info exists ::env($name)] && $::env($name) != ""} {
    return $::env($name)
  }
  return $def
}

set BEX_ROOT        [file normalize [file join [file dirname [info script]] .. .. ..]]
set BEX_DESIGN      BAYER_EX
set BEX_CLK_PERIOD  [bex_env BEX_CLK_PERIOD 2.5]
set BEX_CLK_LATENCY [bex_env BEX_CLK_LATENCY 0.0]
set BEX_CPUS        [bex_env BEX_CPUS 8]

# 出力先
set BEX_OUT         [file join $BEX_ROOT pd commercial out foundry]
set BEX_GENUS_OUT   [file join $BEX_OUT genus]
set BEX_INNOVUS_OUT [file join $BEX_OUT innovus]
set BEX_TEMPUS_OUT  [file join $BEX_OUT tempus]

# ----------------------------------------------------------------------------
# RTL(rtl/rtl.f の順。製品IPはないので、プロセスによって差し替えるものはない)
#   トップは BAYER_EX(BAYER_EX_CORE のインタフェースのポートを平らにしたラッパ)
# ----------------------------------------------------------------------------
proc bex_rtl_files {} {
  global BEX_ROOT
  set files {}
  set fp [open [file join $BEX_ROOT rtl rtl.f] r]
  while {[gets $fp line] >= 0} {
    set line [string trim $line]
    if {$line == "" || [string match "//*" $line]} {
      continue
    }
    lappend files [file join $BEX_ROOT rtl $line]
  }
  close $fp
  return $files
}
set BEX_DEFINES     [list SYNTHESIS]

# ----------------------------------------------------------------------------
# タイミング制約
#   論理合成は共通の SDC(syn/constraints/bayer_ex.sdc)を読む。
#   SDC の変数はグローバル変数と環境変数の両方で渡す(どちらでも読めるように)
#   配置配線と STA は Genus が書き出した SDC を使う
# ----------------------------------------------------------------------------
set BEX_SDC_RTL     [file join $BEX_ROOT syn constraints bayer_ex.sdc]
set BEX_SDC_GENUS   [file join $BEX_GENUS_OUT bayer_ex_genus.sdc]

# BEX_VIEWS(setup/foundry_setup.tcl)から、用途(setup / hold)のビュー名を取り出す
proc bex_views_for {use} {
  global BEX_VIEWS
  set r {}
  foreach v $BEX_VIEWS {
    lassign $v name lc rc u
    if {$u == $use || $u == "both"} {
      lappend r $name
    }
  }
  return $r
}

proc bex_sdc_vars {} {
  global BEX_TIME_UNIT BEX_CAP_UNIT BEX_CLK_PERIOD BEX_CLK_LATENCY
  foreach v {BEX_TIME_UNIT BEX_CAP_UNIT BEX_CLK_PERIOD BEX_CLK_LATENCY} {
    set ::env($v) [set $v]
  }
}
