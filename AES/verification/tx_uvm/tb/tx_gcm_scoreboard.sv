class tx_gcm_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(tx_gcm_scoreboard)

  uvm_analysis_imp_cipher #(tx_gcm_cipher_item, tx_gcm_scoreboard) cipher_imp;
  uvm_analysis_imp_meta #(tx_gcm_meta_item, tx_gcm_scoreboard) meta_imp;

  byte unsigned golden_cipher[TOTAL_PAYLOAD_BYTES];
  byte unsigned golden_aad[TOTAL_AAD_BYTES];
  byte unsigned golden_tag[TOTAL_TAG_BYTES];
  byte unsigned rtl_cipher[TOTAL_PAYLOAD_BYTES];
  byte unsigned rtl_aad[TOTAL_AAD_BYTES];
  byte unsigned rtl_tag[TOTAL_TAG_BYTES];

  int unsigned cipher_packets;
  int unsigned meta_packets;
  int unsigned cipher_mismatches;
  int unsigned aad_mismatches;
  int unsigned tag_mismatches;
  int unsigned cipher_failed_packets;
  int unsigned aad_failed_packets;
  int unsigned tag_failed_packets;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cipher_imp = new("cipher_imp", this);
    meta_imp = new("meta_imp", this);
    load_golden_files();
  endfunction

  function void load_golden_files();
    int fd;
    int count;

    fd = $fopen("golden/ciphertext_1280.bin", "rb");
    if (fd == 0)
      `uvm_fatal(get_type_name(), "Cannot open golden/ciphertext_1280.bin")
    count = $fread(golden_cipher, fd);
    $fclose(fd);
    if (count != TOTAL_PAYLOAD_BYTES)
      `uvm_fatal(get_type_name(),
                 $sformatf("Invalid ciphertext size: expected=%0d actual=%0d",
                           TOTAL_PAYLOAD_BYTES, count))

    fd = $fopen("golden/aad_1280.bin", "rb");
    if (fd == 0)
      `uvm_fatal(get_type_name(), "Cannot open golden/aad_1280.bin")
    count = $fread(golden_aad, fd);
    $fclose(fd);
    if (count != TOTAL_AAD_BYTES)
      `uvm_fatal(get_type_name(),
                 $sformatf("Invalid AAD size: expected=%0d actual=%0d",
                           TOTAL_AAD_BYTES, count))

    fd = $fopen("golden/tag_1280.bin", "rb");
    if (fd == 0)
      `uvm_fatal(get_type_name(), "Cannot open golden/tag_1280.bin")
    count = $fread(golden_tag, fd);
    $fclose(fd);
    if (count != TOTAL_TAG_BYTES)
      `uvm_fatal(get_type_name(),
                 $sformatf("Invalid TAG size: expected=%0d actual=%0d",
                           TOTAL_TAG_BYTES, count))
  endfunction

  function void write_cipher(tx_gcm_cipher_item item);
    int base = item.packet_index * PAYLOAD_BYTES;
    bit packet_failed = 0;
    for (int i = 0; i < PAYLOAD_BYTES; i++) begin
      rtl_cipher[base+i] = item.data[i];
      if (item.data[i] !== golden_cipher[base+i]) begin
        packet_failed = 1;
        cipher_mismatches++;
        if (cipher_mismatches <= MAX_MISMATCH_LOGS)
          `uvm_error("CIPHER_MISMATCH",
                     $sformatf("packet=%0d byte=%0d golden=%02x rtl=%02x cycle=%0d",
                               item.packet_index, i, golden_cipher[base+i],
                               item.data[i], item.cycle))
      end
    end
    if (packet_failed)
      cipher_failed_packets++;
    cipher_packets++;
    if ((cipher_packets % 128) == 0)
      `uvm_info(get_type_name(), $sformatf("Ciphertext packets checked: %0d", cipher_packets), UVM_LOW)
  endfunction

  function void write_meta(tx_gcm_meta_item item);
    int base = item.packet_index * AAD_BYTES;
    bit aad_failed = 0;
    bit tag_failed = 0;
    for (int i = 0; i < AAD_BYTES; i++) begin
      rtl_aad[base+i] = item.aad[i];
      rtl_tag[base+i] = item.tag[i];
      if (item.aad[i] !== golden_aad[base+i]) begin
        aad_failed = 1;
        aad_mismatches++;
        if (aad_mismatches <= MAX_MISMATCH_LOGS)
          `uvm_error("AAD_MISMATCH",
                     $sformatf("packet=%0d byte=%0d golden=%02x rtl=%02x cycle=%0d",
                               item.packet_index, i, golden_aad[base+i],
                               item.aad[i], item.cycle))
      end
      if (item.tag[i] !== golden_tag[base+i]) begin
        tag_failed = 1;
        tag_mismatches++;
        if (tag_mismatches <= MAX_MISMATCH_LOGS)
          `uvm_error("TAG_MISMATCH",
                     $sformatf("packet=%0d byte=%0d golden=%02x rtl=%02x cycle=%0d",
                               item.packet_index, i, golden_tag[base+i],
                               item.tag[i], item.cycle))
      end
    end
    if (aad_failed)
      aad_failed_packets++;
    if (tag_failed)
      tag_failed_packets++;
    meta_packets++;
  endfunction

  function bit passed();
    return cipher_packets == PACKET_COUNT &&
           meta_packets == PACKET_COUNT &&
           cipher_mismatches == 0 && aad_mismatches == 0 &&
           tag_mismatches == 0;
  endfunction

  function void write_rx_handoff_files();
    int fd_aad;
    int fd_cipher;
    int fd_tag;
    int fd_records;
    int fd_result;
    int fd_readme;
    string test_name;
    int seed;

    if (!$value$plusargs("UVM_TESTNAME=%s", test_name))
      test_name = "unknown";
    if (!$value$plusargs("ntb_random_seed=%d", seed))
      seed = 0;

    fd_aad = $fopen("results/tx_rtl_aad_1280.bin", "wb");
    fd_cipher = $fopen("results/tx_rtl_ciphertext_1280.bin", "wb");
    fd_tag = $fopen("results/tx_rtl_tag_1280.bin", "wb");
    fd_records = $fopen("results/tx_rtl_records_1280.bin", "wb");
    fd_result = $fopen("results/tx_rtl_result.log", "w");
    fd_readme = $fopen("results/README.txt", "w");

    if (fd_aad == 0 || fd_cipher == 0 || fd_tag == 0 ||
        fd_records == 0 || fd_result == 0 || fd_readme == 0)
      `uvm_fatal("RESULT_FILE", "Cannot create one or more RX handoff files")

    for (int i = 0; i < TOTAL_AAD_BYTES; i++)
      $fwrite(fd_aad, "%c", rtl_aad[i]);
    for (int i = 0; i < TOTAL_PAYLOAD_BYTES; i++)
      $fwrite(fd_cipher, "%c", rtl_cipher[i]);
    for (int i = 0; i < TOTAL_TAG_BYTES; i++)
      $fwrite(fd_tag, "%c", rtl_tag[i]);

    for (int packet = 0; packet < PACKET_COUNT; packet++) begin
      for (int i = 0; i < AAD_BYTES; i++)
        $fwrite(fd_records, "%c", rtl_aad[(packet*AAD_BYTES)+i]);
      for (int i = 0; i < PAYLOAD_BYTES; i++)
        $fwrite(fd_records, "%c", rtl_cipher[(packet*PAYLOAD_BYTES)+i]);
      for (int i = 0; i < TAG_BYTES; i++)
        $fwrite(fd_records, "%c", rtl_tag[(packet*TAG_BYTES)+i]);
    end

    $fdisplay(fd_result, "TEST=%s", test_name);
    $fdisplay(fd_result, "SEED=%0d", seed);
    $fdisplay(fd_result, "PACKETS=%0d", PACKET_COUNT);
    $fdisplay(fd_result, "CIPHERTEXT_PACKETS=%0d", cipher_packets);
    $fdisplay(fd_result, "METADATA_PACKETS=%0d", meta_packets);
    $fdisplay(fd_result, "CIPHERTEXT_MISMATCHES=%0d", cipher_mismatches);
    $fdisplay(fd_result, "AAD_MISMATCHES=%0d", aad_mismatches);
    $fdisplay(fd_result, "TAG_MISMATCHES=%0d", tag_mismatches);
    $fdisplay(fd_result, "PROTOCOL_ERROR=0");
    $fdisplay(fd_result, "RESULT=PASS");

    $fdisplay(fd_readme, "AES-256-GCM verified TX RTL output for RX verification");
    $fdisplay(fd_readme, "Packet count       : 1280");
    $fdisplay(fd_readme, "AAD per packet     : 16 bytes");
    $fdisplay(fd_readme, "Ciphertext/packet  : 1440 bytes");
    $fdisplay(fd_readme, "TAG per packet     : 16 bytes");
    $fdisplay(fd_readme, "Record layout      : AAD[16] || Ciphertext[1440] || TAG[16]");
    $fdisplay(fd_readme, "Record size        : 1472 bytes");
    $fdisplay(fd_readme, "Byte ordering      : first stream byte first in file");
    $fdisplay(fd_readme, "Session ID         : 0x00000001");
    $fdisplay(fd_readme, "Initial frame ID   : 0x00000000");
    $fdisplay(fd_readme, "Packet index       : 0..1279");
    $fdisplay(fd_readme, "Nonce              : session_id || frame_id || 16'h0000 || packet_index");
    $fdisplay(fd_readme, "Expected plaintext : plaintext_1280.bin");
    $fdisplay(fd_readme, "AES key            : key.bin");
    $fdisplay(fd_readme, "Reference IV       : iv_1280.bin");

    $fclose(fd_aad);
    $fclose(fd_cipher);
    $fclose(fd_tag);
    $fclose(fd_records);
    $fclose(fd_result);
    $fclose(fd_readme);

    `uvm_info("RX_HANDOFF",
              "Created verified RX handoff files under results/", UVM_NONE)
  endfunction

  function void report_phase(uvm_phase phase);
    int unsigned total_checks;
    int unsigned failed_checks;
    int unsigned passed_checks;

    super.report_phase(phase);
    total_checks = cipher_packets + (2 * meta_packets);
    failed_checks = cipher_failed_packets + aad_failed_packets +
                    tag_failed_packets;
    passed_checks = total_checks - failed_checks;

    if (passed() &&
        uvm_report_server::get_server().get_severity_count(UVM_ERROR) == 0 &&
        uvm_report_server::get_server().get_severity_count(UVM_FATAL) == 0)
      write_rx_handoff_files();

    `uvm_info("TX_GCM_RESULT", "", UVM_LOW)
    `uvm_info("TX_GCM_RESULT", "===== TX GCM Scoreboard Summary =====", UVM_LOW)
    `uvm_info("TX_GCM_RESULT",
              $sformatf("  Total comparisons : %0d", total_checks), UVM_LOW)
    `uvm_info("TX_GCM_RESULT",
              $sformatf("  Pass              : %0d", passed_checks), UVM_LOW)
    `uvm_info("TX_GCM_RESULT",
              $sformatf("  Fail              : %0d", failed_checks), UVM_LOW)
    `uvm_info("TX_GCM_RESULT",
              $sformatf("  Ciphertext packets: %0d / %0d passed",
                        cipher_packets - cipher_failed_packets,
                        cipher_packets), UVM_LOW)
    `uvm_info("TX_GCM_RESULT",
              $sformatf("  AAD packets       : %0d / %0d passed",
                        meta_packets - aad_failed_packets,
                        meta_packets), UVM_LOW)
    `uvm_info("TX_GCM_RESULT",
              $sformatf("  TAG packets       : %0d / %0d passed",
                        meta_packets - tag_failed_packets,
                        meta_packets), UVM_LOW)
    `uvm_info("TX_GCM_RESULT",
              $sformatf({"  Byte mismatches   : Ciphertext=%0d, ",
                         "AAD=%0d, TAG=%0d"},
                        cipher_mismatches, aad_mismatches,
                        tag_mismatches), UVM_LOW)

    if (passed()) begin
      `uvm_info("TX_GCM_RESULT",
                $sformatf("  TEST PASSED: %0d comparisons matched!",
                          passed_checks), UVM_LOW)
    end else begin
      `uvm_error("TX_GCM_RESULT",
                 $sformatf("  TEST FAILED: %0d comparison groups failed!",
                           failed_checks))
    end
    `uvm_info("TX_GCM_RESULT", "=====================================", UVM_LOW)
  endfunction
endclass
