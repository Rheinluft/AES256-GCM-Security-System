#!/bin/bash
# STEP 3/4 - UVM simulation.
#   ./run_uvm.sh <test_name> [npkt] [stall_pct]
# e.g.
#   ./run_uvm.sh rx_normal_test 8
#   ./run_uvm.sh rx_recovery_test 8
#   ./run_uvm.sh rx_normal_test 1280 20
set -e
cd "$(dirname "$0")"

TEST=${1:-rx_normal_test}
PKT=${2:-8}
STALL=${3:-0}

if [ ! -f ../data/rx_normal_${PKT}pkt.bin ]; then
  echo "generating ${PKT}-packet vectors..."
  python3 ../tb/pack_rx_vectors.py ${PKT}
fi

if [ ! -x simv_uvm ] || [ -n "$REBUILD" ]; then
  rm -rf csrc_uvm simv_uvm simv_uvm.daidir
  vcs -full64 -sverilog -timescale=1ns/1ps \
      -ntb_opts uvm-1.2 \
      +incdir+../tb/uvm \
      -f rtl.f \
      ../tb/uvm/rx_if.sv \
      ../tb/uvm/rx_uvm_pkg.sv \
      ../tb/uvm/rx_tb_top.sv \
      -top rx_tb_top \
      -Mdir=csrc_uvm -o simv_uvm \
      -l compile_uvm.log
fi

./simv_uvm +UVM_TESTNAME=${TEST} +NPKT=${PKT} +STALL=${STALL} \
    +UVM_VERBOSITY=UVM_LOW \
    -l uvm_${TEST}_${PKT}.log
