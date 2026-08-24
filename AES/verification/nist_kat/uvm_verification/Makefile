# === AES-256 ECB KAT Testbench Makefile (NIST AESAVS / Synopsys VCS) ===
#
#   make sim                full 405-vector verification
#   make sim WAVE=1         run first MAXV vectors and dump FSDB
#   make sim WAVE=1 MAXV=20
#   make sim COV=1          collect code coverage
#   make verdi              open FSDB in Verdi
#   make cov                open coverage report in Verdi
#   make clean
#
# 이 TB 는 UVM 을 쓰지 않는다 (평범한 SV testbench).  UVM env 가 들어오면
# VCS_OPTS 의 -ntb_opts uvm-1.2 주석을 풀면 된다.

VEC  ?= ./kat_vectors
MAXV ?= 0
# MAXV = 0 이면 405 벡터 전체.  파형을 켜도 크기는 5 MB 대라 제한할 이유가
# 거의 없다.  짧게 끊어 보고 싶을 때만 MAXV=5 처럼 지정한다.

VCS_OPTS := -full64 -sverilog
VCS_OPTS += -timescale=1ns/1ps
VCS_OPTS += -debug_access+all -kdb -lca
VCS_OPTS += +incdir+./tb
#VCS_OPTS += -ntb_opts uvm-1.2

SIM_OPTS := +VECDIR=$(VEC)

ifeq ($(WAVE),1)
  VCS_OPTS += +define+KAT_DUMP_FSDB +define+KAT_MAX_VECTORS=$(MAXV)
endif

ifeq ($(COV),1)
  VCS_OPTS += -cm line+cond+fsm+tgl+branch
  SIM_OPTS += -cm line+cond+fsm+tgl+branch
  SIM_OPTS += -cm_dir coverage.vdb -cm_name aes256_kat
endif

VERDI_OPTS := -dbdir simv.daidir -ssf aes_core_kat.fsdb

CUR_TIME := $(shell date +%Y%m%d_%H%M%S)
LOG      := logs/aes256_kat_$(CUR_TIME).log

.PHONY: compile sim gui verdi cov clean help

compile:
	vcs $(VCS_OPTS) -f filelist.f -o simv

# VCS 는 $$fatal 로 끝나도 종료 코드 0 을 낼 수 있다 (xsim 이 2020.2/2025.2
# 양쪽에서 그랬다).  종료 코드만 믿으면 벡터 불일치를 놓치므로 로그의 최종
# 판정문을 확인한다.
sim: compile
	@mkdir -p logs
	./simv $(SIM_OPTS) -l $(LOG)
	@grep -q "RESULT     : PASS" $(LOG) \
	    || { echo "*** AES-256 KAT FAILED - see $(LOG)"; exit 1; }
ifeq ($(MAXV),0)
	@echo "AES-256 KAT PASS - all 405 vectors ($(LOG))"
else
	@echo "AES-256 KAT PASS - LIMITED to $(MAXV) vectors/file (NOT full verification)"
endif

# 인터랙티브: Verdi 가 시뮬을 구동한다.  Verdi 프롬프트에서 run 을 치면 되고,
# 파형이 실시간으로 채워진다.  이 모드에서는 Verdi 가 FSDB 이름을 직접 정하므로
# TB 의 $$fsdbDumpfile 이름은 무시된다 (inter.fsdb 로 간다) - 정상이다.
gui: compile
	@mkdir -p logs
	./simv $(SIM_OPTS) -gui=verdi

# 후처리: 시뮬을 먼저 끝내고 남은 FSDB 를 연다.
verdi:
	@test -f aes_core_kat.fsdb \
	    || { echo "No FSDB.  Run: make sim WAVE=1"; exit 1; }
	verdi $(VERDI_OPTS) &

cov:
	@test -d coverage.vdb \
	    || { echo "No coverage data.  Run: make sim COV=1"; exit 1; }
	verdi -cov -covdir coverage.vdb &

clean:
	rm -rf simv* csrc *.log *.vpd *.fsdb *.key *.h DVE* novas* *.conf *.vdb *Log
	rm -rf logs .inter.vpd.uvm ucli.key AN.DB

help:
	@echo "make sim                full 405-vector verification"
	@echo "make sim WAVE=1         $(MAXV) vectors + FSDB"
	@echo "make sim WAVE=1 MAXV=20"
	@echo "make sim COV=1          collect coverage"
	@echo "make gui                run under Verdi (interactive)"
	@echo "make verdi / make cov / make clean"
	@echo ""
	@echo "VEC  = $(VEC)"
	@echo "LOG  = $(LOG)"
