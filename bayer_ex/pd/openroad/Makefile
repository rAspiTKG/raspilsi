# ============================================================================
# BAYER_EX の物理設計(OpenROAD-flow-scripts(ORFS)+ ASAP7)
#
#   make              論理合成から配線後の解析まで(make synth floorplan place cts io_latency route final summary)
#   make synth        論理合成と合成後のタイミング解析(syn/yosys の make synth sta)
#   make floorplan    フロアプラン(コアの大きさ、端子の配置、電源配線)
#   make place        配置(タイミングを見た配置、バッファ挿入、詳細配置)
#   make cts          クロックツリーの合成とホールドの修正
#   make io_latency   クロックツリーの後の、入出力につながる FF のクロックの遅れ
#                     (SDC の BEX_CLK_LATENCY を決める。asap7/config.mk)
#   make grt          概略配線(make route に含まれる)
#   make route        詳細配線
#   make final        配線後の寄生抽出・タイミング解析・電力・IR ドロップ(ORFS の 6_report)
#   make summary      結果の要約 → results/asap7/summary.md
#   make gds          GDS(KLayout が必要)
#   make clean        work/ を消す
#
#   変数
#     ORFS_FLOW=<dir>     ORFS の flow ディレクトリ
#     CLK_PERIOD=2.5      clk の周期 [ns]
#     CORNER=WC           ライブラリのコーナー(WC / TC / BC)
#     CORE_UTILIZATION=40 コアの使用率 [%]、PLACE_DENSITY=0.60 配置の密度
#     OPENROAD_EXE / OPENSTA_EXE / YOSYS_EXE   ツールのコマンド(既定は PATH にあるもの)
#     ORFS_ARGS="..."     ORFS にそのまま渡す変数(例 ORFS_ARGS="BEX_CLK_LATENCY=0.2")
# ============================================================================
ROOT         := $(abspath ../..)
ORFS_FLOW    ?= $(HOME)/OpenROAD-flow-scripts/flow
CLK_PERIOD   ?= 2.5
CORNER       ?= WC
CORE_UTILIZATION ?= 40
PLACE_DENSITY    ?= 0.60
OPENROAD_EXE ?= $(shell command -v openroad)
OPENSTA_EXE  ?= $(shell command -v sta)
YOSYS_EXE    ?= $(shell command -v yosys)
PYTHON       ?= python3
ORFS_ARGS    ?=

DESIGN_CFG   := $(CURDIR)/asap7/config.mk
NAME         := asap7
NICK         := bayer_ex
WORK         := $(CURDIR)/work/$(NAME)
RES          := $(WORK)/results/asap7/$(NICK)/base
LOG          := $(WORK)/logs/asap7/$(NICK)/base
RPT          := $(WORK)/reports/asap7/$(NICK)/base
SUMMARY_DIR  := $(CURDIR)/results/$(NAME)
NETLIST      := $(ROOT)/syn/yosys/out/$(NAME)/bayer_ex_syn.v
SDC          := $(ROOT)/syn/constraints/bayer_ex.sdc

ORFS = $(MAKE) --no-print-directory -C $(ORFS_FLOW) \
       DESIGN_CONFIG=$(DESIGN_CFG) WORK_HOME=$(WORK) \
       BEX_CLK_PERIOD=$(CLK_PERIOD) CORNER=$(CORNER) \
       CORE_UTILIZATION=$(CORE_UTILIZATION) PLACE_DENSITY=$(PLACE_DENSITY) \
       OPENROAD_EXE=$(OPENROAD_EXE) OPENSTA_EXE=$(OPENSTA_EXE) YOSYS_EXE=$(YOSYS_EXE) $(ORFS_ARGS)

.PHONY: all synth floorplan place cts io_latency grt route final summary gds clean check_tools

all: synth floorplan place cts io_latency route final summary

check_tools:
	@test -d $(ORFS_FLOW)/platforms/asap7 || (echo "ORFS_FLOW=$(ORFS_FLOW) に ORFS の flow がありません"; exit 1)
	@test -n "$(OPENROAD_EXE)" || (echo "openroad が見つかりません(OPENROAD_EXE を指定してください)"; exit 1)
	@test -n "$(YOSYS_EXE)" || (echo "yosys が見つかりません(YOSYS_EXE を指定してください)"; exit 1)

# ---- 論理合成(配置配線と同じ周期・コーナーで行う)
synth: check_tools
	$(MAKE) -C $(ROOT)/syn/yosys PLATFORM=asap7 CLK_PERIOD=$(CLK_PERIOD) \
	  CORNER=$(CORNER) ORFS_FLOW=$(ORFS_FLOW) YOSYS=$(YOSYS_EXE) STA=$(OPENSTA_EXE) synth sta

$(NETLIST):
	$(MAKE) synth

# ---- ORFS の各段階
#   段階の結果のファイルで要否を判断し、ORFS の do-<段階>(依存関係を見ない実行)を呼ぶ。
#   この版の ORFS は合成済みのネットリスト(CACHED_NETLIST)を使うと、呼ぶたびに合成の
#   段階からやり直しになるため
floorplan: $(RES)/2_floorplan.odb
place:     $(RES)/3_place.odb
cts:       $(RES)/4_cts.odb
grt:       $(RES)/5_1_grt.odb
route:     $(RES)/5_route.odb
final:     $(LOG)/6_report.log

$(RES)/1_synth.v: $(NETLIST) $(SDC) $(DESIGN_CFG) | check_tools
	$(ORFS) synth

$(RES)/2_floorplan.odb: $(RES)/1_synth.v $(CURDIR)/asap7/io_constraints.tcl
	$(ORFS) do-floorplan

$(RES)/3_place.odb: $(RES)/2_floorplan.odb
	$(ORFS) do-place

$(RES)/4_cts.odb: $(RES)/3_place.odb
	$(ORFS) do-cts

# クロックツリーの後の、入出力につながる FF のクロックの遅れ → $(RPT)/io_latency.rpt
io_latency: $(RES)/4_cts.odb
	$(ORFS) run RUN_SCRIPT=$(CURDIR)/scripts/io_latency.tcl > $(LOG)/io_latency.log 2>&1 || (tail -20 $(LOG)/io_latency.log; exit 1)
	@grep "^BEX:" $(LOG)/io_latency.log

$(RES)/5_1_grt.odb: $(RES)/4_cts.odb
	$(ORFS) do-5_1_grt

$(RES)/5_route.odb: $(RES)/5_1_grt.odb
	$(ORFS) do-5_2_route do-5_3_fillcell do-5_route do-5_route.sdc

# 配線後の解析(ORFS の finish から GDS を除いたもの。KLayout が要らない)
$(LOG)/6_report.log: $(RES)/5_route.odb
	$(ORFS) do-6_1_fill do-6_1_fill.sdc do-6_final.sdc do-6_report

# GDS(KLayout が必要)
gds: $(LOG)/6_report.log
	$(ORFS) do-gds

# ---- 要約と配置の図
SC_LEF_FILE  := $(ORFS_FLOW)/platforms/asap7/lef/asap7sc7p5t_28_R_1x_220121a.lef

# 図は、終わっている中で最も後の段階のデータベース(6_final … 3_place)から DEF を書いて描く
LAST_ODB      = $(lastword $(wildcard $(RES)/3_place.odb $(RES)/4_cts.odb $(RES)/5_1_grt.odb $(RES)/5_route.odb $(RES)/6_final.odb))

summary:
	@mkdir -p $(SUMMARY_DIR)
	@if [ -n "$(LAST_ODB)" ]; then \
	  echo "read_db $(LAST_ODB); write_def $(WORK)/summary.def" > $(WORK)/summary_def.tcl; \
	  $(OPENROAD_EXE) -no_init -exit $(WORK)/summary_def.tcl > $(WORK)/summary_def.log 2>&1; \
	fi
	$(PYTHON) scripts/pd_summary.py --name $(NAME) --logs $(LOG) --reports $(RPT) --results $(RES) \
	  --syn $(ROOT)/syn/yosys/out/$(NAME)/reports --out $(SUMMARY_DIR) \
	  --def $(WORK)/summary.def --def_label $(notdir $(LAST_ODB)) \
	  $(addprefix --lef ,$(SC_LEF_FILE))

clean:
	rm -rf work
