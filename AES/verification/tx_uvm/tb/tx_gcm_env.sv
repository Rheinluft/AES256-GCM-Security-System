class tx_gcm_env extends uvm_env;
  `uvm_component_utils(tx_gcm_env)

  tx_gcm_input_agent input_agent;
  tx_gcm_cipher_monitor cipher_monitor;
  tx_gcm_meta_monitor meta_monitor;
  tx_gcm_scoreboard scoreboard;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    input_agent = tx_gcm_input_agent::type_id::create("input_agent", this);
    cipher_monitor = tx_gcm_cipher_monitor::type_id::create("cipher_monitor", this);
    meta_monitor = tx_gcm_meta_monitor::type_id::create("meta_monitor", this);
    scoreboard = tx_gcm_scoreboard::type_id::create("scoreboard", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    cipher_monitor.ap.connect(scoreboard.cipher_imp);
    meta_monitor.ap.connect(scoreboard.meta_imp);
  endfunction
endclass
