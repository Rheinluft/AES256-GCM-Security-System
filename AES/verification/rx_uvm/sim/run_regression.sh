#!/bin/bash
# STEP 4 - full UVM regression: sequences 1..8 + backpressure + full frame.
# Collects code + functional coverage and merges it with urg.
#
#   ./run_regression.sh            sequences 1..8 + backpressure
#   FULL=1 ./run_regression.sh     also runs the 1280-packet frame
cd "$(dirname "$0")"

RESULTS=regression_results.txt
: > $RESULTS

rm -rf csrc_uvm simv_uvm simv_uvm.daidir cov_rx.vdb urg_report
vcs -full64 -sverilog -timescale=1ns/1ps \
    -ntb_opts uvm-1.2 \
    -cm line+cond+fsm+tgl+branch -cm_name rx -cm_dir ./cov_rx.vdb \
    +incdir+../tb/uvm \
    -f rtl.f \
    ../tb/uvm/rx_if.sv \
    ../tb/uvm/rx_uvm_pkg.sv \
    ../tb/uvm/rx_tb_top.sv \
    -top rx_tb_top \
    -Mdir=csrc_uvm -o simv_uvm \
    -l compile_uvm.log || { echo "COMPILE FAILED"; exit 1; }

# name : test : packets : stall%
RUNS=(
  "1_normal:rx_normal_test:8:0"
  "2_tag_tamper:rx_tag_tamper_test:8:0"
  "3_cipher_tamper:rx_cipher_tamper_test:8:0"
  "4_recovery:rx_recovery_test:8:0"
  "5_replay:rx_replay_test:8:0"
  "6_sequence:rx_sequence_test:8:0"
  "7_session:rx_session_test:16:0"
  "8_timeout:rx_timeout_test:8:0"
  "9_backpressure:rx_normal_test:8:25"
)
if [ -n "$FULL" ]; then
  RUNS+=("10_full_frame:rx_normal_test:1280:0")
fi

overall=0
for entry in "${RUNS[@]}"; do
  IFS=':' read -r name test pkt stall <<< "$entry"

  [ -f ../data/rx_normal_${pkt}pkt.bin ] || python3 ../tb/pack_rx_vectors.py ${pkt} > /dev/null

  ./simv_uvm +UVM_TESTNAME=${test} +NPKT=${pkt} +STALL=${stall} \
      +UVM_VERBOSITY=UVM_LOW \
      -cm line+cond+fsm+tgl+branch -cm_name ${name} -cm_dir ./cov_rx.vdb \
      -l uvm_${name}.log > /dev/null 2>&1

  errs=$(grep -c "^UVM_ERROR" uvm_${name}.log)
  ue=$(grep "UVM_ERROR :" uvm_${name}.log | tail -1 | awk '{print $NF}')
  uf=$(grep "UVM_FATAL :" uvm_${name}.log | tail -1 | awk '{print $NF}')
  chk=$(grep "packets checked" uvm_${name}.log | tail -1 | awk '{print $NF}')
  mat=$(grep "plaintext match" uvm_${name}.log | tail -1 | awk '{print $NF}')
  zer=$(grep "zero-substituted" uvm_${name}.log | tail -1 | awk '{print $NF}')
  evt=$(grep "error events" uvm_${name}.log | tail -1 | awk '{print $NF}')

  if [ "$ue" == "0" ] && [ "$uf" == "0" ]; then verdict=PASS; else verdict=FAIL; overall=1; fi

  printf "%-16s %-24s npkt=%-5s stall=%-3s checked=%-5s plain=%-5s zero=%-3s err=%-3s %s\n" \
      "$name" "$test" "$pkt" "$stall" "$chk" "$mat" "$zer" "$evt" "$verdict" | tee -a $RESULTS
done

echo "" | tee -a $RESULTS
if [ $overall -eq 0 ]; then
  echo "=== REGRESSION PASS (all scenarios) ===" | tee -a $RESULTS
else
  echo "=== REGRESSION FAIL ===" | tee -a $RESULTS
fi

urg -dir cov_rx.vdb -format text -report urg_report > /dev/null 2>&1 && \
  echo "coverage report: sim/urg_report/dashboard.txt" | tee -a $RESULTS

exit $overall
