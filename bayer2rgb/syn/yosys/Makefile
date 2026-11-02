# ============================================================================
# BAYER2RGB の論理合成(Yosys)
#
#   make                    論理合成とタイミング解析(既定: ASAP7、PPC=8、400 MHz)
#   make synth              論理合成だけ → out/<PLATFORM>_ppc<PPC>/bayer2rgb_syn.v
#                           面積の表は reports/area_summary.md
#   make sta                合成後のタイミング解析(OpenSTA。配線の遅れは入らない)
#   make macros             SRAM の仮マクロ(LEF / Liberty / ブラックボックス)を作る
#   make clean
#
#   変数
#     PLATFORM=asap7        platforms/<PLATFORM>.mk を読む
#     ORFS_FLOW=<dir>       OpenROAD-flow-scripts の flow ディレクトリ(ASAP7 のライブラリ)
#     PPC=8                 1クロックの画素数(1/2/4/8)
#     CLK_PERIOD=2.5        clk の周期 [ns](CTRL_PERIOD: ctrl_clk の周期 [ns])
#     CORNER=WC             ライブラリのコーナー(WC / TC / BC)
#     FRONTEND=sv2v         sv2v: sv2v で Verilog に変換して読む / slang: yosys-slang で直接読む
#     ABC_AREA=1            1: 面積優先 / 0: 速度優先(時間がかかる)
#     SYNTH_FLATTEN=0       0: 階層を残す(メモリが少なくて済む) / 1: 平らにする
#     YOSYS / SV2V / STA    ツールのコマンド(STA: OpenSTA。OpenROAD に付いている sta)
# ============================================================================
ROOT       := $(abspath ../..)
SYN_DIR    := $(ROOT)/syn
PLATFORM   ?= asap7
PPC        ?= 8
CLK_PERIOD ?= 2.5
CTRL_PERIOD ?= 10.0
FRONTEND   ?= sv2v
ABC_AREA   ?= 1
SYNTH_FLATTEN ?= 0
YOSYS      ?= yosys
SV2V       ?= sv2v
STA        ?= sta
PYTHON     ?= python3
DESIGN     := BAYER2RGB

include platforms/$(PLATFORM).mk

OUT        ?= out/$(PLATFORM)_ppc$(PPC)
RPT        := $(OUT)/reports
NETLIST    := $(OUT)/bayer2rgb_syn.v
SDC        := $(SYN_DIR)/constraints/bayer2rgb.sdc

# ---- SRAM の大きさ(ラインバッファ、読み出し・書き込みバッファ、出力FIFO)
LB_DEPTH   := $(shell echo $$((3840/$(PPC))))
LB_WIDTH   := $(shell echo $$(($(PPC)*14)))
OF_WIDTH   := $(shell echo $$(($(PPC)*24+3)))
SRAM_SIZES := $(LB_DEPTH)x$(LB_WIDTH),64x128,64x144,32x$(OF_WIDTH)
MACRO_DIR  := $(OUT)/macros
MACRO_LIBS  = $(wildcard $(MACRO_DIR)/b2r_sram1r1w_*.lib)

# ---- RTL(SRAM と同期化のラッパはプラットフォームの合成用に差し替える)
RTL_LIST   := $(shell grep -v '^\s*//' $(ROOT)/rtl/rtl.f | grep -v '^\s*$$')
RTL_FILES  := $(filter-out %BAYER2RGB_SRAM_1R1W.sv %BAYER2RGB_SYNC2.sv,$(addprefix $(ROOT)/rtl/,$(RTL_LIST))) \
              $(SYN_RTL_DIR)/BAYER2RGB_SRAM_1R1W.sv $(SYN_RTL_DIR)/BAYER2RGB_SYNC2.sv
DEFINES    := SYNTHESIS BAYER2RGB_PPC=$(PPC)
SV2V_OUT   := $(OUT)/bayer2rgb_sv2v.v

# ---- ライブラリ(Yosys / ABC で読める形にそろえる)
LIB_OUT    := $(OUT)/lib
STD_PREP   := $(addprefix $(LIB_OUT)/,$(patsubst %.gz,%,$(notdir $(STD_LIBS))))
MERGED_LIB := $(LIB_OUT)/merged.lib
DFF_LIB    := $(LIB_OUT)/$(notdir $(DFF_LIB_SRC))

ABC_PERIOD := $(shell awk 'BEGIN { print $(CLK_PERIOD)*$(TIME_SCALE) }')

.PHONY: all synth sta macros libs sv2v clean

all: synth sta

macros: $(MACRO_DIR)/macros.txt

$(MACRO_DIR)/macros.txt: $(ROOT)/tools/gen_sram_macro.py
	@mkdir -p $(MACRO_DIR)
	$(PYTHON) $(ROOT)/tools/gen_sram_macro.py --platform $(MACRO_PLATFORM) --sizes $(SRAM_SIZES) --outdir $(MACRO_DIR)

libs: $(MERGED_LIB)

$(MERGED_LIB): $(STD_LIBS) $(ROOT)/tools/liberty_prep.py
	@mkdir -p $(LIB_OUT)
	$(PYTHON) $(ROOT)/tools/liberty_prep.py --outdir $(LIB_OUT) $(STD_LIBS)
	$(PYTHON) $(ROOT)/tools/liberty_prep.py --name $(PLATFORM)_merged --out $@ $(STD_PREP)

sv2v: $(SV2V_OUT)

$(SV2V_OUT): $(RTL_FILES)
	@mkdir -p $(OUT)
	LC_ALL=C.UTF-8 $(SV2V) $(addprefix -D,$(DEFINES)) $(RTL_FILES) -w $@

synth: $(NETLIST)

$(NETLIST): $(MACRO_DIR)/macros.txt $(MERGED_LIB) $(if $(filter sv2v,$(FRONTEND)),$(SV2V_OUT),$(RTL_FILES)) scripts/synth.tcl
	@mkdir -p $(RPT)
	DESIGN=$(DESIGN) FRONTEND=$(FRONTEND) SV2V_FILE=$(SV2V_OUT) SV_FILES="$(RTL_FILES)" SV_DEFINES="$(DEFINES)" \
	MACRO_V=$(MACRO_DIR)/b2r_sram_macros.v LIB_FILES="$(STD_PREP) $(MACRO_LIBS)" \
	MERGED_LIB=$(MERGED_LIB) DFF_LIB=$(DFF_LIB) DONT_USE_CELLS="$(DONT_USE_CELLS)" \
	LATCH_MAP=$(LATCH_MAP) ADDER_MAP=$(ADDER_MAP) TIEHI="$(TIEHI)" TIELO="$(TIELO)" MIN_BUF="$(MIN_BUF)" \
	ABC_DRIVER=$(ABC_DRIVER) ABC_LOAD=$(ABC_LOAD) ABC_PERIOD=$(ABC_PERIOD) ABC_AREA=$(ABC_AREA) \
	SYNTH_FLATTEN=$(SYNTH_FLATTEN) EXTRA_MAP=$(EXTRA_MAP) \
	ABC_SCRIPT_DIR=$(CURDIR)/scripts OUT_NETLIST=$@ REPORT_DIR=$(RPT) \
	$(YOSYS) -c scripts/synth.tcl > $(OUT)/yosys.log 2>&1 || (tail -30 $(OUT)/yosys.log; exit 1)
	$(PYTHON) scripts/area_summary.py $(RPT)/area.txt > $(RPT)/area_summary.md
	@grep -E "Chip area|Number of cells" $(RPT)/area.txt | tail -2

sta: $(NETLIST)
	DESIGN=$(DESIGN) NETLIST=$(NETLIST) SDC=$(SDC) LIBS="$(STD_PREP) $(MACRO_LIBS)" REPORT_DIR=$(RPT) \
	B2R_TIME_UNIT=$(TIME_UNIT) B2R_CAP_UNIT=$(CAP_UNIT) B2R_CLK_PERIOD=$(CLK_PERIOD) B2R_CTRL_PERIOD=$(CTRL_PERIOD) \
	$(STA) -no_init -exit scripts/sta.tcl > $(OUT)/sta.log 2>&1 || (tail -30 $(OUT)/sta.log; exit 1)
	@cat $(RPT)/sta_summary.txt

clean:
	rm -rf out
