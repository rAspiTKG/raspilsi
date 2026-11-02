# ============================================================================
# BAYER_EX の配置配線(OpenROAD-flow-scripts、ASAP7)の設定
#
#   ORFS の DESIGN_CONFIG に渡す。pd/openroad/Makefile から使う。
#   論理合成は ORFS では行わず、syn/yosys で合成したネットリストを使う(CACHED_NETLIST)。
#   タイミング制約は論理合成と同じ syn/constraints/bayer_ex.sdc を単位 ps / fF で読む。
#
#   変数(make のコマンドラインで変えられる)
#     BEX_CLK_PERIOD    clk の周期 [ns](既定 2.5 = 400 MHz)
#     BEX_CLK_LATENCY   入出力の相手の clk の遅れ [ns](既定は make io_latency で測った値)
#     CORNER            ライブラリのコーナー(WC / TC / BC、既定 WC)
#     CORE_UTILIZATION  コアの使用率 [%](既定 40)
#     PLACE_DENSITY     配置の密度(既定 0.60)
# ============================================================================
BEX_PD_DIR            := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
export BEX_ROOT       ?= $(abspath $(BEX_PD_DIR)/../../..)
export BEX_SYN_OUT    ?= $(BEX_ROOT)/syn/yosys/out/asap7

export DESIGN_NAME     = BAYER_EX
export DESIGN_NICKNAME = bayer_ex
export PLATFORM        = asap7
export CORNER         ?= WC

# ---- ネットリスト(syn/yosys の出力。階層つき)
#   CACHED_NETLIST: この版の ORFS で合成を飛ばす変数。新しい ORFS では SYNTH_NETLIST_FILES
export VERILOG_FILES   = $(BEX_SYN_OUT)/bayer_ex_syn.v
export CACHED_NETLIST  = $(BEX_SYN_OUT)/bayer_ex_syn.v
export SYNTH_NETLIST_FILES = $(BEX_SYN_OUT)/bayer_ex_syn.v
export SYNTH_HIERARCHICAL = 1

# ---- タイミング制約(論理合成と同じファイル。ASAP7 のライブラリの単位に合わせる)
export SDC_FILE        = $(BEX_ROOT)/syn/constraints/bayer_ex.sdc
export BEX_TIME_UNIT   = ps
export BEX_CAP_UNIT    = fF
export BEX_CLK_PERIOD ?= 2.5

# 入出力の相手のクロックの遅れ [ns](SDC の BEX_CLK_LATENCY)
#   クロックツリーの後に make io_latency で測った、入出力につながる FF のクロックの遅れの
#   中央値に合わせる。0 のままだと、入力の経路に不要なホールド用バッファが入る
#   (pd/README.md の 1.4)。実測 0.135 ns(見込み 0 で1回流して測った)
export BEX_CLK_LATENCY ?= 0.135

# ---- フロアプラン
#   コアの大きさはセルの面積と使用率から決める(正方形)
export CORE_UTILIZATION  ?= 40
export CORE_ASPECT_RATIO ?= 1
export CORE_MARGIN       ?= 2

# 端子の置き場所(asap7/io_constraints.tcl): 左辺に入力側、右辺に出力側、上辺に設定、下辺に clk と rst_n
export IO_CONSTRAINTS    ?= $(BEX_PD_DIR)/io_constraints.tcl

# ---- 配置
export PLACE_DENSITY     ?= 0.60

# ---- タイミングの修正(違反した終点を全部直す)
export TNS_END_PERCENT    = 100
export SETUP_SLACK_MARGIN ?= 0
export HOLD_SLACK_MARGIN  ?= 0

# ---- 配線(ASAP7 の既定 M2〜M7)
export MIN_ROUTING_LAYER ?= M2
export MAX_ROUTING_LAYER ?= M7
