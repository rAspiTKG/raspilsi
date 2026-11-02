# ============================================================================
# BAYER_EX シミュレーション
#
#   make lint                         RTL の lint(Verilator -Wall)
#   make build                        Verilator でビルド
#   make run TEST=bex_smoke_test      Verilator で1テストを実行
#   make run TEST=... WAVES=1         波形(FST)を出す → gtkwave waves.fst
#   make regress                      回帰試験(tests.list)
#   make cov                          カバレッジ付きで回帰試験 → cov/code_coverage.md, cov/functional_coverage.md
#   make xrun TEST=...                Xcelium で実行(XWAVES=vcd で waves.vcd → GTKWave)
#
#   変数
#     DUT=core         core: BAYER_EX_CORE(インタフェースのポート)/ top: BAYER_EX(合成のトップ)
#     SEED=1           乱数のシード
#     UVM_HOME=...     UVM 1800.2-2017-1.0 のディレクトリ(src/uvm_pkg.sv があるところ)
#     PLUSARGS=...     追加のプラスアーグ(例: +BEX_FRAMES=20 +CLK_PS=2000)
#     RTL_F=...        RTL のファイルリスト(既定 ../rtl/rtl.f。tools/bex_mutate.py は書き換えた RTL を指定する)
#     OBJ=...          ビルドの出力先(既定 obj_<DUT>[_cov][_vcd])
# ============================================================================
ROOT      := $(abspath ..)
#UVM_HOME  ?= $(ROOT)/../uvm-1800.2-2017-1.0
DUT       ?= core
TEST      ?= bex_smoke_test
SEED      ?= 1
WAVES     ?= 0
COVERAGE  ?= 0
TRACE     ?= fst
PLUSARGS  ?=
VERBOSITY ?= UVM_LOW
VERILATOR ?= verilator
JOBS      ?= 0
# FST 出力には lz4 と zlib が要る(Ubuntu: apt install liblz4-dev zlib1g-dev)。
# 別の場所に入れた場合は VL_CFLAGS=-I<dir>/include VL_LDFLAGS=-L<dir>/lib を指定する
VL_CFLAGS  ?=
VL_LDFLAGS ?=
RTL_F      ?= $(ROOT)/rtl/rtl.f

DEFINES   := +define+UVM_NO_DPI $(EXTRA_DEFINES)
ifeq ($(DUT),top)
  DEFINES += +define+BEX_DUT_TOP
else ifneq ($(DUT),core)
  $(error DUT は core か top)
endif
BTAG      :=
ifeq ($(COVERAGE),1)
  VCOV    := --coverage-line --coverage-user
  BTAG    := $(BTAG)_cov
endif
# 波形の形式: fst(既定)/ vcd(仕様書の波形図の生成にも使う)
ifeq ($(TRACE),vcd)
  VTRACE  := --trace
  DEFINES += +define+BEX_VCD
  BTAG    := $(BTAG)_vcd
else
  VTRACE  := --trace-fst
endif

OBJ       := obj_$(DUT)$(BTAG)
BIN       := $(OBJ)/Vtb_top
FLIST     := -F $(RTL_F) -F $(ROOT)/tb/tb.f
LOGDIR    := logs

# --x-assign/--x-initial unique と実行時の +verilator+rand+reset+2 で、
# リセットしない FF の初期値を乱数にする(リセット値への依存を見つける)
# --assert: 検証環境のアサーション(bex_vbd_if)を有効にする
VFLAGS    := --binary --timing --assert -j $(JOBS) --top-module tb_top \
             --timescale 1ns/1ps $(VTRACE) --trace-structs \
             --x-assign unique --x-initial unique \
             -Wno-fatal -Wno-lint -Wno-style -Wno-COVERIGN -Wno-ZERODLY \
             -CFLAGS -O1 -CFLAGS -Wno-unused-value \
             $(addprefix -CFLAGS ,$(VL_CFLAGS)) $(addprefix -LDFLAGS ,$(VL_LDFLAGS)) \
             +incdir+$(UVM_HOME) $(UVM_HOME)/uvm_pkg.sv \
             $(DEFINES) $(VCOV) $(FLIST)
#             +incdir+$(UVM_HOME)/src $(UVM_HOME)/src/uvm_pkg.sv \

.PHONY: all lint build run regress cov xrun clean

all: build

lint:
	$(VERILATOR) --lint-only -Wall --top-module BAYER_EX $(ROOT)/rtl/bayer_ex_lint.vlt -F $(RTL_F)

build: $(BIN)

$(BIN): $(wildcard $(dir $(RTL_F))*.sv) $(wildcard $(ROOT)/tb/*.sv) $(wildcard $(ROOT)/tb/uvm/*.svh)
	$(VERILATOR) $(VFLAGS) -Mdir $(OBJ) -o Vtb_top > $(OBJ).build.log 2>&1 || (tail -40 $(OBJ).build.log; exit 1)

run: $(BIN)
	@mkdir -p $(LOGDIR)
	./$(BIN) +UVM_TESTNAME=$(TEST) +verilator+seed+$(SEED) +verilator+rand+reset+2 +UVM_VERBOSITY=$(VERBOSITY) \
	  $(if $(filter 1,$(WAVES)),+WAVES) $(PLUSARGS) | tee $(LOGDIR)/$(TEST)_$(DUT)_s$(SEED).log
	@grep -q "TEST PASSED" $(LOGDIR)/$(TEST)_$(DUT)_s$(SEED).log

regress:
	./run_regress.sh

cov:
	COVERAGE=1 ./run_regress.sh
	verilator_coverage --annotate cov/annotate --annotate-min 1 cov/*.dat > cov/summary.txt
	verilator_coverage --write-info cov/coverage.info cov/*.dat
	python3 $(ROOT)/tools/cov_summary.py cov/coverage.info --filter /rtl/ --md cov/code_coverage.md
	python3 $(ROOT)/tools/merge_cov.py $(LOGDIR)/*_n*_s*.log --md cov/functional_coverage.md

# ---- Xcelium -----------------------------------------------------------------
#   make xrun TEST=bex_smoke_test               波形なし
#   make xrun TEST=... XWAVES=vcd               waves.vcd を出す(GTKWave で見る)
#   make xrun TEST=... XWAVES=shm               waves.shm を出す(SimVision。xrun_waves.tcl を使う)
#   XUVM: -uvmhome に渡す UVM。既定は Xcelium 付属の CDNS-1.2。
#         Verilator と同じ UVM を使うときは XUVM=$(UVM_HOME)(UVM 1800.2-2017-1.0 のソース)
#   Xcelium では DPI が使えるので UVM_NO_DPI は定義しない
XRUN      ?= xrun
XWAVES    ?= none
XUVM      ?= CDNS-1.2
XDEFINES  := $(EXTRA_DEFINES)
ifeq ($(DUT),top)
  XDEFINES += +define+BEX_DUT_TOP
endif
XFLAGS    := -64bit -sv -timescale 1ns/1ps -access +rwc -uvm -uvmhome $(XUVM) \
             $(XDEFINES) -top tb_top -l $(LOGDIR)/xrun_$(TEST)_$(DUT)_s$(SEED).log \
             -svseed $(SEED) +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY) \
             -coverage all -covoverwrite -covtest $(TEST)_$(DUT)_s$(SEED) $(FLIST) $(PLUSARGS)
ifeq ($(XWAVES),shm)
  XFLAGS += -input xrun_waves.tcl
endif
ifeq ($(XWAVES),vcd)
  XFLAGS += +WAVES
endif

xrun:
	@mkdir -p $(LOGDIR)
	$(XRUN) $(XFLAGS)

clean:
	rm -rf obj_* logs cov mut waves.fst waves.vcd waves.shm xcelium.d xrun.history *.log dump
