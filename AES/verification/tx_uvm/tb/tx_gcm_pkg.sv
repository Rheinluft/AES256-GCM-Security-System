package tx_gcm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam int KEY_BYTES = 32;
  localparam int AAD_BYTES = 16;
  localparam int TAG_BYTES = 16;
  localparam int AXIS_BYTES = 16;
  localparam int PAYLOAD_BYTES = 1440;
  localparam int PAYLOAD_BEATS = 90;
  localparam int PACKET_COUNT = 1280;
  localparam int TOTAL_PAYLOAD_BYTES = PAYLOAD_BYTES * PACKET_COUNT;
  localparam int TOTAL_AAD_BYTES = AAD_BYTES * PACKET_COUNT;
  localparam int TOTAL_TAG_BYTES = TAG_BYTES * PACKET_COUNT;
  localparam int MAX_MISMATCH_LOGS = 20;
  localparam int FULL_FRAME_TIMEOUT_CYCLES = 3_000_000;
  localparam int READY_PERCENT = 70;
  localparam int MAX_STALL_CYCLES = 20;

  `uvm_analysis_imp_decl(_cipher)
  `uvm_analysis_imp_decl(_meta)

  `include "tx_gcm_item.sv"
  `include "tx_gcm_sequence.sv"
  `include "tx_gcm_driver.sv"
  `include "tx_gcm_cipher_monitor.sv"
  `include "tx_gcm_meta_monitor.sv"
  `include "tx_gcm_agent.sv"
  `include "tx_gcm_scoreboard.sv"
  `include "tx_gcm_env.sv"
  `include "tx_gcm_test.sv"
endpackage
