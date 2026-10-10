#==============================================================================
# Verilator + UVM (IEEE 1800.2-2020.3.2) で apb_master_mem を検証する
#
#   make                                   : ビルドして apbm_smoke_test を実行 (CFG=a)
#   make run TEST=apbm_rand_test SEED=7 NUM=10
#   make regress                           : smoke + rand (SEEDS) を連続実行
#   make regress CFG=b                     : 別の構成 (下の CFG_* を参照)
#   make regress_all                       : 全構成 (CFGS) で regress
#   make cov                               : その構成の全 run の機能カバレッジをマージして表示
#   make run WAVES=1                       : wave.fst を出力 (別ディレクトリに別ビルド)
#   make clean
#
# 必要なもの
#   Verilator 5.052 以降 (UVM 2020-3.2 を公式サポート)
#   UVM 1800.2-2020.3.2   (UVM_HOME で指定。src/uvm_pkg.sv があるディレクトリ)
#   z3                    (制約付きランダムの実行時ソルバ)
#==============================================================================
UVM_HOME  ?= $(HOME)/tools/uvm-verilator
VERILATOR ?= verilator
VCOV      ?= verilator_coverage
JOBS      ?= $(shell nproc)
TEST      ?= apbm_smoke_test
SEED      ?= 1
SEEDS     ?= 1 2 3 4 5
NUM       ?= 8
VERB      ?= UVM_MEDIUM
QUIT      ?= 200
WAVES     ?= 0
CFG       ?= a
CFGS      ?= a b c

RTL := ../../rtl
TB  := ../tb

#------------------------------------------------------------------------------
# 構成 (apbm_params_pkg.sv の `define を上書きする)
#------------------------------------------------------------------------------
# a : 既定 (アドレス 32bit、データ 32bit、スレーブ 3、メモリ 16 ワード、タイムアウト 6、エラーで中止)
CFG_a :=
# b : データ 8bit、アドレス 12bit、スレーブ 1、メモリ 10 ワード、タイムアウト無し、エラーでも最後まで続ける
CFG_b := +define+APBM_DATA_W=8 +define+APBM_ADDR_W=12 +define+APBM_NUM_SLAVES=1 +define+APBM_MEM_DEPTH=10 \
         +define+APBM_TIMEOUT_CYCLES=0 +define+APBM_STOP_ON_ERROR=0
# c : データ 16bit、アドレス 16bit、スレーブ 4、メモリ 64 ワード、タイムアウト 3、エラーでも最後まで続ける
CFG_c := +define+APBM_DATA_W=16 +define+APBM_ADDR_W=16 +define+APBM_NUM_SLAVES=4 +define+APBM_MEM_DEPTH=64 \
         +define+APBM_TIMEOUT_CYCLES=3 +define+APBM_STOP_ON_ERROR=0

ifeq ($(WAVES),1)
  OBJ       := obj_$(CFG)_waves
  WAVE_OPTS := --trace-fst +define+WAVES
else
  OBJ       := obj_$(CFG)
  WAVE_OPTS :=
endif
BIN := $(OBJ)/Vtb_top

# コンパイル順が必要 (uvm_pkg -> params -> if -> tb pkg -> DUT -> top)
SRCS := $(UVM_HOME)/src/uvm_pkg.sv \
        $(TB)/apbm_params_pkg.sv \
        $(TB)/apb_if.sv \
        $(TB)/usr_if.sv \
        $(TB)/apbm_uvm_pkg.sv \
        $(RTL)/apb_master_sram_sp.sv \
        $(RTL)/apb_master_engine.sv \
        $(RTL)/apb_master_mem.sv \
        $(TB)/tb_top.sv \
        $(UVM_HOME)/src/dpi/uvm_dpi.cc

# --binary               : --main --exe --build --timing をまとめて指定
# --vpi                  : UVM の DPI (src/dpi/uvm_hdl_verilator.c) が VPI を使う
# --coverage-user        : covergroup を有効化 (結果は +verilator+coverage+file+ に出力)
# --CFLAGS -O0           : UVM の生成 C++ は巨大なので g++ の最適化を切ってビルド時間を短縮
# -Werror-USERERROR      : パラメータチェック (エラボレーション時の $error) は必ずエラーにする
# APB_MASTER_SRAM_POISON : 内部メモリモデルの読み出しデータを 1 サイクルだけ有効にする
VFLAGS := --binary -j $(JOBS) --vpi --coverage-user \
          --top-module tb_top --timescale 1ns/1ps \
          +incdir+$(UVM_HOME)/src +incdir+$(TB) \
          -Wno-fatal -Wno-lint -Wno-style -Werror-USERERROR -Werror-USERFATAL \
          +define+APB_MASTER_SRAM_POISON $(CFG_$(CFG)) \
          --CFLAGS -O0 \
          --Mdir $(OBJ) $(WAVE_OPTS)

# $(1)=テスト名 $(2)=シード
#   +UVM_MAX_QUIT_COUNT : UVM_ERROR が QUIT 件に達したら打ち切る (ログの肥大化を防ぐ)
RUN_ARGS = +UVM_TESTNAME=$(1) +verilator+seed+$(2) +CMD_NUM=$(NUM) \
           +UVM_VERBOSITY=$(VERB) +UVM_NO_RELNOTES +UVM_MAX_QUIT_COUNT=$(QUIT),NO \
           +verilator+coverage+file+cov_$(CFG)_$(1)_$(2).dat

.PHONY: all build run regress regress_all cov clean

all: run

build: $(BIN)

$(BIN): $(SRCS) $(wildcard $(TB)/*.svh)
	$(VERILATOR) $(VFLAGS) $(SRCS)

run: $(BIN)
	$(BIN) $(call RUN_ARGS,$(TEST),$(SEED)) 2>&1 | tee run_$(CFG)_$(TEST)_$(SEED).log
	@grep -q "TEST PASSED" run_$(CFG)_$(TEST)_$(SEED).log

regress: $(BIN)
	@rm -f regress_$(CFG).txt
	@$(BIN) $(call RUN_ARGS,apbm_smoke_test,1) > run_$(CFG)_apbm_smoke_test_1.log 2>&1; \
	  if grep -q "TEST PASSED" run_$(CFG)_apbm_smoke_test_1.log; then r=PASS; else r=FAIL; fi; \
	  echo "[$(CFG)] apbm_smoke_test seed=1 : $$r" | tee -a regress_$(CFG).txt
	@for s in $(SEEDS); do \
	  $(BIN) $(call RUN_ARGS,apbm_rand_test,$$s) > run_$(CFG)_apbm_rand_test_$$s.log 2>&1; \
	  if grep -q "TEST PASSED" run_$(CFG)_apbm_rand_test_$$s.log; then r=PASS; else r=FAIL; fi; \
	  echo "[$(CFG)] apbm_rand_test  seed=$$s : $$r" | tee -a regress_$(CFG).txt; \
	done
	@! grep -q FAIL regress_$(CFG).txt

regress_all:
	@for c in $(CFGS); do \
	  $(MAKE) --no-print-directory regress CFG=$$c || exit 1; \
	  $(MAKE) --no-print-directory cov CFG=$$c || exit 1; \
	done

# その構成の全 run の coverage を 1 つにマージして covergroup の集計を表示
cov:
	@rm -f merged_cov_$(CFG).dat
	@$(VCOV) --filter-type covergroup --write merged_cov_$(CFG).dat cov_$(CFG)_*.dat
	@echo "[$(CFG)] $$($(VCOV) --filter-type covergroup --report summary merged_cov_$(CFG).dat | grep covergroup)"

clean:
	rm -rf obj_* *.log *.dat regress_*.txt wave.fst
