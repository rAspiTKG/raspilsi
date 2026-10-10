#==============================================================================
# 簡易シミュレーション用 Makefile (Verilator 5.x)
#
#   make                : エンジン単体 + トップの全構成を実行
#   make engine         : apb_master_engine の単体テスト (全構成)
#   make top            : apb_master_mem を全構成 (CFGS) で実行
#   make one CFG=c2     : トップを 1 構成だけ実行
#   make eng_one ECFG=e2: エンジン単体を 1 構成だけ実行
#   make lint           : RTL を -Wall で lint (全構成)
#   make top EXTRA=-GN_RAND=5000    : TB の parameter を追加で上書き (ランダムなコマンドの本数を増やす)
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

RTL_SRCS := $(RTL)/apb_master_sram_sp.sv \
            $(RTL)/apb_master_engine.sv \
            $(RTL)/apb_master_mem.sv

# 警告は全てエラー扱い (-Wno-fatal を付けない)。
# APB_MASTER_SRAM_POISON : 内部メモリモデルの読み出しデータを 1 サイクルだけ有効にする
# --CFLAGS -O0           : シミュレーション自体は一瞬で終わるので、g++ の最適化を切ってビルド時間を短くする
VFLAGS := --binary --timing -j $(JOBS) +define+APB_MASTER_SRAM_POISON --CFLAGS -O0

#------------------------------------------------------------------------------
# トップ (apb_master_mem) の構成
#------------------------------------------------------------------------------
# c1 : 既定 (アドレス 32bit、データ 32bit、スレーブ 1、メモリ 16 ワード、タイムアウト無し、エラーで中止)
CFG_c1 :=
# c2 : データ 8bit、アドレス 12bit、スレーブ 3、メモリ 10 ワード (2 のべき乗でない)、タイムアウト 8
CFG_c2 := -GDATA_WIDTH=8 -GADDR_WIDTH=12 -GNUM_SLAVES=3 -GMEM_DEPTH=10 -GTIMEOUT_CYCLES=8
# c3 : データ 16bit、アドレス 16bit、スレーブ 4、メモリ 64 ワード、エラーでも最後まで続ける
CFG_c3 := -GDATA_WIDTH=16 -GADDR_WIDTH=16 -GNUM_SLAVES=4 -GMEM_DEPTH=64 -GSTOP_ON_ERROR=0
# c4 : スレーブ 2、メモリ 256 ワード、タイムアウト 3、エラーでも最後まで続ける
CFG_c4 := -GNUM_SLAVES=2 -GMEM_DEPTH=256 -GTIMEOUT_CYCLES=3 -GSTOP_ON_ERROR=0 -GN_RAND=60
# c5 : メモリ 1 ワード、アドレス 8bit、タイムアウト 1 (ウェイトを許さない)
CFG_c5 := -GADDR_WIDTH=8 -GMEM_DEPTH=1 -GTIMEOUT_CYCLES=1
# c6 : アドレス空間がメモリより狭い (アドレス 5bit、データ 16bit = 16 ワード、メモリ 24 ワード)、スレーブ 5
CFG_c6 := -GADDR_WIDTH=5 -GDATA_WIDTH=16 -GNUM_SLAVES=5 -GMEM_DEPTH=24 -GTIMEOUT_CYCLES=5
# c7 : データ 8bit、スレーブ 16、メモリ 7 ワード、タイムアウト 16、エラーでも最後まで続ける
CFG_c7 := -GDATA_WIDTH=8 -GNUM_SLAVES=16 -GMEM_DEPTH=7 -GTIMEOUT_CYCLES=16 -GSTOP_ON_ERROR=0
# c8 : アドレス 10bit、メモリ 3 ワード、タイムアウト 2、エラーでも最後まで続ける
CFG_c8 := -GADDR_WIDTH=10 -GMEM_DEPTH=3 -GTIMEOUT_CYCLES=2 -GSTOP_ON_ERROR=0

CFGS ?= c1 c2 c3 c4 c5 c6 c7 c8
CFG  ?= c1

#------------------------------------------------------------------------------
# エンジン単体 (apb_master_engine) の構成
#------------------------------------------------------------------------------
ECFG_e1 :=
ECFG_e2 := -GNUM_SLAVES=3 -GTIMEOUT_CYCLES=6 -GFLUSH_ON_ERROR=1
ECFG_e3 := -GDATA_WIDTH=8 -GADDR_WIDTH=5 -GNUM_SLAVES=2 -GTIMEOUT_CYCLES=1
ECFG_e4 := -GDATA_WIDTH=16 -GADDR_WIDTH=12 -GNUM_SLAVES=5 -GFLUSH_ON_ERROR=1
ECFG_e5 := -GTIMEOUT_CYCLES=2 -GFLUSH_ON_ERROR=1
ECFG_e6 := -GNUM_SLAVES=4 -GTIMEOUT_CYCLES=3
ECFG_e7 := -GADDR_WIDTH=3 -GNUM_SLAVES=2 -GFLUSH_ON_ERROR=1
ECFG_e8 := -GDATA_WIDTH=8 -GNUM_SLAVES=16 -GTIMEOUT_CYCLES=16 -GFLUSH_ON_ERROR=1

ECFGS ?= e1 e2 e3 e4 e5 e6 e7 e8
ECFG  ?= e1

.PHONY: all engine top one eng_one lint lint_one clean

all: engine top

engine:
	@for c in $(ECFGS); do \
	  $(MAKE) --no-print-directory eng_one ECFG=$$c || exit 1; \
	done

eng_one:
	@$(VERILATOR) $(VFLAGS) --Mdir obj_$(ECFG) -o tb --top-module tb_apb_master_engine $(ECFG_$(ECFG)) $(EXTRA) \
	  $(RTL)/apb_master_engine.sv $(TB)/apb_slave_mem_model.sv $(TB)/tb_apb_master_engine.sv > $(ECFG).build.log 2>&1 \
	  || { echo "$(ECFG) : BUILD FAILED (see $(ECFG).build.log)"; exit 1; }
	@./obj_$(ECFG)/tb > $(ECFG).log 2>&1; \
	  if grep -q "TEST PASSED" $(ECFG).log; then echo "engine $(ECFG) : PASS  [$(strip $(ECFG_$(ECFG)) $(EXTRA))]"; else echo "engine $(ECFG) : FAIL (see $(ECFG).log)"; exit 1; fi

top:
	@for c in $(CFGS); do \
	  $(MAKE) --no-print-directory one CFG=$$c || exit 1; \
	done

one:
	@$(VERILATOR) $(VFLAGS) --Mdir obj_$(CFG) -o tb --top-module tb_apb_master_mem $(CFG_$(CFG)) $(EXTRA) \
	  $(RTL_SRCS) $(TB)/apb_slave_mem_model.sv $(TB)/tb_apb_master_mem.sv > $(CFG).build.log 2>&1 \
	  || { echo "$(CFG) : BUILD FAILED (see $(CFG).build.log)"; exit 1; }
	@./obj_$(CFG)/tb > $(CFG).log 2>&1; \
	  if grep -q "TEST PASSED" $(CFG).log; then echo "top $(CFG) : PASS  [$(strip $(CFG_$(CFG)) $(EXTRA))]"; else echo "top $(CFG) : FAIL (see $(CFG).log)"; exit 1; fi

lint:
	@for c in $(CFGS); do \
	  $(MAKE) --no-print-directory lint_one CFG=$$c || exit 1; \
	done

lint_one:
	@$(VERILATOR) --lint-only -Wall --top-module apb_master_mem $(filter-out -GN_RAND=%,$(CFG_$(CFG))) $(RTL_SRCS) \
	  && echo "lint $(CFG) : clean"

clean:
	rm -rf obj_* *.log
