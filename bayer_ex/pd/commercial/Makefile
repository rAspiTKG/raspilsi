# ============================================================================
# BAYER_EX の商用ツールの流れ(Cadence、Foundry の PDK。雛形・未検証)
#
#   make syn        論理合成(Genus)          → out/foundry/genus/
#   make lec_rtl    RTL と合成後の等価性検証(Conformal。Genus が書いた dofile)
#   make pnr        配置配線(Innovus。init floorplan place cts route signoff の順)
#   make sta        サインオフの STA(Tempus。RC コーナーごとの SPEF を使う)
#   make lec_g2g    合成後と配置配線後の等価性検証(Conformal)
#   make drc / lvs  物理検証(Pegasus。ルールファイルは PDK のもの)
#   make all        syn lec_rtl pnr sta lec_g2g
#
#   先に setup/foundry_setup.tcl の <...> を PDK に合わせて記入する。
#
#   変数: CLK_PERIOD=2.5  CPUS=8
#         GENUS / INNOVUS / TEMPUS / LEC / PEGASUS   ツールのコマンド
# ============================================================================
CLK_PERIOD  ?= 2.5
CPUS        ?= 8
GENUS       ?= genus
INNOVUS     ?= innovus
TEMPUS      ?= tempus
LEC         ?= lec
PEGASUS     ?= pegasus

OUT         := $(CURDIR)/out/foundry
DB          := $(OUT)/innovus/db
LOGS        := $(OUT)/logs
export BEX_CLK_PERIOD := $(CLK_PERIOD)
export BEX_CPUS       := $(CPUS)

# Conformal に渡す Liberty(最も遅いコーナー)と Pegasus のルール(PDK のもの)
LEC_LIBS          ?= <PDK の標準セルの Liberty(ss コーナー)>
PEGASUS_DRC_RULES ?= <PDK の Pegasus DRC ルール>
PEGASUS_LVS_RULES ?= <PDK の Pegasus LVS ルール>

INNOVUS_RUN = $(INNOVUS) -stylus -no_gui -files
STAGES      := init floorplan place cts route signoff

.PHONY: all syn lec_rtl pnr $(STAGES) sta lec_g2g drc lvs clean

all: syn lec_rtl pnr sta lec_g2g

# ---- 論理合成
syn: $(OUT)/genus/bayer_ex_genus.v

$(OUT)/genus/bayer_ex_genus.v:
	@mkdir -p $(LOGS)
	$(GENUS) -batch -files genus/syn.tcl -log $(LOGS)/genus

lec_rtl: $(OUT)/genus/bayer_ex_genus.v
	$(LEC) -xl -nogui -dofile $(OUT)/genus/rtl2gate.do

# ---- 配置配線(段階ごとに Innovus を起動する。前の段階の db を読む)
pnr: signoff

init:      $(DB)/01_init.db
floorplan: $(DB)/02_floorplan.db
place:     $(DB)/03_place.db
cts:       $(DB)/04_cts.db
route:     $(DB)/05_route.db
signoff:   $(DB)/06_signoff.db

$(DB)/01_init.db:      $(OUT)/genus/bayer_ex_genus.v
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
	cd $(OUT) && $(PEGASUS) -drc -dp $(CPUS) -top_cell BAYER_EX -gds innovus/bayer_ex_final.gds $(PEGASUS_DRC_RULES)

lvs: $(DB)/06_signoff.db
	cd $(OUT) && $(PEGASUS) -lvs -dp $(CPUS) -top_cell BAYER_EX -gds innovus/bayer_ex_final.gds \
	  -source_verilog innovus/bayer_ex_final_pg.v $(PEGASUS_LVS_RULES)

clean:
	rm -rf out
