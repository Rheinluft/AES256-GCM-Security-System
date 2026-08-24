class tx_gcm_full_frame_test extends uvm_test;
  `uvm_component_utils(tx_gcm_full_frame_test)

  tx_gcm_env env;
  virtual tx_gcm_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = tx_gcm_env::type_id::create("env", this);
    if (!uvm_config_db#(virtual tx_gcm_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "tx_gcm_if was not set")
  endfunction

  task run_phase(uvm_phase phase);
    tx_gcm_full_frame_sequence seq;
    bit completed = 0;

    phase.raise_objection(this);
    seq = tx_gcm_full_frame_sequence::type_id::create("seq");

    fork
      begin
        seq.start(env.input_agent.sequencer);
        wait (env.scoreboard.cipher_packets == PACKET_COUNT &&
              env.scoreboard.meta_packets == PACKET_COUNT);
        while (vif.mon_cb.busy)
          @(vif.mon_cb);
        repeat (5) @(vif.mon_cb);
        completed = 1;
      end
      begin
        repeat (FULL_FRAME_TIMEOUT_CYCLES) @(vif.mon_cb);
      end
    join_any
    disable fork;

    if (!completed)
      `uvm_fatal("TIMEOUT", $sformatf("Full-frame timeout after %0d cycles",
                                      FULL_FRAME_TIMEOUT_CYCLES))
    if (vif.mon_cb.protocol_error)
      `uvm_fatal("PROTOCOL_ERROR", "DUT protocol_error asserted")
    if (vif.mon_cb.status_frame_id !== 32'd1 ||
        vif.mon_cb.status_packet_index !== 16'd0)
      `uvm_fatal("FINAL_STATUS",
                 $sformatf("frame_id=%0d packet_index=%0d",
                           vif.mon_cb.status_frame_id,
                           vif.mon_cb.status_packet_index))
    if (!env.scoreboard.passed())
      `uvm_fatal("SCOREBOARD", "Golden comparison failed")
    if (env.cipher_monitor.stability_errors != 0 ||
        env.meta_monitor.stability_errors != 0)
      `uvm_fatal("STALL_STABILITY",
                 $sformatf("cipher_errors=%0d meta_errors=%0d",
                           env.cipher_monitor.stability_errors,
                           env.meta_monitor.stability_errors))
    if (get_type_name() == "tx_gcm_stall_test" &&
        (env.cipher_monitor.stall_cycles == 0 ||
         env.meta_monitor.stall_cycles == 0))
      `uvm_fatal("STALL_NOT_EXERCISED",
                 $sformatf("cipher_stall_cycles=%0d meta_stall_cycles=%0d",
                           env.cipher_monitor.stall_cycles,
                           env.meta_monitor.stall_cycles))

    `uvm_info("TX_GCM_TEST",
              $sformatf("%s PASS", get_type_name()), UVM_NONE)
    phase.drop_objection(this);
  endtask
endclass

class tx_gcm_stall_test extends tx_gcm_full_frame_test;
  `uvm_component_utils(tx_gcm_stall_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    uvm_config_db#(bit)::set(this, "env.input_agent.driver",
                            "stall_enable", 1'b1);
    super.build_phase(phase);
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    $display("");
    $display("===== TX GCM Stall Summary =====");
    $display("  Ciphertext output");
    $display("    Stall events        : %0d", env.cipher_monitor.stall_events);
    $display("    Stalled cycles      : %0d", env.cipher_monitor.stall_cycles);
    $display("    Max consecutive     : %0d", env.cipher_monitor.max_stall_cycles);
    $display("    Stability errors    : %0d", env.cipher_monitor.stability_errors);
    $display("  Metadata output");
    $display("    Stall events        : %0d", env.meta_monitor.stall_events);
    $display("    Stalled cycles      : %0d", env.meta_monitor.stall_cycles);
    $display("    Max consecutive     : %0d", env.meta_monitor.max_stall_cycles);
    $display("    Stability errors    : %0d", env.meta_monitor.stability_errors);
    $display("  STALL TEST PASSED");
    $display("================================");
  endfunction
endclass
