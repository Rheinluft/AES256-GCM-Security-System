#!/bin/bash
# STEP 2 - directed smoke simulation (no UVM).
#   ./run_smoke.sh [packet_count]      default 8
set -e
cd "$(dirname "$0")"

PKT=${1:-8}

rm -rf csrc_smoke simv_smoke simv_smoke.daidir smoke_${PKT}.log

vcs -full64 -sverilog -timescale=1ns/1ps \
    -f rtl.f \
    ../tb/tb_rx_smoke.sv \
    -top tb_rx_smoke \
    -pvalue+tb_rx_smoke.PKT_COUNT=${PKT} \
    -Mdir=csrc_smoke -o simv_smoke \
    -l compile_smoke_${PKT}.log

./simv_smoke \
    +STIM=../data/rx_normal_${PKT}pkt.bin \
    +GOLD=../data/rx_plain_${PKT}pkt.bin \
    -l smoke_${PKT}.log
