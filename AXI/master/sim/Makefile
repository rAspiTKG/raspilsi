# 簡易シミュレーション用 Makefile (Verilator 5.x)
#   make           : 全 TB を実行
#   make copy      : axi4_full_master_copy
#   make stream    : axi4_full_master_stream
#   make p2p       : axi4_full_master_p2p_bridge
#   make passthru  : axi4_full_passthrough (据え置き。BYPASS=0)
RTL := ../rtl
TB  := ../tb
VFLAGS := --binary --timing -j 4 -Wno-fatal

ENGINE := $(RTL)/axi4_sync_fifo.sv $(RTL)/axi4_mst_wr_engine.sv $(RTL)/axi4_mst_rd_engine.sv
P2PBFM := $(TB)/p2p_source_bfm.sv $(TB)/p2p_sink_bfm.sv
MODEL  := $(TB)/axi4_slave_mem_model.sv

.PHONY: all copy stream p2p passthru clean

all: copy stream p2p passthru

copy:
	verilator $(VFLAGS) --Mdir obj_copy -o tb --top-module tb_axi4_full_master_copy \
	  $(ENGINE) $(RTL)/axi4_full_master_copy.sv $(MODEL) $(TB)/tb_axi4_full_master_copy.sv
	./obj_copy/tb

stream:
	verilator $(VFLAGS) --Mdir obj_stream -o tb --top-module tb_axi4_full_master_stream \
	  $(ENGINE) $(RTL)/axi4_full_master_stream.sv $(MODEL) $(P2PBFM) $(TB)/tb_axi4_full_master_stream.sv
	./obj_stream/tb

p2p:
	verilator $(VFLAGS) --Mdir obj_p2p -o tb --top-module tb_axi4_full_master_p2p_bridge \
	  $(ENGINE) $(RTL)/axi4_full_master_p2p_bridge.sv $(MODEL) $(P2PBFM) $(TB)/tb_axi4_full_master_p2p_bridge.sv
	./obj_p2p/tb

passthru:
	verilator $(VFLAGS) --Mdir obj_passthru -o tb --top-module tb_axi4_full_passthrough \
	  $(RTL)/axi4_full_passthrough.sv $(RTL)/axi4_skid_buffer.sv \
	  $(TB)/axi4_full_slave_mem.sv $(TB)/axi4_full_master_bfm.sv $(TB)/tb_axi4_full_passthrough.sv
	./obj_passthru/tb

clean:
	rm -rf obj_* *.log
