#==============================================================================
# 簡易シミュレーション用 Makefile (Verilator 5.x)
#
#   make                : エンジン単体 + トップの全構成を実行
#   make engine         : axil_master_engine の単体テスト (全構成)
#   make top            : axil_master_mem (+ axil_to_axi4) を全構成 (CFGS) で実行
#   make one CFG=c2     : トップを 1 構成だけ実行
#   make eng_one ECFG=e2: エンジン単体を 1 構成だけ実行
#   make lint           : RTL を -Wall で lint (全構成)
#   make top EXTRA=-GN_RAND=2000    : TB の parameter を追加で上書き (ランダムなコマンドの本数を増やす)
#   make engine EXTRA=-GN_REQ=20000 : 同上 (エンジン単体の要求数)
#   make clean
#
# 構成は CFG_<名前> / ECFG_<名前> に Verilator の -G オプションで書く。
# 追加する場合は定義して CFGS / ECFGS に足す。
#==============================================================================
VERILATOR ?= verilator
JOBS      ?= $(shell nproc)
EXTRA     ?=

RTL := ../rtl
TB  := ../tb

RTL_SRCS := $(RTL)/axil_master_rs.sv \
            $(RTL)/axil_master_sram_2p.sv \
            $(RTL)/axil_master_engine.sv \
            $(RTL)/axil_master_mem.sv \
            $(RTL)/axil_to_axi4.sv

ENG_SRCS := $(RTL)/axil_master_rs.sv \
            $(RTL)/axil_master_engine.sv

# 警告は全てエラー扱い (-Wno-fatal を付けない)。
# AXIL_MASTER_SRAM_POISON : 内部メモリモデルの読み出しデータを、読んだ次の 1 サイクルだけ有効にする
# --CFLAGS -O0            : シミュレーション自体は短いので、g++ の最適化を切ってビルド時間を短くする
VFLAGS := --binary --timing -j $(JOBS) +define+AXIL_MASTER_SRAM_POISON --CFLAGS -O0

#------------------------------------------------------------------------------
# トップ (axil_master_mem) の構成
#   TB 用の parameter : N_RAND (ランダムなコマンドの本数 / 方向)
#------------------------------------------------------------------------------
# c1 : 既定 (アドレス 32bit、データ 32bit、メモリ 16 ワード、未完了 4 / 4、エラーで中止)
CFG_c1 :=
# c2 : データ 64bit、メモリ 10 ワード (2 のべき乗でない)、未完了 1 / 1、エラーでも最後まで続ける
CFG_c2 := -GDATA_WIDTH=64 -GMEM_DEPTH=10 -GMAX_WR_OUTSTANDING=1 -GMAX_RD_OUTSTANDING=1 -GSTOP_ON_ERROR=0
# c3 : アドレス 16bit、メモリ 64 ワード、未完了 2 / 3
CFG_c3 := -GADDR_WIDTH=16 -GMEM_DEPTH=64 -GMAX_WR_OUTSTANDING=2 -GMAX_RD_OUTSTANDING=3
# c4 : メモリ 1 ワード、未完了 8 / 8、エラーでも最後まで続ける
CFG_c4 := -GMEM_DEPTH=1 -GMAX_WR_OUTSTANDING=8 -GMAX_RD_OUTSTANDING=8 -GSTOP_ON_ERROR=0
# c5 : アドレス 64bit、データ 64bit、メモリ 33 ワード、未完了 16 / 2
CFG_c5 := -GADDR_WIDTH=64 -GDATA_WIDTH=64 -GMEM_DEPTH=33 -GMAX_WR_OUTSTANDING=16 -GMAX_RD_OUTSTANDING=2
# c6 : アドレス空間がメモリより狭い (アドレス 6bit = 16 ワード、メモリ 24 ワード)、未完了 3 / 3
CFG_c6 := -GADDR_WIDTH=6 -GMEM_DEPTH=24 -GMAX_WR_OUTSTANDING=3 -GMAX_RD_OUTSTANDING=3
# c7 : アドレス 12bit、メモリ 2 ワード、未完了 1 / 16、エラーでも最後まで続ける
CFG_c7 := -GADDR_WIDTH=12 -GMEM_DEPTH=2 -GMAX_WR_OUTSTANDING=1 -GMAX_RD_OUTSTANDING=16 -GSTOP_ON_ERROR=0
# c8 : アドレス 20bit、データ 64bit、メモリ 7 ワード、未完了 5 / 4
CFG_c8 := -GADDR_WIDTH=20 -GDATA_WIDTH=64 -GMEM_DEPTH=7 -GMAX_WR_OUTSTANDING=5 -GMAX_RD_OUTSTANDING=4

CFGS ?= c1 c2 c3 c4 c5 c6 c7 c8
CFG  ?= c1

#------------------------------------------------------------------------------
# エンジン単体 (axil_master_engine) の構成
#------------------------------------------------------------------------------
ECFG_e1 :=
ECFG_e2 := -GMAX_WR_OUTSTANDING=1 -GMAX_RD_OUTSTANDING=1
ECFG_e3 := -GDATA_WIDTH=64 -GMAX_WR_OUTSTANDING=2 -GMAX_RD_OUTSTANDING=3
ECFG_e4 := -GADDR_WIDTH=64 -GDATA_WIDTH=64 -GMAX_WR_OUTSTANDING=8 -GMAX_RD_OUTSTANDING=5
ECFG_e5 := -GADDR_WIDTH=4 -GMAX_WR_OUTSTANDING=3 -GMAX_RD_OUTSTANDING=2
ECFG_e6 := -GADDR_WIDTH=12 -GMAX_WR_OUTSTANDING=16 -GMAX_RD_OUTSTANDING=1
ECFG_e7 := -GADDR_WIDTH=5 -GDATA_WIDTH=64 -GMAX_WR_OUTSTANDING=1 -GMAX_RD_OUTSTANDING=16

ECFGS ?= e1 e2 e3 e4 e5 e6 e7
ECFG  ?= e1

.PHONY: all engine top one eng_one lint lint_one clean

all: engine top

engine:
	@for c in $(ECFGS); do \
	  $(MAKE) --no-print-directory eng_one ECFG=$$c || exit 1; \
	done

eng_one:
	@$(VERILATOR) $(VFLAGS) --Mdir obj_$(ECFG) -o tb --top-module tb_axil_master_engine $(ECFG_$(ECFG)) $(EXTRA) \
	  $(ENG_SRCS) $(TB)/axil_slave_mem_model.sv $(TB)/tb_axil_master_engine.sv > $(ECFG).build.log 2>&1 \
	  || { echo "$(ECFG) : BUILD FAILED (see $(ECFG).build.log)"; exit 1; }
	@./obj_$(ECFG)/tb > $(ECFG).log 2>&1; \
	  if grep -q "TEST PASSED" $(ECFG).log; then echo "engine $(ECFG) : PASS  [$(strip $(ECFG_$(ECFG)) $(EXTRA))]"; else echo "engine $(ECFG) : FAIL (see $(ECFG).log)"; exit 1; fi

top:
	@for c in $(CFGS); do \
	  $(MAKE) --no-print-directory one CFG=$$c || exit 1; \
	done

one:
	@$(VERILATOR) $(VFLAGS) --Mdir obj_$(CFG) -o tb --top-module tb_axil_master_mem $(CFG_$(CFG)) $(EXTRA) \
	  $(RTL_SRCS) $(TB)/axil_slave_mem_model.sv $(TB)/tb_axil_master_mem.sv > $(CFG).build.log 2>&1 \
	  || { echo "$(CFG) : BUILD FAILED (see $(CFG).build.log)"; exit 1; }
	@./obj_$(CFG)/tb > $(CFG).log 2>&1; \
	  if grep -q "TEST PASSED" $(CFG).log; then echo "top $(CFG) : PASS  [$(strip $(CFG_$(CFG)) $(EXTRA))]"; else echo "top $(CFG) : FAIL (see $(CFG).log)"; exit 1; fi

# axil_master_mem (エンジンを含む) と axil_to_axi4 を、構成ごとに lint
lint:
	@for c in $(CFGS); do \
	  $(MAKE) --no-print-directory lint_one CFG=$$c || exit 1; \
	done

lint_one:
	@$(VERILATOR) --lint-only -Wall --top-module axil_master_mem $(filter-out -GN_RAND=%,$(CFG_$(CFG))) $(RTL_SRCS) \
	  && $(VERILATOR) --lint-only -Wall --top-module axil_to_axi4 $(filter -GADDR_WIDTH=% -GDATA_WIDTH=%,$(CFG_$(CFG))) $(RTL)/axil_to_axi4.sv \
	  && echo "lint $(CFG) : clean"

clean:
	rm -rf obj_* *.log
