// ---------------------------------------------------------------------------
// Tests. Each declares the error signature it expects, so the scoreboard's
// third judgement (error code) is checked, not just plaintext.
// ---------------------------------------------------------------------------
class rx_base_test extends uvm_test;
  `uvm_component_utils(rx_base_test)

  rx_env        env;
  rx_vector_db  db;
  virtual rx_if vif;
  int unsigned num_packets = 8;
  int unsigned stall_pct   = 0;
  string       stim_path;
  string       gold_path;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!$value$plusargs("NPKT=%d", num_packets)) num_packets = 8;
    if (!$value$plusargs("STALL=%d", stall_pct))  stall_pct   = 0;
    if (!$value$plusargs("STIM=%s", stim_path))
      stim_path = $sformatf("../data/rx_normal_%0dpkt.bin", num_packets);
    if (!$value$plusargs("GOLD=%s", gold_path))
      gold_path = $sformatf("../data/rx_plain_%0dpkt.bin", num_packets);

    if (!uvm_config_db#(virtual rx_if)::get(this, "", "vif", vif))
      `uvm_fatal("TEST", "virtual interface not set")

    db = rx_vector_db::type_id::create("db");
    db.load(stim_path, gold_path, num_packets);

    uvm_config_db#(rx_vector_db)::set(null, "*", "db", db);
    uvm_config_db#(int unsigned)::set(null, "*", "num_packets", num_packets);
    uvm_config_db#(int unsigned)::set(null, "*", "stall_pct", stall_pct);

    env = rx_env::type_id::create("env", this);
  endfunction

  // Let the output pipeline drain, but stay under TIMEOUT_US (200us = 30000
  // clocks) so an idle-timeout is not injected accidentally.
  virtual task drain();
    repeat (4000) @(posedge vif.aclk);
  endtask

  virtual task run_seq();
    `uvm_fatal("TEST", "run_seq not implemented")
  endtask

  virtual function void declare_errors();
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    declare_errors();
    run_seq();
    drain();
    phase.drop_objection(this);
  endtask
endclass


// --- 1. 정상 -----------------------------------------------------------------
class rx_normal_test extends rx_base_test;
  `uvm_component_utils(rx_normal_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_seq();
    rx_normal_seq s = rx_normal_seq::type_id::create("s");
    s.start(env.agent.sqr);
  endtask
endclass


// --- 2. TAG 변조 -------------------------------------------------------------
class rx_tag_tamper_test extends rx_base_test;
  `uvm_component_utils(rx_tag_tamper_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void declare_errors();
    env.scb.expect_error(ERRB_TAG, 1);
  endfunction
  task run_seq();
    rx_tag_tamper_seq s = rx_tag_tamper_seq::type_id::create("s");
    s.start(env.agent.sqr);
  endtask
endclass


// --- 3. Ciphertext 변조 ------------------------------------------------------
class rx_cipher_tamper_test extends rx_base_test;
  `uvm_component_utils(rx_cipher_tamper_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void declare_errors();
    env.scb.expect_error(ERRB_TAG, 1);
  endfunction
  task run_seq();
    rx_cipher_tamper_seq s = rx_cipher_tamper_seq::type_id::create("s");
    s.start(env.agent.sqr);
  endtask
endclass


// --- 4. 변조 후 복구 ---------------------------------------------------------
class rx_recovery_test extends rx_base_test;
  `uvm_component_utils(rx_recovery_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void declare_errors();
    env.scb.expect_error(ERRB_TAG, 2);
  endfunction
  task run_seq();
    rx_recovery_seq s = rx_recovery_seq::type_id::create("s");
    s.start(env.agent.sqr);
  endtask
endclass


// --- 5. Replay ---------------------------------------------------------------
// A resent index is both "already seen" and "not the expected next index", so
// the detector raises REPLAY and SEQUENCE together (err_flags is a set, not a
// one-hot); err_code priority-encodes it as REPLAY.
class rx_replay_test extends rx_base_test;
  `uvm_component_utils(rx_replay_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void declare_errors();
    env.scb.expect_error(ERRB_REPLAY, 1);
    env.scb.expect_error(ERRB_SEQUENCE, 1);
  endfunction
  task run_seq();
    rx_replay_seq s = rx_replay_seq::type_id::create("s");
    s.start(env.agent.sqr);
  endtask
endclass

// --- 6. Sequence -------------------------------------------------------------
class rx_sequence_test extends rx_base_test;
  `uvm_component_utils(rx_sequence_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void declare_errors();
    env.scb.expect_error(ERRB_SEQUENCE, 1);
  endfunction
  task run_seq();
    rx_sequence_gap_seq s = rx_sequence_gap_seq::type_id::create("s");
    s.start(env.agent.sqr);
  endtask
endclass

// --- 7. Session --------------------------------------------------------------
// Needs enough packets for the victim to land past the re-key grace window.
class rx_session_test extends rx_base_test;
  `uvm_component_utils(rx_session_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void declare_errors();
    env.scb.expect_error(ERRB_SESSION, 1);
  endfunction
  task run_seq();
    rx_session_seq s = rx_session_seq::type_id::create("s");
    if (num_packets < 16)
      `uvm_fatal("TEST", "rx_session_test needs +NPKT=16 or more")
    s.start(env.agent.sqr);
  endtask
endclass

// --- 8. Timeout --------------------------------------------------------------
class rx_timeout_test extends rx_base_test;
  `uvm_component_utils(rx_timeout_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void declare_errors();
    env.scb.expect_error(ERRB_TIMEOUT, 1);
  endfunction
  // The idle window is longer than TIMEOUT_US by design.
  task drain();
    repeat (2000) @(posedge vif.aclk);
  endtask
  task run_seq();
    rx_timeout_seq s = rx_timeout_seq::type_id::create("s");
    s.start(env.agent.sqr);
  endtask
endclass
