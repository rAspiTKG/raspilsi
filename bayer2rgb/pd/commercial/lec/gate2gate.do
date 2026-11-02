// ============================================================================
// 論理等価性検証: Genus のネットリスト と 配置配線後のネットリスト(Conformal LEC。雛形・未検証)
//   make lec_g2g で使う。Makefile が @OUT@ と @LIBS@ を置き換えてから lec に渡す
//     @OUT@   pd/commercial/out/<名前>
//     @LIBS@  標準セルとメモリの Liberty(最も遅いコーナー)
//   RTL と Genus のネットリストの比較は、Genus が書き出す rtl2gate.do を使う(make lec_rtl)
// ============================================================================
set log file @OUT@/lec_gate2gate.log -replace
set dofile abort exit

read library -liberty -both @LIBS@

read design -verilog -golden  @OUT@/genus/bayer2rgb_genus.v
read design -verilog -revised @OUT@/innovus/bayer2rgb_final.v

set root module BAYER2RGB -both

set system mode lec
add compared points -all
compare
report verification > @OUT@/lec_gate2gate.rpt
report unmapped points -summary >> @OUT@/lec_gate2gate.rpt
exit -force
