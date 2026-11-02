# ============================================================================
# BAYER_EX の論理合成(Yosys)
#
#   make                    論理合成とタイミング解析(既定: ASAP7、400 MHz、WC コーナー)
#   make synth              論理合成だけ → out/<PLATFORM>/bayer_ex_syn.v
#                           面積の表は reports/area_summary.md
#   make sta                合成後のタイミング解析(OpenSTA。配線の遅れは入らない)
#   make clean
#
#   変数
#     PLATFORM=asap7        platforms/<PLATFORM>.mk を読む
#     ORFS_FLOW=<dir>       OpenROAD-flow-scripts の flow ディレクトリ(ASAP7 のライブラリ)
#     CLK_PERIOD=2.5        clk の周期 [ns]
#     CORNER=WC             ライブラリのコーナー(WC / TC / BC)
#     FRONTEND=sv2v         sv2v: sv2v で Verilog に変換して読む / slang: yosys-slang で直接読む
#     ABC_AREA=1            1: 面積優先 / 0: 速度優先(時間がかかる)
#     SYNTH_FLATTEN=0       0: 階層を残す / 1: 平らにする
#     OUT=out/<PLATFORM>    出力先
#     YOSYS / SV2V / STA    ツールのコマンド(STA: OpenSTA。OpenROAD に付いている sta)
# ============================================================================
ROOT       := $(abspath ../..)
SYN_DIR    := $(ROOT)/syn
PLATFORM   ?= asap7
CLK_PERIOD ?= 2.5
FRONTEND   ?= sv2v
ABC_AREA   ?= 1
SYNTH_FLATTEN ?= 0
YOSYS      ?= yosys
SV2V       ?= sv2v
STA        ?= sta
PYTHON     ?= python3
DESIGN     := BAYER_EX

include platforms/$(PLATFORM).mk

OUT        ?= out/$(PLATFORM)
RPT        := $(OUT)/reports
NETLIST    := $(OUT)/bayer_ex_syn.v
SDC        := $(SYN_DIR)/constraints/bayer_ex.sdc

# ---- RTL(rtl/rtl.f の順。プロセスによって差し替えるものはない)
RTL_LIST   := $(shell grep -v '^\s*//' $(ROOT)/rtl/rtl.f | grep -v '^\s*$$')
RTL_FILES  := $(addprefix $(ROOT)/rtl/,$(RTL_LIST))
DEFINES    := SYNTHESIS
SV2V_OUT   := $(OUT)/bayer_ex_sv2v.v

# ---- ライブラリ(Yosys / ABC で読める形にそろえる)
LIB_OUT    := $(OUT)/lib
STD_PREP   := $(addprefix $(LIB_OUT)/,$(patsubst %.gz,%,$(notdir $(STD_LIBS))))
MERGED_LIB := $(LIB_OUT)/merged.lib
DFF_LIB    := $(LIB_OUT)/$(notdir $(DFF_LIB_SRC))

ABC_PERIOD := $(shell awk 'BEGIN { print $(CLK_PERIOD)*$(TIME_SCALE) }')

.PHONY: all synth sta libs sv2v clean

all: synth sta

libs: $(MERGED_LIB)

$(MERGED_LIB): $(STD_LIBS) $(ROOT)/tools/liberty_prep.py
	@mkdir -p $(LIB_OUT)
	$(PYTHON) $(ROOT)/tools/liberty_prep.py --outdir $(LIB_OUT) $(STD_LIBS)
	$(PYTHON) $(ROOT)/tools/liberty_prep.py --name $(PLATFORM)_merged --out $@ $(STD_PREP)

sv2v: $(SV2V_OUT)

# sv2v はインタフェースのポートを持つモジュールをトップにできないので、トップはラッパの BAYER_EX
$(SV2V_OUT): $(RTL_FILES)
	@mkdir -p $(OUT)
	LC_ALL=C.UTF-8 $(SV2V) $(addprefix -D,$(DEFINES)) --top $(DESIGN) $(RTL_FILES) -w $@

synth: $(NETLIST)

$(NETLIST): $(MERGED_LIB) $(if $(filter sv2v,$(FRONTEND)),$(SV2V_OUT),$(RTL_FILES)) scripts/synth.tcl
	@mkdir -p $(RPT)
	DESIGN=$(DESIGN) FRONTEND=$(FRONTEND) SV2V_FILE=$(SV2V_OUT) SV_FILES="$(RTL_FILES)" SV_DEFINES="$(DEFINES)" \
	LIB_FILES="$(STD_PREP)" MERGED_LIB=$(MERGED_LIB) DFF_LIB=$(DFF_LIB) DONT_USE_CELLS="$(DONT_USE_CELLS)" \
	LATCH_MAP=$(LATCH_MAP) ADDER_MAP=$(ADDER_MAP) TIEHI="$(TIEHI)" TIELO="$(TIELO)" MIN_BUF="$(MIN_BUF)" \
	ABC_DRIVER=$(ABC_DRIVER) ABC_LOAD=$(ABC_LOAD) ABC_PERIOD=$(ABC_PERIOD) ABC_AREA=$(ABC_AREA) \
	SYNTH_FLATTEN=$(SYNTH_FLATTEN) EXTRA_MAP=$(EXTRA_MAP) \
	ABC_SCRIPT_DIR=$(CURDIR)/scripts OUT_NETLIST=$@ REPORT_DIR=$(RPT) \
	$(YOSYS) -c scripts/synth.tcl > $(OUT)/yosys.log 2>&1 || (tail -30 $(OUT)/yosys.log; exit 1)
	$(PYTHON) scripts/area_summary.py $(RPT)/area.txt > $(RPT)/area_summary.md
	@grep -E "Chip area|Number of cells" $(RPT)/area.txt | tail -2

sta: $(NETLIST)
	DESIGN=$(DESIGN) NETLIST=$(NETLIST) SDC=$(SDC) LIBS="$(STD_PREP)" REPORT_DIR=$(RPT) \
	BEX_TIME_UNIT=$(TIME_UNIT) BEX_CAP_UNIT=$(CAP_UNIT) BEX_CLK_PERIOD=$(CLK_PERIOD) \
	$(STA) -no_init -exit scripts/sta.tcl > $(OUT)/sta.log 2>&1 || (tail -30 $(OUT)/sta.log; exit 1)
	@cat $(RPT)/sta_summary.txt

clean:
	rm -rf out
