# ============================================================================
# BAYER2RGB のタイミング制約(論理合成・配置配線・STA で共通)
#
#   Tcl の SDC です。Genus / Design Compiler / OpenSTA(OpenROAD)で読めます。
#   ポート名だけを使い、セル名・インスタンス名は使いません(合成ツールによらない)。
#
#   調整用の変数(Tcl のグローバル変数か環境変数で与える。どちらもなければ既定値)
#     B2R_TIME_UNIT     ライブラリの時間の単位            ns(既定)/ ps(ASAP7 など)
#     B2R_CAP_UNIT      ライブラリの容量の単位            pF(既定)/ fF(ASAP7 など)
#     B2R_CLK_PERIOD    clk の周期 [ns]                   2.5(400 MHz)
#     B2R_CTRL_PERIOD   ctrl_clk の周期 [ns]              10.0(100 MHz)
#     B2R_IO_PCT        AXI の入出力で外側が使う割合 [%]   50
#     B2R_RST_PCT       リセットの解除で外側が使う割合 [%] 50
#     B2R_UNC_SETUP     クロックの不確かさ(セットアップ)[ns]  0.10
#     B2R_UNC_HOLD      クロックの不確かさ(ホールド)[ns]      0.03
#     B2R_CLK_TRAN      クロックの遷移時間(配置前)[ns]       0.05
#     B2R_IN_TRAN       入力の遷移時間 [ns]               0.05
#     B2R_OUT_LOAD      出力の負荷容量 [pF]               0.005
#     B2R_CLK_LATENCY   clk のクロックツリーの遅れの見込み [ns]       0.0
#     B2R_CTRL_LATENCY  ctrl_clk のクロックツリーの遅れの見込み [ns]  0.0
#
#   クロック
#     clk          映像系(AXI4 マスタ BAYER2RGB_MEM_*、画像処理)
#     ctrl_clk     制御系(AXI4-Lite スレーブ BAYER2RGB_REG_*、irq)
#     clk_io       入出力の相手(IP の外の FF)の clk。仮想クロック
#     ctrl_clk_io  入出力の相手の ctrl_clk。仮想クロック
#     clk と ctrl_clk は非同期。間の経路は BAYER2RGB_CDC の中の乗せ換えだけ(仕様書 11章)
# ============================================================================

# ----------------------------------------------------------------------------
# 変数(Tcl のグローバル変数 > 環境変数 > 既定値)。配列 b2r_v に入れて使う
# ----------------------------------------------------------------------------
foreach {b2r_k b2r_d} {
  B2R_TIME_UNIT   ns
  B2R_CAP_UNIT    pF
  B2R_CLK_PERIOD  2.5
  B2R_CTRL_PERIOD 10.0
  B2R_IO_PCT      50
  B2R_RST_PCT     50
  B2R_UNC_SETUP   0.10
  B2R_UNC_HOLD    0.03
  B2R_CLK_TRAN    0.05
  B2R_IN_TRAN     0.05
  B2R_OUT_LOAD    0.005
  B2R_CLK_LATENCY  0.0
  B2R_CTRL_LATENCY 0.0
} {
  if {[info exists ::$b2r_k]} {
    set b2r_v($b2r_k) [set ::$b2r_k]
  } elseif {[info exists ::env($b2r_k)]} {
    set b2r_v($b2r_k) $::env($b2r_k)
  } else {
    set b2r_v($b2r_k) $b2r_d
  }
}

# 単位の換算(値は ns / pF で書き、ライブラリの単位に直す)
if {$b2r_v(B2R_TIME_UNIT)=="ps"} {
  set b2r_t 1000.0
} else {
  set b2r_t 1.0
}
if {$b2r_v(B2R_CAP_UNIT)=="fF"} {
  set b2r_c 1000.0
} else {
  set b2r_c 1.0
}

set b2r_clk_p   [expr {$b2r_v(B2R_CLK_PERIOD)*$b2r_t}]
set b2r_ctrl_p  [expr {$b2r_v(B2R_CTRL_PERIOD)*$b2r_t}]
set b2r_io_clk  [expr {$b2r_v(B2R_CLK_PERIOD)*$b2r_v(B2R_IO_PCT)/100.0*$b2r_t}]
set b2r_io_ctrl [expr {$b2r_v(B2R_CTRL_PERIOD)*$b2r_v(B2R_IO_PCT)/100.0*$b2r_t}]
set b2r_rst_clk  [expr {$b2r_v(B2R_CLK_PERIOD)*$b2r_v(B2R_RST_PCT)/100.0*$b2r_t}]
set b2r_rst_ctrl [expr {$b2r_v(B2R_CTRL_PERIOD)*$b2r_v(B2R_RST_PCT)/100.0*$b2r_t}]
set b2r_unc_s   [expr {$b2r_v(B2R_UNC_SETUP)*$b2r_t}]
set b2r_unc_h   [expr {$b2r_v(B2R_UNC_HOLD)*$b2r_t}]
set b2r_clk_tr  [expr {$b2r_v(B2R_CLK_TRAN)*$b2r_t}]
set b2r_in_tr   [expr {$b2r_v(B2R_IN_TRAN)*$b2r_t}]
set b2r_load    [expr {$b2r_v(B2R_OUT_LOAD)*$b2r_c}]
set b2r_clk_lat  [expr {$b2r_v(B2R_CLK_LATENCY)*$b2r_t}]
set b2r_ctrl_lat [expr {$b2r_v(B2R_CTRL_LATENCY)*$b2r_t}]

# ----------------------------------------------------------------------------
# クロック
#   入出力の遅延は、入出力の相手(IP の外の FF)のクロック clk_io / ctrl_clk_io から測る。
#   相手の FF も SoC の同じクロックツリーから来るので、クロックツリーの遅れの見込み
#   (B2R_CLK_LATENCY / B2R_CTRL_LATENCY)を、IP のクロックと相手のクロックの両方に与える。
#     - クロックツリーの前(理想クロック): 両方が同じ遅れなので、見込みの値によらず同じ結果
#     - クロックツリーの後: IP の中の FF は実際の遅れ、相手は見込みの遅れのまま
#       (仮想クロックは伝搬しない)。見込みを実際の遅れに合わせると、入力の経路に
#       不要なホールド用バッファが入らない(仕様書 14.4)
#   Innovus では CTS の後に update_io_latency で仮想クロックの遅れをクロックツリーに合わせられる。
#   OpenROAD では pd/openroad の make io_latency で測った値を与える
# ----------------------------------------------------------------------------
create_clock -name clk         -period $b2r_clk_p  [get_ports clk]
create_clock -name ctrl_clk    -period $b2r_ctrl_p [get_ports ctrl_clk]
create_clock -name clk_io      -period $b2r_clk_p
create_clock -name ctrl_clk_io -period $b2r_ctrl_p
set_clock_latency $b2r_clk_lat  [get_clocks {clk clk_io}]
set_clock_latency $b2r_ctrl_lat [get_clocks {ctrl_clk ctrl_clk_io}]

set_clock_uncertainty -setup $b2r_unc_s [get_clocks {clk ctrl_clk clk_io ctrl_clk_io}]
set_clock_uncertainty -hold  $b2r_unc_h [get_clocks {clk ctrl_clk clk_io ctrl_clk_io}]
# 配置前の見積もり用(クロックツリーを作った後はツールが実際の値を使う)
set_clock_transition $b2r_clk_tr [get_clocks {clk ctrl_clk}]

# ----------------------------------------------------------------------------
# AXI4 マスタ(BAYER2RGB_MEM_*、clk)
#   出力は FF から直接出している(BRIDGE の2段スキッド)
# ----------------------------------------------------------------------------
set b2r_mem_in [get_ports {
  BAYER2RGB_MEM_AWREADY
  BAYER2RGB_MEM_WREADY
  BAYER2RGB_MEM_BID* BAYER2RGB_MEM_BRESP* BAYER2RGB_MEM_BVALID
  BAYER2RGB_MEM_ARREADY
  BAYER2RGB_MEM_RID* BAYER2RGB_MEM_RDATA* BAYER2RGB_MEM_RRESP* BAYER2RGB_MEM_RLAST BAYER2RGB_MEM_RVALID
}]
set b2r_mem_out [get_ports {
  BAYER2RGB_MEM_AWID* BAYER2RGB_MEM_AWADDR* BAYER2RGB_MEM_AWLEN* BAYER2RGB_MEM_AWSIZE* BAYER2RGB_MEM_AWBURST*
  BAYER2RGB_MEM_AWLOCK BAYER2RGB_MEM_AWCACHE* BAYER2RGB_MEM_AWPROT* BAYER2RGB_MEM_AWQOS* BAYER2RGB_MEM_AWVALID
  BAYER2RGB_MEM_WDATA* BAYER2RGB_MEM_WSTRB* BAYER2RGB_MEM_WLAST BAYER2RGB_MEM_WVALID
  BAYER2RGB_MEM_BREADY
  BAYER2RGB_MEM_ARID* BAYER2RGB_MEM_ARADDR* BAYER2RGB_MEM_ARLEN* BAYER2RGB_MEM_ARSIZE* BAYER2RGB_MEM_ARBURST*
  BAYER2RGB_MEM_ARLOCK BAYER2RGB_MEM_ARCACHE* BAYER2RGB_MEM_ARPROT* BAYER2RGB_MEM_ARQOS* BAYER2RGB_MEM_ARVALID
  BAYER2RGB_MEM_RREADY
}]
set_input_delay  -max $b2r_io_clk -clock clk_io $b2r_mem_in
set_input_delay  -min 0.0         -clock clk_io $b2r_mem_in
set_output_delay -max $b2r_io_clk -clock clk_io $b2r_mem_out
set_output_delay -min 0.0         -clock clk_io $b2r_mem_out

# ----------------------------------------------------------------------------
# AXI4-Lite スレーブ(BAYER2RGB_REG_*、ctrl_clk)と割り込み
# ----------------------------------------------------------------------------
set b2r_reg_in [get_ports {
  BAYER2RGB_REG_AWADDR* BAYER2RGB_REG_AWPROT* BAYER2RGB_REG_AWVALID
  BAYER2RGB_REG_WDATA* BAYER2RGB_REG_WSTRB* BAYER2RGB_REG_WVALID
  BAYER2RGB_REG_BREADY
  BAYER2RGB_REG_ARADDR* BAYER2RGB_REG_ARPROT* BAYER2RGB_REG_ARVALID
  BAYER2RGB_REG_RREADY
}]
set b2r_reg_out [get_ports {
  BAYER2RGB_REG_AWREADY BAYER2RGB_REG_WREADY
  BAYER2RGB_REG_BRESP* BAYER2RGB_REG_BVALID
  BAYER2RGB_REG_ARREADY
  BAYER2RGB_REG_RDATA* BAYER2RGB_REG_RRESP* BAYER2RGB_REG_RVALID
  irq
}]
set_input_delay  -max $b2r_io_ctrl -clock ctrl_clk_io $b2r_reg_in
set_input_delay  -min 0.0          -clock ctrl_clk_io $b2r_reg_in
set_output_delay -max $b2r_io_ctrl -clock ctrl_clk_io $b2r_reg_out
set_output_delay -min 0.0          -clock ctrl_clk_io $b2r_reg_out

# ----------------------------------------------------------------------------
# リセット(非同期アサート・同期解除。解除はIPの外でそれぞれのクロックに同期する)
#   解除のタイミング(リカバリ・リムーバル)を検査するため、入力遅延を与える。
#   リセットは IP の全体の制御の FF に配線が広がるので、配置配線の後はこの検査が
#   最も厳しくなる(仕様書 14.4)。IP の外の同期化の FF を IP の近くに置けるときは
#   B2R_RST_PCT を小さくできる
# ----------------------------------------------------------------------------
set_input_delay -max $b2r_rst_clk  -clock clk_io      [get_ports rst_n]
set_input_delay -min 0.0           -clock clk_io      [get_ports rst_n]
set_input_delay -max $b2r_rst_ctrl -clock ctrl_clk_io [get_ports ctrl_rst_n]
set_input_delay -min 0.0           -clock ctrl_clk_io [get_ports ctrl_rst_n]

# ----------------------------------------------------------------------------
# 入力の遷移時間と出力の負荷
# ----------------------------------------------------------------------------
set_input_transition $b2r_in_tr $b2r_mem_in
set_input_transition $b2r_in_tr $b2r_reg_in
set_input_transition $b2r_in_tr [get_ports {rst_n ctrl_rst_n}]
set_load $b2r_load $b2r_mem_out
set_load $b2r_load $b2r_reg_out

# ----------------------------------------------------------------------------
# クロック乗せ換え(BAYER2RGB_CDC)
#   clk と ctrl_clk の間の経路は次の2種類だけ
#     - 同期化セル(BAYER2RGB_SYNC2)の1段目へのトグル信号
#     - トグルで受け渡す設定・イベントのデータ(MCP。受け側で2周期以上変化しない)
#   どちらも、データの遅れ(クロックの遅れは含めない)を受け側クロックの1周期以内にする。
#   ホールドは検査しない。set_clock_groups -asynchronous は使わない(この制約が消えるため)
# ----------------------------------------------------------------------------
#   入出力の相手のクロック(clk_io / ctrl_clk_io)もそれぞれの側に含める
set b2r_dom_clk  [get_clocks {clk clk_io}]
set b2r_dom_ctrl [get_clocks {ctrl_clk ctrl_clk_io}]
set_max_delay $b2r_clk_p  -ignore_clock_latency -from $b2r_dom_ctrl -to $b2r_dom_clk
set_max_delay $b2r_ctrl_p -ignore_clock_latency -from $b2r_dom_clk  -to $b2r_dom_ctrl
set_false_path -hold -from $b2r_dom_ctrl -to $b2r_dom_clk
set_false_path -hold -from $b2r_dom_clk  -to $b2r_dom_ctrl
