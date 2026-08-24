class tx_gcm_input_agent extends uvm_agent;
  `uvm_component_utils(tx_gcm_input_agent)

  uvm_sequencer #(tx_gcm_packet_item) sequencer;
  tx_gcm_driver driver;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sequencer = uvm_sequencer#(tx_gcm_packet_item)::type_id::create("sequencer", this);
    driver = tx_gcm_driver::type_id::create("driver", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass
