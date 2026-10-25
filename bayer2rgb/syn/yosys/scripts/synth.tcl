# ============================================================================
# BAYER2RGB の論理合成(Yosys)
#   yosys -c synth.tcl で実行する。値は環境変数で受け取る(Makefile が設定する)
#
#   DESIGN          トップモジュール名(BAYER2RGB)
#   FRONTEND        sv2v: sv2v で変換した Verilog を読む / slang: yosys-slang で SystemVerilog を直接読む
#   SV2V_FILE       sv2v で変換した Verilog(FRONTEND=sv2v)
#   SV_FILES        SystemVerilog のファイル(FRONTEND=slang)
#   SV_DEFINES      マクロ定義(FRONTEND=slang、例 "SYNTHESIS BAYER2RGB_PPC=8")
#   MACRO_V         SRAM マクロのブラックボックス(FRONTEND=slang で使う)
#   LIB_FILES       標準セルとマクロの Liberty(ブラックボックスとして読む)
#   MERGED_LIB      ABC に渡す標準セルの Liberty(1つにまとめたもの)
#   DFF_LIB         FF の Liberty
#   DONT_USE_CELLS  使わないセル(ワイルドカード可)
#   LATCH_MAP / ADDER_MAP   ラッチ・加算器の割り当て(なければ空)
#   TIEHI / TIELO   定数1/0 のセルと端子(例 "TIEHIx1_ASAP7_75t_R H")
#   MIN_BUF         素通しの配線に入れるバッファ(例 "BUFx2_ASAP7_75t_R A Y")
#   ABC_DRIVER      ABC の入力の駆動セル、ABC_LOAD: ABC の出力負荷
#   ABC_PERIOD      ABC の目標遅延(ライブラリの時間単位。clk の周期)
#   ABC_AREA        1: 面積優先のスクリプト / 0: 速度優先
#   ABC_SCRIPT_DIR  ABC のスクリプトのディレクトリ
#   OUT_NETLIST     出力のネットリスト、REPORT_DIR: レポートの出力先
# ============================================================================
yosys -import

proc env_or {name def} {
  if {[info exists ::env($name)] && $::env($name) != ""} {
    return $::env($name)
  }
  return $def
}

set design   $::env(DESIGN)
set frontend [env_or FRONTEND sv2v]
set rpt      $::env(REPORT_DIR)
file mkdir $rpt

# ----------------------------------------------------------------------------
# 読み込み
# ----------------------------------------------------------------------------
if {$frontend == "slang"} {
  plugin -i slang
  set defs {}
  foreach d [env_or SV_DEFINES ""] {
    lappend defs -D $d
  }
  # 階層を残すときは --best-effort-hierarchy(インスタンスごとにモジュールを分けて残す)
  if {[env_or SYNTH_FLATTEN 0] != 1} {
    lappend defs --best-effort-hierarchy
  }
  # プラグインのコマンドは yosys -import の後に増えたので、yosys を付けて呼ぶ
  yosys read_slang {*}$defs --top $design {*}$::env(SV_FILES) $::env(MACRO_V)
} else {
  read_verilog -defer -sv $::env(SV2V_FILE)
}

# 標準セルと SRAM マクロはブラックボックスとして読む
read_liberty -overwrite -lib {*}$::env(LIB_FILES)

hierarchy -check -top $design

# ----------------------------------------------------------------------------
# 論理合成
#   SYNTH_FLATTEN=0(既定): 階層を残す。ABC はモジュールごとに動くので
#                           必要なメモリが少ない。同じパラメータのモジュールは1回だけ合成する
#   SYNTH_FLATTEN=1      : 階層を平らにする(モジュールをまたいだ最適化ができる。メモリが多く要る)
#   EXTRA_MAP            : 加算器などの割り当て(例 ORFS の lcu_kogge_stone.v)
#   汎用ゲートへの ABC(synth の abc -fast)は省く。セルへの割り当ては後の abc で行う
#   同期化の FF は keep 属性で残る
# ----------------------------------------------------------------------------
set synth_args [list -top $design -noabc]
if {[env_or SYNTH_FLATTEN 0] == 1} {
  lappend synth_args -flatten
}
set extra_map [env_or EXTRA_MAP ""]
if {$extra_map != "" && [file isfile $extra_map]} {
  lappend synth_args -extra-map $extra_map
}
synth {*}$synth_args

# FF の名前を元のレジスタ名にそろえる
renames -wire
opt -purge

# 加算器(全加算器・半加算器のセルに割り当てる)
set adder_map [env_or ADDER_MAP ""]
if {$adder_map != "" && [file isfile $adder_map]} {
  extract_fa
  techmap -map $adder_map
  techmap
  opt -fast -purge
}

# ラッチ(この設計にはないはず)
set latch_map [env_or LATCH_MAP ""]
if {$latch_map != "" && [file isfile $latch_map]} {
  techmap -map $latch_map
}

# FF の割り当て
set dont_use {}
foreach c [env_or DONT_USE_CELLS ""] {
  lappend dont_use -dont_use $c
}
dfflibmap -liberty $::env(DFF_LIB) {*}$dont_use
opt

# 組み合わせ回路の割り当て(ABC)
set constr [file join $rpt abc.constr]
set fp [open $constr w]
puts $fp "set_driving_cell [env_or ABC_DRIVER {}]"
puts $fp "set_load [env_or ABC_LOAD 1.0]"
close $fp
if {[env_or ABC_AREA 0] == 1} {
  set abc_script [file join $::env(ABC_SCRIPT_DIR) abc_area.script]
} else {
  set abc_script [file join $::env(ABC_SCRIPT_DIR) abc_speed.script]
}
abc -script $abc_script -liberty $::env(MERGED_LIB) -constr $constr -D [env_or ABC_PERIOD 0] {*}$dont_use

# 後始末(定数・素通しの配線・まとめた代入をなくす)
setundef -zero
splitnets
opt_clean -purge
hilomap -singleton -hicell {*}$::env(TIEHI) -locell {*}$::env(TIELO)
insbuf -buf {*}$::env(MIN_BUF)
opt_clean -purge

# ----------------------------------------------------------------------------
# レポートと出力
# ----------------------------------------------------------------------------
tee -o [file join $rpt check.txt] check
set stat_libs {}
foreach l $::env(LIB_FILES) {
  lappend stat_libs -liberty $l
}
tee -o [file join $rpt area.txt] stat -top $design {*}$stat_libs

write_verilog -noexpr -nohex -nodec -noattr $::env(OUT_NETLIST)
