# 簡易シミュレーション用 Makefile (Verilator 5.x)
#   make          : 3 本の TB を全てビルドして実行
#   make tb1      : axi4_full_slave_mem
#   make tb2      : axi4_full_passthrough (BYPASS=0)
#   make tb2_byp  : axi4_full_passthrough (BYPASS=1)
#   make tb3      : axi4_full_slave_stream
#   make tb4      : axi4_full_to_p2p_bridge (B_WAIT_DRAIN=0, RD_TIMEOUT=0)
#   make tb4_drain: axi4_full_to_p2p_bridge (B_WAIT_DRAIN=1)
#   make tb4_to   : axi4_full_to_p2p_bridge (RD_TIMEOUT=200)
RTL := ../rtl
TB  := ../tb
VFLAGS := --binary --timing -j 4 -Wno-fatal

.PHONY: all tb1 tb2 tb2_byp tb3 tb4 tb4_drain tb4_to clean

BRIDGE_SRC := $(RTL)/axi4_full_to_p2p_bridge.sv $(RTL)/axi4_sync_fifo.sv \
              $(TB)/axi4_full_master_bfm.sv $(TB)/p2p_source_bfm.sv $(TB)/p2p_sink_bfm.sv \
              $(TB)/tb_axi4_full_to_p2p_bridge.sv

all: tb1 tb2 tb2_byp tb3 tb4 tb4_drain tb4_to

tb1:
	verilator $(VFLAGS) --Mdir obj_tb1 -o tb1 --top-module tb_axi4_full_slave_mem \
	  $(RTL)/axi4_full_slave_mem.sv $(TB)/axi4_full_master_bfm.sv $(TB)/tb_axi4_full_slave_mem.sv
	./obj_tb1/tb1

tb2:
	verilator $(VFLAGS) --Mdir obj_tb2 -o tb2 --top-module tb_axi4_full_passthrough \
	  $(RTL)/axi4_full_passthrough.sv $(RTL)/axi4_skid_buffer.sv $(RTL)/axi4_full_slave_mem.sv \
	  $(TB)/axi4_full_master_bfm.sv $(TB)/tb_axi4_full_passthrough.sv
	./obj_tb2/tb2

tb2_byp:
	verilator $(VFLAGS) -GPT_BYPASS=1 --Mdir obj_tb2b -o tb2b --top-module tb_axi4_full_passthrough \
	  $(RTL)/axi4_full_passthrough.sv $(RTL)/axi4_skid_buffer.sv $(RTL)/axi4_full_slave_mem.sv \
	  $(TB)/axi4_full_master_bfm.sv $(TB)/tb_axi4_full_passthrough.sv
	./obj_tb2b/tb2b

tb3:
	verilator $(VFLAGS) --Mdir obj_tb3 -o tb3 --top-module tb_axi4_full_slave_stream \
	  $(RTL)/axi4_full_slave_stream.sv $(TB)/axi4_full_master_bfm.sv $(TB)/tb_axi4_full_slave_stream.sv
	./obj_tb3/tb3

tb4:
	verilator $(VFLAGS) --Mdir obj_tb4 -o tb4 --top-module tb_axi4_full_to_p2p_bridge $(BRIDGE_SRC)
	./obj_tb4/tb4

tb4_drain:
	verilator $(VFLAGS) -GTB_B_WAIT_DRAIN=1 --Mdir obj_tb4d -o tb4d \
	  --top-module tb_axi4_full_to_p2p_bridge $(BRIDGE_SRC)
	./obj_tb4d/tb4d

tb4_to:
	verilator $(VFLAGS) -GTB_RD_TIMEOUT=200 --Mdir obj_tb4t -o tb4t \
	  --top-module tb_axi4_full_to_p2p_bridge $(BRIDGE_SRC)
	./obj_tb4t/tb4t

clean:
	rm -rf obj_tb1 obj_tb2 obj_tb2b obj_tb3 obj_tb4 obj_tb4d obj_tb4t
