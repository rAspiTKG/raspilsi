#==============================================================================
# bus_if : interface とサンプルを Verilator で lint / シミュレーションする
#
#   make                  : lint + 全サンプルの TB + 違反注入 + チェックの自己テスト
#   make lint             : interface + サンプルの RTL を -Wall で lint (プロトコルごとに 2 通り)
#                             SYNTHESIS あり : 合成で読む内容 (信号 + modport)
#                             SYNTHESIS なし : SVA と clocking block を含む内容。SYNCASYNCNET だけ外す
#                             (SVA の disable iff がリセットを同期で使うとみなされるため。RTL のリセットは非同期)
#   make sim              : 全サンプルの自己チェック TB (sample/<P>/tb_<P>_smp.sv)
#   make bad              : +BAD で各 TB にプロトコル違反を 1 つ入れ、interface のチェックが止めることを確かめる
#   make chk              : チェックの自己テスト (check/tb_<P>_chk.sv)。正しい転送でエラーが出ないことと、
#                           違反ごとに決めたエラーが出ることを確かめる
#   make role             : TB_ROLE の確認の自己テスト (check/tb_role_chk.sv)。TB_ROLE がつながない側の
#                           clocking block に書いたとき、6 種類 x 2 = 12 個の $warning が出ることを確かめる
#   make uvm UVM_HOME=<dir> : axil_if を UVM (uvm_config_db + virtual interface) で使う例 (sample/uvm)。
#                           make all には入れない (UVM 1800.2-2020.3.2 が必要。ビルドに 2 分ほどかかる)
#   make run P=axi4       : 1 つだけ実行 (P = axi4 axil ahb apb p2p strm)
#   make run P=axi4 PARAMS="-GDW=32 -GIW=1"
#                         : TB の parameter を変えて実行 (axi4 : AW / DW / IW、p2p : DW、strm : DW / IW / AW)
#   make files P=ahb      : そのプロトコルの interface と合成できるサンプルのファイル一覧 (他のツールに渡す用)
#   make clean
#
# 必要なもの : Verilator 5.x (--timing、clocking block、SVA を使う。5.052 で確認)
#==============================================================================
VERILATOR ?= verilator
JOBS      ?= $(shell nproc)
PROTOS    ?= axi4 axil ahb apb p2p strm
PARAMS    ?=

IF  := ../if
SMP := ../sample
CHK := ../check

# プロトコルごとのファイル (interface / 合成できるサンプル / TB) と、+BAD で出るべきアサーション名
IF_axi4  := $(IF)/axi4_if.sv
RTL_axi4 := $(SMP)/axi4/axi4_smp_mgr.sv $(SMP)/axi4/axi4_smp_mem.sv $(SMP)/axi4/axi4_smp_top.sv
TB_axi4  := $(SMP)/axi4/tb_axi4_smp.sv
BAD_axi4 := a_aw_hold

IF_axil  := $(IF)/axil_if.sv
RTL_axil := $(SMP)/axil/axil_smp_mgr.sv $(SMP)/axil/axil_smp_regs.sv $(SMP)/axil/axil_smp_top.sv
TB_axil  := $(SMP)/axil/tb_axil_smp.sv
BAD_axil := a_aw_hold

IF_ahb   := $(IF)/ahb_if.sv
RTL_ahb  := $(SMP)/ahb/ahb_smp_mgr.sv $(SMP)/ahb/ahb_smp_ic.sv $(SMP)/ahb/ahb_smp_mem.sv $(SMP)/ahb/ahb_smp_top.sv
TB_ahb   := $(SMP)/ahb/tb_ahb_smp.sv
BAD_ahb  := a_wait_hold

IF_apb   := $(IF)/apb_if.sv
RTL_apb  := $(SMP)/apb/apb_smp_req.sv $(SMP)/apb/apb_smp_regs.sv $(SMP)/apb/apb_smp_top.sv
TB_apb   := $(SMP)/apb/tb_apb_smp.sv
BAD_apb  := a_access_hold

IF_p2p   := $(IF)/p2p_if.sv
RTL_p2p  := $(SMP)/p2p/p2p_smp_src.sv $(SMP)/p2p/p2p_smp_slice.sv $(SMP)/p2p/p2p_smp_sink.sv $(SMP)/p2p/p2p_smp_top.sv
TB_p2p   := $(SMP)/p2p/tb_p2p_smp.sv
BAD_p2p  := a_hold

IF_strm  := $(IF)/strm_if.sv
RTL_strm := $(SMP)/strm/strm_smp_src.sv $(SMP)/strm/strm_smp_rs.sv $(SMP)/strm/strm_smp_sink.sv $(SMP)/strm/strm_smp_top.sv
TB_strm  := $(SMP)/strm/tb_strm_smp.sv
BAD_strm := a_hold

# チェックの自己テストの違反の数 (SCN=1〜CHK_N_<P>)
CHK_N_axi4 := 31
CHK_N_axil := 12
CHK_N_ahb  := 18
CHK_N_apb  := 6
CHK_N_p2p  := 3
CHK_N_strm := 4

# --assert : SVA を有効にする / -Wno-fatal : TB の警告では止めない (警告の数は build_*.log で確認できる)
# -Werror-USERERROR / -Werror-USERFATAL : エラボレーション時の $error / $fatal (interface とモジュールの幅の違いなど) は止める
VFLAGS := --binary -j $(JOBS) --assert --timescale 1ns/1ps -Wno-fatal -Werror-USERERROR -Werror-USERFATAL

# PARAMS を指定したときは別のディレクトリに毎回ビルドする
ifeq ($(strip $(PARAMS)),)
  OBJ_SUFFIX :=
else
  OBJ_SUFFIX := _p
endif

.PHONY: all lint lint_one sim run bad run_bad chk chk_one role uvm files clean FORCE

all: lint sim bad chk role

#------------------------------------------------------------------------------
# lint
#------------------------------------------------------------------------------
lint:
	@for p in $(PROTOS); do \
	  $(MAKE) --no-print-directory lint_one P=$$p || exit 1; \
	done

lint_one:
	@$(VERILATOR) --lint-only -Wall --timescale 1ns/1ps +define+SYNTHESIS --top-module $(P)_smp_top $(IF_$(P)) $(RTL_$(P)) && echo "lint $(P) (SYNTHESIS) : clean"
	@$(VERILATOR) --lint-only -Wall -Wno-SYNCASYNCNET --timescale 1ns/1ps --top-module $(P)_smp_top $(IF_$(P)) $(RTL_$(P)) && echo "lint $(P) (simulation) : clean"

#------------------------------------------------------------------------------
# サンプルの TB
#------------------------------------------------------------------------------
obj_%/Vtb: $(IF)/*.sv $(SMP)/*/*.sv
	$(VERILATOR) $(VFLAGS) --top-module tb_$*_smp --Mdir obj_$* -o Vtb $(IF_$*) $(RTL_$*) $(TB_$*) > build_$*.log 2>&1 || (cat build_$*.log; exit 1)

obj_%_p/Vtb: FORCE
	$(VERILATOR) $(VFLAGS) $(PARAMS) --top-module tb_$*_smp --Mdir obj_$*_p -o Vtb $(IF_$*) $(RTL_$*) $(TB_$*) > build_$*_p.log 2>&1 || (cat build_$*_p.log; exit 1)

run: obj_$(P)$(OBJ_SUFFIX)/Vtb
	@./obj_$(P)$(OBJ_SUFFIX)/Vtb > sim_$(P).log 2>&1; r=$$?; grep -v "^- " sim_$(P).log; \
	  if [ $$r -eq 0 ] && grep -q "TB PASS" sim_$(P).log; then echo "[$(P)] PASS"; else echo "[$(P)] FAIL"; exit 1; fi

sim:
	@for p in $(PROTOS); do \
	  $(MAKE) --no-print-directory run P=$$p || exit 1; \
	done

# +BAD : TB がプロトコル違反を入れる。決めたアサーションで止まること
run_bad: obj_$(P)/Vtb
	@./obj_$(P)/Vtb +BAD > bad_$(P).log 2>&1; r=$$?; \
	  if [ $$r -ne 0 ] && grep -q "Assertion failed in .*\.$(BAD_$(P))" bad_$(P).log; then \
	    echo "[$(P)] +BAD : detected by $(BAD_$(P))"; \
	    grep -m1 "Assertion failed" bad_$(P).log; \
	  else \
	    echo "[$(P)] +BAD : NOT detected"; cat bad_$(P).log; exit 1; \
	  fi

bad:
	@for p in $(PROTOS); do \
	  $(MAKE) --no-print-directory run_bad P=$$p || exit 1; \
	done

#------------------------------------------------------------------------------
# チェックの自己テスト
#   SCN=0 はエラーが出ないこと、SCN=1〜 は TB が「EXPECT: 」で示したメッセージのエラーで止まること
#------------------------------------------------------------------------------
chkobj_%/Vtb: $(IF)/*.sv $(CHK)/*.sv
	$(VERILATOR) $(VFLAGS) --top-module tb_$*_chk --Mdir chkobj_$* -o Vtb $(IF_$*) $(CHK)/tb_$*_chk.sv > chkbuild_$*.log 2>&1 || (cat chkbuild_$*.log; exit 1)

chk_one: chkobj_$(P)/Vtb
	@./chkobj_$(P)/Vtb +SCN=0 > chk_$(P)_0.log 2>&1; r=$$?; \
	  if [ $$r -eq 0 ] && grep -q "CHK PASS" chk_$(P)_0.log; then echo "[$(P)] SCN=0 legal traffic : no error"; \
	  else echo "[$(P)] SCN=0 : FAIL"; grep -v "^- " chk_$(P)_0.log | head -5; exit 1; fi
	@ok=0; ng=0; \
	for n in $$(seq 1 $(CHK_N_$(P))); do \
	  ./chkobj_$(P)/Vtb +SCN=$$n > chk_$(P)_$$n.log 2>&1; r=$$?; \
	  e=$$(sed -n 's/^EXPECT: //p' chk_$(P)_$$n.log); \
	  if [ $$r -ne 0 ] && [ -n "$$e" ] && grep -F "%Error" chk_$(P)_$$n.log | grep -qF "$$e"; then \
	    ok=$$((ok+1)); \
	  else \
	    ng=$$((ng+1)); echo "[$(P)] SCN=$$n : NOT detected as expected ($$e)"; grep -v "^- " chk_$(P)_$$n.log | head -4; \
	  fi; \
	done; \
	echo "[$(P)] violations detected : $$ok / $(CHK_N_$(P))"; [ $$ng -eq 0 ]

chk:
	@for p in $(PROTOS); do \
	  $(MAKE) --no-print-directory chk_one P=$$p || exit 1; \
	done

#------------------------------------------------------------------------------
# TB_ROLE の確認の自己テスト
#   つながる側に書くと信号が変わり、つながらない側に書くと $warning が出る (エラーにはしない)
#------------------------------------------------------------------------------
ROLE_N := 12

roleobj/Vtb: $(IF)/*.sv $(CHK)/tb_role_chk.sv
	$(VERILATOR) $(VFLAGS) --top-module tb_role_chk --Mdir roleobj -o Vtb $(IF)/*.sv $(CHK)/tb_role_chk.sv > rolebuild.log 2>&1 || (cat rolebuild.log; exit 1)

role: roleobj/Vtb
	@./roleobj/Vtb > role.log 2>&1; r=$$?; \
	  n=$$(grep -c "%Warning.*_cb was written, but TB_ROLE=" role.log); \
	  if [ $$r -eq 0 ] && grep -q "ROLE PASS" role.log && [ $$n -eq $(ROLE_N) ] && ! grep -q "%Error" role.log; then \
	    echo "[role] TB_ROLE warnings for unconnected clocking blocks : $$n / $(ROLE_N)"; \
	    grep -m1 "%Warning" role.log; \
	  else \
	    echo "[role] FAIL (warnings $$n / $(ROLE_N))"; grep -v "^- " role.log; exit 1; \
	  fi

#------------------------------------------------------------------------------
# UVM で使う例 (make all には入れない)
#   UVM_HOME : UVM 1800.2-2020.3.2 のディレクトリ (src/uvm_pkg.sv があるところ)
#   --vpi    : UVM の DPI (src/dpi) が VPI を使う / --CFLAGS -O0 : UVM の大きな C++ のビルド時間を短くする
#------------------------------------------------------------------------------
UVM_HOME ?= $(HOME)/tools/uvm-2020.3.2
UVM_SRCS := $(UVM_HOME)/src/uvm_pkg.sv $(IF)/axil_if.sv $(SMP)/axil/axil_smp_regs.sv $(SMP)/uvm/tb_axil_uvm.sv \
            $(UVM_HOME)/src/dpi/uvm_dpi.cc

uvmobj/Vtb: $(IF)/axil_if.sv $(SMP)/axil/axil_smp_regs.sv $(SMP)/uvm/tb_axil_uvm.sv
	@test -f $(UVM_HOME)/src/uvm_pkg.sv || (echo "UVM_HOME=$(UVM_HOME) : src/uvm_pkg.sv not found"; exit 1)
	$(VERILATOR) --binary -j $(JOBS) --vpi --top-module tb_axil_uvm --timescale 1ns/1ps +incdir+$(UVM_HOME)/src \
	  -Wno-fatal -Wno-lint -Wno-style --CFLAGS -O0 --Mdir uvmobj -o Vtb $(UVM_SRCS) > uvmbuild.log 2>&1 || (cat uvmbuild.log; exit 1)

uvm: uvmobj/Vtb
	@./uvmobj/Vtb +UVM_NO_RELNOTES > uvm.log 2>&1; r=$$?; grep -E "^UVM_(INFO|WARNING|ERROR|FATAL) .*\[(WR|RD|TEST|NOVIF)\]" uvm.log; \
	  if [ $$r -eq 0 ] && grep -q "TEST PASSED" uvm.log; then echo "[uvm] PASS"; else echo "[uvm] FAIL"; exit 1; fi

#------------------------------------------------------------------------------
files:
	@echo $(IF_$(P)) $(RTL_$(P))

clean:
	rm -rf obj_* chkobj_* roleobj uvmobj *.log

FORCE:
