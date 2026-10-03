#==============================================================================
# 簡易シミュレーション用 Makefile (Verilator 5.x)
#
#   make                : gearbox 単体 + トップの全構成を実行
#   make gearbox        : axi4_lb_gearbox の単体テスト (幅の組み合わせを複数)
#   make top            : axi4_master_linebuf を全構成 (CFGS) で実行
#   make one CFG=c2     : 1 構成だけ実行
#   make lint           : RTL を -Wall で lint (全構成)
#   make clean
#
# 構成は CFG_<名前> に Verilator の -G オプションで書く。追加する場合は
# CFG_xxx を定義して CFGS に足す。
#==============================================================================
VERILATOR ?= verilator
JOBS      ?= $(shell nproc)

RTL := ../rtl
TB  := ../tb

RTL_SRCS := $(RTL)/axi4_lb_fifo.sv \
            $(RTL)/axi4_lb_sram_sp.sv \
            $(RTL)/axi4_lb_gearbox.sv \
            $(RTL)/axi4_lb_rd_engine.sv \
            $(RTL)/axi4_lb_wr_engine.sv \
            $(RTL)/axi4_lb_scratchpad.sv \
            $(RTL)/axi4_master_linebuf.sv

# 警告は全てエラー扱い (-Wno-fatal を付けない)。
# AXI4_LB_SRAM_POISON : SRAM モデルの読み出しデータを 1 サイクルだけ有効にする
VFLAGS := --binary --timing -j $(JOBS) +define+AXI4_LB_SRAM_POISON

#------------------------------------------------------------------------------
# トップの構成
#------------------------------------------------------------------------------
# c1 : 既定 (64bit -> 64bit、8bit 画素、4 ライン)
CFG_c1 :=
# c2 : 32bit -> 128bit、10bit 画素を 16bit コンテナ、2 画素/ワード、2 ライン
CFG_c2 := -GIN_DATA_WIDTH=32 -GOUT_DATA_WIDTH=128 -GPIXEL_BITS=10 -GPIX_PER_WORD=2 -GNUM_LINES=2
# c3 : 128bit -> 32bit、24bit 画素 (RGB888)、3 ライン (2 のべき乗でない)
CFG_c3 := -GIN_DATA_WIDTH=128 -GOUT_DATA_WIDTH=32 -GPIXEL_BITS=24 -GNUM_LINES=3 -GMAX_LINE_PIXELS=100
# c4 : 10bit 画素を隙間なく詰める、4 画素/ワード、1 ライン
CFG_c4 := -GPIXEL_BITS=10 -GPIX_MEM_BITS=10 -GPIX_PER_WORD=4 -GNUM_LINES=1
# c5 : 512bit -> 64bit、12bit 画素を 16bit コンテナの上位詰め、8 画素/ワード、8 ライン
CFG_c5 := -GIN_DATA_WIDTH=512 -GOUT_DATA_WIDTH=64 -GPIXEL_BITS=12 -GPIX_ALIGN_MSB=1 -GPIX_PER_WORD=8 -GNUM_LINES=8 -GIN_MAX_BURST=4
# c6 : 8bit -> 16bit、1bit 画素、3 画素/ワード、最大幅 37、バースト 256 / 1
CFG_c6 := -GIN_DATA_WIDTH=8 -GOUT_DATA_WIDTH=16 -GPIXEL_BITS=1 -GPIX_MEM_BITS=1 -GPIX_PER_WORD=3 -GMAX_LINE_PIXELS=37 -GNUM_LINES=2 \
          -GIN_MAX_BURST=256 -GIN_FIFO_DEPTH=256 -GOUT_MAX_BURST=1 -GOUT_FIFO_DEPTH=2
# c7 : アドレス幅 40bit / 24bit、ID 幅 1 / 8、16bit 画素、5 ライン
CFG_c7 := -GIN_ADDR_WIDTH=40 -GOUT_ADDR_WIDTH=24 -GIN_ID_WIDTH=1 -GIN_AXI_ID=1 -GOUT_ID_WIDTH=8 -GOUT_AXI_ID=200 \
          -GPIXEL_BITS=16 -GNUM_LINES=5 -GIN_MAX_BURST=8 -GOUT_MAX_BURST=32 -GOUT_FIFO_DEPTH=32
# c8 : 1920 画素幅、64bit -> 256bit、8bit 画素、8 画素/ワード (1 ビート/サイクル)
CFG_c8 := -GOUT_DATA_WIDTH=256 -GPIX_PER_WORD=8 -GMAX_LINE_PIXELS=1920 -GNUM_LINES=4 -GSTRIDE_WIDTH=24 -GN_RAND=6
# c9 : 最大幅 1 画素、5 画素/ワード (1 ワードに収まる)、64bit 画素
CFG_c9 := -GPIXEL_BITS=64 -GPIX_PER_WORD=5 -GMAX_LINE_PIXELS=1 -GNUM_LINES=2
# c10: 1024bit -> 1024bit、13bit 画素を隙間なく詰める、7 画素/ワード、最大幅 4095
CFG_c10 := -GIN_DATA_WIDTH=1024 -GOUT_DATA_WIDTH=1024 -GPIXEL_BITS=13 -GPIX_MEM_BITS=13 -GPIX_PER_WORD=7 -GMAX_LINE_PIXELS=4095 \
           -GNUM_LINES=2 -GSTRIDE_WIDTH=24 -GN_RAND=5

CFGS ?= c1 c2 c3 c4 c5 c6 c7 c8 c9 c10
CFG  ?= c1

# gearbox 単体テストの (IN_BITS, OUT_BITS)
GB_PAIRS ?= 64_8 8_64 64_24 24_64 10_64 64_10 1_7 7_1 96_512 512_96 1024_13 13_1024 32_32 40_128

.PHONY: all gearbox top one lint clean

all: gearbox top

gearbox:
	@for p in $(GB_PAIRS); do \
	  i=$${p%_*}; \
	  o=$${p#*_}; \
	  $(VERILATOR) $(VFLAGS) --Mdir obj_gb_$$p -o tb --top-module tb_axi4_lb_gearbox \
	    -GIN_BITS=$$i -GOUT_BITS=$$o $(RTL)/axi4_lb_gearbox.sv $(TB)/tb_axi4_lb_gearbox.sv > gb_$$p.build.log 2>&1 \
	    || { echo "gearbox $$p : BUILD FAILED (see gb_$$p.build.log)"; exit 1; }; \
	  ./obj_gb_$$p/tb > gb_$$p.log 2>&1; \
	  if grep -q "TEST PASSED" gb_$$p.log; then echo "gearbox IN=$$i OUT=$$o : PASS"; else echo "gearbox IN=$$i OUT=$$o : FAIL (see gb_$$p.log)"; exit 1; fi; \
	done

top:
	@for c in $(CFGS); do \
	  $(MAKE) --no-print-directory one CFG=$$c || exit 1; \
	done

one:
	@$(VERILATOR) $(VFLAGS) --Mdir obj_$(CFG) -o tb --top-module tb_axi4_master_linebuf $(CFG_$(CFG)) \
	  $(RTL_SRCS) $(TB)/axi4_slave_mem_model.sv $(TB)/tb_axi4_master_linebuf.sv > $(CFG).build.log 2>&1 \
	  || { echo "$(CFG) : BUILD FAILED (see $(CFG).build.log)"; exit 1; }
	@./obj_$(CFG)/tb > $(CFG).log 2>&1; \
	  if grep -q "TEST PASSED" $(CFG).log; then echo "$(CFG) : PASS  [$(CFG_$(CFG))]"; else echo "$(CFG) : FAIL (see $(CFG).log)"; exit 1; fi

lint:
	@for c in $(CFGS); do \
	  $(MAKE) --no-print-directory lint_one CFG=$$c || exit 1; \
	done

.PHONY: lint_one
lint_one:
	@$(VERILATOR) --lint-only -Wall --top-module axi4_master_linebuf $(filter-out -GN_RAND=%,$(CFG_$(CFG))) $(RTL_SRCS) \
	  && echo "lint $(CFG) : clean"

clean:
	rm -rf obj_* *.log
