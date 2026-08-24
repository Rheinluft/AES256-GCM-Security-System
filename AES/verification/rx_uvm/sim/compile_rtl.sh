#!/bin/bash
# STEP 1 - RTL-only elaboration check (no UVM, no TB).
# Isolates missing-file / compile-order problems from the UVM environment.
set -e
cd "$(dirname "$0")"

rm -rf rtl_only.log csrc_rtl simv_rtl simv_rtl.daidir

vcs -full64 -sverilog -timescale=1ns/1ps \
    -f rtl.f \
    -top axis_gcm_rx_frame_processor \
    -Mdir=csrc_rtl -o simv_rtl \
    -l rtl_only.log

echo "=== STEP1 RTL elaboration PASSED ==="
