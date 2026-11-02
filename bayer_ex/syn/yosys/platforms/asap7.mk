# ============================================================================
# ASAP7(7nm 相当の公開PDK)の設定
#   ライブラリは OpenROAD-flow-scripts(ORFS)の flow/platforms/asap7 を使う。
#   ORFS_FLOW に ORFS の flow ディレクトリを指定する。
#   単位は ps / fF。コーナー: WC(SS 0.63V 100C、既定)/ TC(TT 0.70V 0C)/ BC(FF 0.77V 25C)
# ============================================================================
ORFS_FLOW      ?= $(HOME)/OpenROAD-flow-scripts/flow
PLATFORM_DIR   ?= $(ORFS_FLOW)/platforms/asap7
CORNER         ?= WC

LIB_DIR        := $(PLATFORM_DIR)/lib/NLDM
CORNER_TAG_WC  := SS
CORNER_TAG_TC  := TT
CORNER_TAG_BC  := FF
CT             := $(CORNER_TAG_$(CORNER))

# 標準セル(RVT)
STD_LIBS       := $(LIB_DIR)/asap7sc7p5t_AO_RVT_$(CT)_nldm_211120.lib.gz \
                  $(LIB_DIR)/asap7sc7p5t_INVBUF_RVT_$(CT)_nldm_220122.lib.gz \
                  $(LIB_DIR)/asap7sc7p5t_OA_RVT_$(CT)_nldm_211120.lib.gz \
                  $(LIB_DIR)/asap7sc7p5t_SIMPLE_RVT_$(CT)_nldm_211120.lib.gz \
                  $(LIB_DIR)/asap7sc7p5t_SEQ_RVT_$(CT)_nldm_220123.lib
DFF_LIB_SRC    := $(LIB_DIR)/asap7sc7p5t_SEQ_RVT_$(CT)_nldm_220123.lib

# 配線の混雑を避けるため使わないセル(ORFS の asap7 と同じ)
DONT_USE_CELLS := *x1p*_ASAP7* *xp*_ASAP7* SDF* ICG*

LATCH_MAP      := $(PLATFORM_DIR)/yoSys/cells_latch_R.v
EXTRA_MAP      := $(ORFS_FLOW)/platforms/common/lcu_kogge_stone.v
ADDER_MAP      := $(PLATFORM_DIR)/yoSys/cells_adders_R.v
TIEHI          := TIEHIx1_ASAP7_75t_R H
TIELO          := TIELOx1_ASAP7_75t_R L
MIN_BUF        := BUFx2_ASAP7_75t_R A Y
ABC_DRIVER     := BUFx2_ASAP7_75t_R
ABC_LOAD       := 3.898

TIME_UNIT      := ps
CAP_UNIT       := fF
TIME_SCALE     := 1000
