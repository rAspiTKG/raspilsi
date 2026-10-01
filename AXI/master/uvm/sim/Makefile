#==============================================================================
# Verilator + UVM (IEEE 1800.2-2020.3.2) で axi4_full_master_copy を検証する
#
#   make                                   : ビルドして copy_smoke_test を実行
#   make run TEST=copy_rand_test SEED=7 NUM=20
#   make regress                           : smoke + rand (SEEDS) を連続実行
#   make cov                               : 全 run の機能カバレッジをマージして表示
#   make run WAVES=1                       : wave.fst を出力 (obj_dir_waves に別ビルド)
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
TEST      ?= copy_smoke_test
SEED      ?= 1
SEEDS     ?= 1 2 3 4 5
NUM       ?= 10
VERB      ?= UVM_MEDIUM
WAVES     ?= 0

RTL := ../../rtl
TB  := ../tb

ifeq ($(WAVES),1)
  OBJ       := obj_dir_waves
  WAVE_OPTS := --trace-fst +define+WAVES
else
  OBJ       := obj_dir
  WAVE_OPTS :=
endif
BIN := $(OBJ)/Vtb_top

# コンパイル順が必要 (uvm_pkg -> params -> if -> tb pkg -> DUT -> top)
SRCS := $(UVM_HOME)/src/uvm_pkg.sv \
        $(TB)/axi_params_pkg.sv \
        $(TB)/axi_if.sv \
        $(TB)/cmd_if.sv \
        $(TB)/copy_uvm_pkg.sv \
        $(RTL)/axi4_sync_fifo.sv \
        $(RTL)/axi4_mst_wr_engine.sv \
        $(RTL)/axi4_mst_rd_engine.sv \
        $(RTL)/axi4_full_master_copy.sv \
        $(TB)/tb_top.sv \
        $(UVM_HOME)/src/dpi/uvm_dpi.cc

# --binary       : --main --exe --build --timing をまとめて指定
# --vpi          : UVM の DPI (src/dpi/uvm_hdl_verilator.c) が VPI を使う
# --coverage-user: covergroup を有効化 (結果は +verilator+coverage+file+ に出力)
# --CFLAGS -O0   : UVM の生成 C++ は巨大なので g++ の最適化を切ってビルド時間を短縮
VFLAGS := --binary -j $(JOBS) --vpi --coverage-user \
          --top-module tb_top --timescale 1ns/1ps \
          +incdir+$(UVM_HOME)/src +incdir+$(TB) \
          -Wno-fatal -Wno-lint -Wno-style \
          --CFLAGS -O0 \
          --Mdir $(OBJ) $(WAVE_OPTS)

# $(1)=テスト名 $(2)=シード
RUN_ARGS = +UVM_TESTNAME=$(1) +verilator+seed+$(2) +CMD_NUM=$(NUM) \
           +UVM_VERBOSITY=$(VERB) +UVM_NO_RELNOTES \
           +verilator+coverage+file+cov_$(1)_$(2).dat

.PHONY: all build run regress cov clean

all: run

build: $(BIN)

$(BIN): $(SRCS) $(wildcard $(TB)/*.svh)
	$(VERILATOR) $(VFLAGS) $(SRCS)

run: $(BIN)
	$(BIN) $(call RUN_ARGS,$(TEST),$(SEED)) 2>&1 | tee run_$(TEST)_$(SEED).log
	@grep -q "TEST PASSED" run_$(TEST)_$(SEED).log

regress: $(BIN)
	@rm -f regress.txt
	@$(BIN) $(call RUN_ARGS,copy_smoke_test,1) > run_copy_smoke_test_1.log 2>&1; \
	  if grep -q "TEST PASSED" run_copy_smoke_test_1.log; then r=PASS; else r=FAIL; fi; \
	  echo "copy_smoke_test seed=1 : $$r" | tee -a regress.txt
	@for s in $(SEEDS); do \
	  $(BIN) $(call RUN_ARGS,copy_rand_test,$$s) > run_copy_rand_test_$$s.log 2>&1; \
	  if grep -q "TEST PASSED" run_copy_rand_test_$$s.log; then r=PASS; else r=FAIL; fi; \
	  echo "copy_rand_test  seed=$$s : $$r" | tee -a regress.txt; \
	done
	@! grep -q FAIL regress.txt

# 全 run の coverage を 1 つにマージして covergroup の集計を表示
cov:
	@rm -f merged_cov.dat
	$(VCOV) --filter-type covergroup --write merged_cov.dat cov_*.dat
	$(VCOV) --filter-type covergroup --report summary merged_cov.dat

clean:
	rm -rf obj_dir obj_dir_waves *.log *.dat regress.txt wave.fst
