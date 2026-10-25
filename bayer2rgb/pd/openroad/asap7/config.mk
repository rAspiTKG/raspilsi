# ============================================================================
# BAYER2RGB の配置配線(OpenROAD-flow-scripts、ASAP7)の設定
#
#   ORFS の DESIGN_CONFIG に渡す。pd/openroad/Makefile から使う。
#   論理合成は ORFS では行わず、syn/yosys で合成したネットリストを使う(CACHED_NETLIST)。
#   タイミング制約は論理合成と同じ syn/constraints/bayer2rgb.sdc を単位 ps / fF で読む。
#
#   変数(make のコマンドラインで変えられる)
#     B2R_PPC           1クロックの画素数(1/2/4/8、既定 8)
#     B2R_CLK_PERIOD    clk の周期 [ns](既定 2.5 = 400 MHz)
#     B2R_CTRL_PERIOD   ctrl_clk の周期 [ns](既定 10.0 = 100 MHz)
#     B2R_CLK_LATENCY   入出力の相手の clk の遅れ [ns](既定は PPC ごとの値。下の表)
#     B2R_CTRL_LATENCY  入出力の相手の ctrl_clk の遅れ [ns](同上)
#     CORNER            ライブラリのコーナー(WC / TC / BC、既定 WC)
#     CORE_UTILIZATION  コアの使用率 [%](既定 30)
#     PLACE_DENSITY     配置の密度(既定 0.42)
# ============================================================================
B2R_PD_DIR            := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
export B2R_ROOT       ?= $(abspath $(B2R_PD_DIR)/../../..)
export B2R_PPC        ?= 8
export B2R_SYN_OUT    ?= $(B2R_ROOT)/syn/yosys/out/asap7_ppc$(B2R_PPC)

export DESIGN_NAME     = BAYER2RGB
export DESIGN_NICKNAME = bayer2rgb_ppc$(B2R_PPC)
export PLATFORM        = asap7
export CORNER         ?= WC

# ---- ネットリスト(syn/yosys の出力。階層つき)
#   CACHED_NETLIST: この版の ORFS で合成を飛ばす変数。新しい ORFS では SYNTH_NETLIST_FILES
export VERILOG_FILES   = $(B2R_SYN_OUT)/bayer2rgb_syn.v
export CACHED_NETLIST  = $(B2R_SYN_OUT)/bayer2rgb_syn.v
export SYNTH_NETLIST_FILES = $(B2R_SYN_OUT)/bayer2rgb_syn.v
export SYNTH_HIERARCHICAL = 1

# ---- タイミング制約(論理合成と同じファイル。ASAP7 のライブラリの単位に合わせる)
export SDC_FILE        = $(B2R_ROOT)/syn/constraints/bayer2rgb.sdc
export B2R_TIME_UNIT   = ps
export B2R_CAP_UNIT    = fF
export B2R_CLK_PERIOD ?= 2.5
export B2R_CTRL_PERIOD ?= 10.0

# 入出力の相手のクロックの遅れ [ns](SDC の B2R_CLK_LATENCY / B2R_CTRL_LATENCY)
#   クロックツリーの後に make io_latency で測った、入出力につながる FF のクロックの遅れの
#   中央値に合わせる。0 のままだと、入力の経路に不要なホールド用バッファが入る(仕様書 14.4)。
#   値は「clk ctrl_clk」の順
#     PPC=8: 実測 0.500 / 0.232(make io_latency)
#     PPC=2: 実測 0.395 / 0.200(見込み 0.45 / 0.23 で1回流して測った)
#     PPC=4 / 1: 測っていない(PPC=4 は PPC=8 と 2 の間の値、PPC=1 は PPC=2 と同じ値)
B2R_IO_LAT_PPC8 := 0.50 0.23
B2R_IO_LAT_PPC4 := 0.45 0.22
B2R_IO_LAT_PPC2 := 0.40 0.20
B2R_IO_LAT_PPC1 := 0.40 0.20
export B2R_CLK_LATENCY  ?= $(word 1,$(B2R_IO_LAT_PPC$(B2R_PPC)))
export B2R_CTRL_LATENCY ?= $(word 2,$(B2R_IO_LAT_PPC$(B2R_PPC)))

# ---- SRAM の仮マクロ(tools/gen_sram_macro.py。syn/yosys の make macros で作る)
export ADDITIONAL_LEFS = $(sort $(wildcard $(B2R_SYN_OUT)/macros/b2r_sram1r1w_*.lef))
export ADDITIONAL_LIBS = $(sort $(wildcard $(B2R_SYN_OUT)/macros/b2r_sram1r1w_*.lib))
# 仮マクロには GDS がない(GDS をつなぐときに空のセルとして扱う)
export GDS_ALLOW_EMPTY = b2r_sram1r1w_.*

# ---- フロアプラン
#   コアの大きさはセルとマクロの面積と使用率から決める(正方形)
#   使用率 40%・配置の密度 0.60 では、GAMMA(24チャネル × 37個の折れ点の選択)のまわりの
#   配線が混みすぎて概略配線が収束しなかったので、30% / 0.42 にしている
export CORE_UTILIZATION  ?= 30
export CORE_ASPECT_RATIO ?= 1
export CORE_MARGIN       ?= 2

# マクロの配置: asap7/macro_place.tcl(コアの左右の端に積む。端子はコアの内側へ向ける)
#   この版の OpenROAD の自動配置(RTL-MP)は階層つきのネットリストで異常終了したため。
#   自動配置を試すときは make ... ORFS_ARGS="MACRO_PLACEMENT_TCL=" とする
export MACRO_PLACEMENT_TCL ?= $(B2R_PD_DIR)/macro_place.tcl
# マクロのまわりに標準セルを置かない幅 [um]
export MACRO_PLACE_HALO    ?= 4 4
export MACRO_PLACE_CHANNEL ?= 8 8

# 端子は上辺と下辺に置く(左右の端はマクロの列)
export PLACE_PINS_ARGS     ?= -exclude left:* -exclude right:*

# ---- 配置
export PLACE_DENSITY     ?= 0.42

# ---- タイミングの修正(違反した終点を全部直す)
export TNS_END_PERCENT    = 100
export SETUP_SLACK_MARGIN ?= 0
export HOLD_SLACK_MARGIN  ?= 0

# ---- 配線(ASAP7 の既定 M2〜M7)
export MIN_ROUTING_LAYER ?= M2
export MAX_ROUTING_LAYER ?= M7
# 概略配線で各層の容量から差し引く割合(ORFS の既定 0.5。ASAP7 の swerv_wrapper と同じく小さめにする)
export ROUTING_LAYER_ADJUSTMENT ?= 0.3
