# ============================================================================
# BAYER_EX のタイミング制約(論理合成・配置配線・STA で共通)
#
#   Tcl の SDC です。Genus / Design Compiler / OpenSTA(OpenROAD)で読めます。
#   ポート名だけを使い、セル名・インスタンス名は使いません(合成ツールによらない)。
#   対象のトップは BAYER_EX(BAYER_EX_CORE のインタフェースのポートを平らにしたラッパ)。
#
#   調整用の変数(Tcl のグローバル変数か環境変数で与える。どちらもなければ既定値)
#     BEX_TIME_UNIT    ライブラリの時間の単位                ns(既定)/ ps(ASAP7 など)
#     BEX_CAP_UNIT     ライブラリの容量の単位                pF(既定)/ fF(ASAP7 など)
#     BEX_CLK_PERIOD   clk の周期 [ns]                       2.5(400 MHz)
#     BEX_IO_PCT       入出力で IP の外が使う割合 [%]         50
#     BEX_RST_PCT      リセットの解除で IP の外が使う割合 [%]  50
#     BEX_UNC_SETUP    クロックの不確かさ(セットアップ)[ns]  0.10
#     BEX_UNC_HOLD     クロックの不確かさ(ホールド)[ns]      0.03
#     BEX_CLK_TRAN     クロックの遷移時間(配置前)[ns]       0.05
#     BEX_IN_TRAN      入力の遷移時間 [ns]                   0.05
#     BEX_OUT_LOAD     出力の負荷容量 [pF]                   0.005
#     BEX_CLK_LATENCY  clk のクロックツリーの遅れの見込み [ns]  0.0
#
#   クロック
#     clk     IP のクロック(すべての FF)
#     clk_io  入出力の相手(IP の外の FF)の clk。仮想クロック
# ============================================================================

# ----------------------------------------------------------------------------
# 変数(Tcl のグローバル変数 > 環境変数 > 既定値)。配列 bex_v に入れて使う
# ----------------------------------------------------------------------------
foreach {bex_k bex_d} {
  BEX_TIME_UNIT   ns
  BEX_CAP_UNIT    pF
  BEX_CLK_PERIOD  2.5
  BEX_IO_PCT      50
  BEX_RST_PCT     50
  BEX_UNC_SETUP   0.10
  BEX_UNC_HOLD    0.03
  BEX_CLK_TRAN    0.05
  BEX_IN_TRAN     0.05
  BEX_OUT_LOAD    0.005
  BEX_CLK_LATENCY 0.0
} {
  if {[info exists ::$bex_k]} {
    set bex_v($bex_k) [set ::$bex_k]
  } elseif {[info exists ::env($bex_k)]} {
    set bex_v($bex_k) $::env($bex_k)
  } else {
    set bex_v($bex_k) $bex_d
  }
}

# 単位の換算(値は ns / pF で書き、ライブラリの単位に直す)
if {$bex_v(BEX_TIME_UNIT)=="ps"} {
  set bex_t 1000.0
} else {
  set bex_t 1.0
}
if {$bex_v(BEX_CAP_UNIT)=="fF"} {
  set bex_c 1000.0
} else {
  set bex_c 1.0
}

set bex_clk_p   [expr {$bex_v(BEX_CLK_PERIOD)*$bex_t}]
set bex_io      [expr {$bex_v(BEX_CLK_PERIOD)*$bex_v(BEX_IO_PCT)/100.0*$bex_t}]
set bex_rst     [expr {$bex_v(BEX_CLK_PERIOD)*$bex_v(BEX_RST_PCT)/100.0*$bex_t}]
set bex_unc_s   [expr {$bex_v(BEX_UNC_SETUP)*$bex_t}]
set bex_unc_h   [expr {$bex_v(BEX_UNC_HOLD)*$bex_t}]
set bex_clk_tr  [expr {$bex_v(BEX_CLK_TRAN)*$bex_t}]
set bex_in_tr   [expr {$bex_v(BEX_IN_TRAN)*$bex_t}]
set bex_load    [expr {$bex_v(BEX_OUT_LOAD)*$bex_c}]
set bex_clk_lat [expr {$bex_v(BEX_CLK_LATENCY)*$bex_t}]

# ----------------------------------------------------------------------------
# クロック
#   入出力の遅延は、入出力の相手(IP の外の FF)のクロック clk_io から測る。
#   相手の FF も SoC の同じクロックツリーから来るので、クロックツリーの遅れの見込み
#   (BEX_CLK_LATENCY)を、IP のクロックと相手のクロックの両方に与える。
#     - クロックツリーの前(理想クロック): 両方が同じ遅れなので、見込みの値によらず同じ結果
#     - クロックツリーの後: IP の中の FF は実際の遅れ、相手は見込みの遅れのまま
#       (仮想クロックは伝搬しない)。見込みを実際の遅れに合わせると、入力の経路に
#       不要なホールド用バッファが入らない
#   Innovus では CTS の後に update_io_latency で仮想クロックの遅れをクロックツリーに合わせられる。
#   OpenROAD では pd/openroad の make io_latency で測った値を与える
# ----------------------------------------------------------------------------
create_clock -name clk    -period $bex_clk_p [get_ports clk]
create_clock -name clk_io -period $bex_clk_p
set_clock_latency $bex_clk_lat [get_clocks {clk clk_io}]

set_clock_uncertainty -setup $bex_unc_s [get_clocks {clk clk_io}]
set_clock_uncertainty -hold  $bex_unc_h [get_clocks {clk clk_io}]
# 配置前の見積もり用(クロックツリーを作った後はツールが実際の値を使う)
set_clock_transition $bex_clk_tr [get_clocks clk]

# ----------------------------------------------------------------------------
# 入出力(vld / busy / data と設定)
#   出力(o_vld、o_busy、o_data)はすべて FF から直接出している。
#   入力はすべて、IP の中で最初に FF で受ける(i_busy だけは、FF の手前で
#   パイプラインを止める判定に使う)。
#   i_cfg は準静的(コアの中にデータがないときだけ変える)だが、ほかの入力と同じ制約にする
# ----------------------------------------------------------------------------
set bex_in  [get_ports {i_vld i_busy i_data* i_cfg*}]
set bex_out [get_ports {o_vld o_busy o_data*}]
set_input_delay  -max $bex_io -clock clk_io $bex_in
set_input_delay  -min 0.0     -clock clk_io $bex_in
set_output_delay -max $bex_io -clock clk_io $bex_out
set_output_delay -min 0.0     -clock clk_io $bex_out

# ----------------------------------------------------------------------------
# リセット(非同期アサート・同期解除。解除は IP の外で clk に同期する)
#   解除のタイミング(リカバリ・リムーバル)を検査するため、入力遅延を与える
# ----------------------------------------------------------------------------
set_input_delay -max $bex_rst -clock clk_io [get_ports rst_n]
set_input_delay -min 0.0      -clock clk_io [get_ports rst_n]

# ----------------------------------------------------------------------------
# 入力の遷移時間と出力の負荷
# ----------------------------------------------------------------------------
set_input_transition $bex_in_tr $bex_in
set_input_transition $bex_in_tr [get_ports rst_n]
set_load $bex_load $bex_out
