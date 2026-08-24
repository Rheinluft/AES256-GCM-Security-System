#!/bin/bash
# TX->RX loopback UVM simulation (single test).
#   ./run_uvm.sh <test_name> [npkt] [stall_pct]
# Stimulus comes from tx_uvm/vectors (verified TX RTL output).
set -e
cd "$(dirname "$0")"

TEST=${1:-rx_normal_test}
PKT=${2:-8}
STALL=${3:-0}

if [ ! -f ../data/tx_records_${PKT}pkt.bin ]; then
  echo "generating ${PKT}-packet TX stimulus..."
  python3 ../tb/pack_tx_vectors.py ${PKT}
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
    +STIM=../data/tx_records_${PKT}pkt.bin \
    +GOLD=../data/tx_plain_${PKT}pkt.bin \
    +UVM_VERBOSITY=UVM_LOW \
    -l uvm_${TEST}_${PKT}.log
