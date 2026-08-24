// ---------------------------------------------------------------------------
// TX->RX loopback RTL file list (compile order matters: packages first)
//   pkg -> aes256_gcm submodules -> rx core top -> rx wrapper (DUT)
// ---------------------------------------------------------------------------
+incdir+../rtl/aes256_gcm

// packages
../rtl/aes256_gcm/aes_key_rcon_pkg.sv
../rtl/aes256_gcm/aes_sbox_pkg.sv
../rtl/aes256_gcm/gcm_protocol_pkg.sv

// AES-256 datapath
../rtl/aes256_gcm/aes_subword32.sv
../rtl/aes256_gcm/aes_subbytes.sv
../rtl/aes256_gcm/aes_shiftrows.sv
../rtl/aes256_gcm/aes_mixcolumns.sv
../rtl/aes256_gcm/aes_addroundkey.sv
../rtl/aes256_gcm/aes_round.sv
../rtl/aes256_gcm/aes_next_round_key.sv
../rtl/aes256_gcm/aes256_key_transform.sv
../rtl/aes256_gcm/aes256_key_expansion.sv
../rtl/aes256_gcm/aes256_iterative_core.sv

// GCM
../rtl/aes256_gcm/ghash_mul16.sv
../rtl/aes256_gcm/packet_buffer_bram.sv
../rtl/aes256_gcm/video_aes_gcm_rx_top.sv

// RX wrapper (DUT) + error detector
../rtl/rx/gcm_rx_error_detector.sv
../rtl/rx/axis_gcm_rx_frame_processor_v2.sv
