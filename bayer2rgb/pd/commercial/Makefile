# ============================================================================
# BAYER2RGB の商用ツールの流れ(Cadence、Foundry の PDK。雛形・未検証)
#
#   make syn        論理合成(Genus)          → out/<名前>/genus/
#   make lec_rtl    RTL と合成後の等価性検証(Conformal。Genus が書いた dofile)
#   make pnr        配置配線(Innovus。init floorplan place cts route signoff の順)
#   make sta        サインオフの STA(Tempus。RC コーナーごとの SPEF を使う)
#   make lec_g2g    合成後と配置配線後の等価性検証(Conformal)
#   make drc / lvs  物理検証(Pegasus。ルールファイルは PDK のもの)
#   make all        syn lec_rtl pnr sta lec_g2g
#
#   先に setup/foundry_setup.tcl の <...> を PDK に合わせて記入する。
#   SRAM と同期化のラッパ(syn/rtl/foundry/)のセル名・端子名も合わせる。
#
#   変数: PPC=8  CLK_PERIOD=2.5  CTRL_PERIOD=10.0  CPUS=8
#         GENUS / INNOVUS / TEMPUS / LEC / PEGASUS   ツールのコマンド
# ============================================================================
PPC         ?= 8
CLK_PERIOD  ?= 2.5
CTRL_PERIOD ?= 10.0
CPUS        ?= 8
GENUS       ?= genus
INNOVUS     ?= innovus
TEMPUS      ?= tempus
LEC         ?= lec
PEGASUS     ?= pegasus

OUT         := $(CURDIR)/out/foundry_ppc$(PPC)
DB          := $(OUT)/innovus/db
LOGS        := $(OUT)/logs
export B2R_PPC         := $(PPC)
export B2R_CLK_PERIOD  := $(CLK_PERIOD)
export B2R_CTRL_PERIOD := $(CTRL_PERIOD)
export B2R_CPUS        := $(CPUS)

# Conformal に渡す Liberty(最も遅いコーナー)と Pegasus のルール(PDK のもの)
LEC_LIBS          ?= <PDK の標準セルとメモリの Liberty(ss コーナー)>
PEGASUS_DRC_RULES ?= <PDK の Pegasus DRC ルール>
PEGASUS_LVS_RULES ?= <PDK の Pegasus LVS ルール>

INNOVUS_RUN = $(INNOVUS) -stylus -no_gui -files
STAGES      := init floorplan place cts route signoff
STAGE_DB_init      := 01_init
STAGE_DB_floorplan := 02_floorplan
STAGE_DB_place     := 03_place
STAGE_DB_cts       := 04_cts
STAGE_DB_route     := 05_route
STAGE_DB_signoff   := 06_signoff

.PHONY: all syn lec_rtl pnr $(STAGES) sta lec_g2g drc lvs clean

all: syn lec_rtl pnr sta lec_g2g

# ---- 論理合成
syn: $(OUT)/genus/bayer2rgb_genus.v

$(OUT)/genus/bayer2rgb_genus.v:
	@mkdir -p $(LOGS)
	$(GENUS) -batch -files genus/syn.tcl -log $(LOGS)/genus

lec_rtl: $(OUT)/genus/bayer2rgb_genus.v
	$(LEC) -xl -nogui -dofile $(OUT)/genus/rtl2gate.do

# ---- 配置配線(段階ごとに Innovus を起動する。前の段階の db を読む)
pnr: signoff

init:      $(DB)/01_init.db
floorplan: $(DB)/02_floorplan.db
place:     $(DB)/03_place.db
cts:       $(DB)/04_cts.db
route:     $(DB)/05_route.db
signoff:   $(DB)/06_signoff.db

$(DB)/01_init.db:      $(OUT)/genus/bayer2rgb_genus.v
$(DB)/02_floorplan.db: $(DB)/01_init.db
$(DB)/03_place.db:     $(DB)/02_floorplan.db
$(DB)/04_cts.db:       $(DB)/03_place.db
$(DB)/05_route.db:     $(DB)/04_cts.db
$(DB)/06_signoff.db:   $(DB)/05_route.db

$(DB)/%.db:
	@mkdir -p $(LOGS)
	$(INNOVUS_RUN) innovus/$(word 2,$(subst _, ,$*)).tcl -log $(LOGS)/innovus_$*

# ---- サインオフ
sta: $(DB)/06_signoff.db
	@mkdir -p $(LOGS)
	$(TEMPUS) -stylus -no_gui -files tempus/sta.tcl -log $(LOGS)/tempus

lec_g2g: $(DB)/06_signoff.db
	sed -e "s#@OUT@#$(OUT)#g" -e "s#@LIBS@#$(LEC_LIBS)#g" lec/gate2gate.do > $(OUT)/gate2gate.do
	$(LEC) -xl -nogui -dofile $(OUT)/gate2gate.do

drc: $(DB)/06_signoff.db
	cd $(OUT) && $(PEGASUS) -drc -dp $(CPUS) -top_cell BAYER2RGB -gds innovus/bayer2rgb_final.gds $(PEGASUS_DRC_RULES)

lvs: $(DB)/06_signoff.db
	cd $(OUT) && $(PEGASUS) -lvs -dp $(CPUS) -top_cell BAYER2RGB -gds innovus/bayer2rgb_final.gds \
	  -source_verilog innovus/bayer2rgb_final_pg.v $(PEGASUS_LVS_RULES)

clean:
	rm -rf out
