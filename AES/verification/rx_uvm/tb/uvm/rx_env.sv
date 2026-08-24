class rx_sequencer extends uvm_sequencer #(rx_record_item);
  `uvm_component_utils(rx_sequencer)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass


class rx_agent extends uvm_agent;
  `uvm_component_utils(rx_agent)

  rx_sequencer   sqr;
  rx_driver      drv;
  rx_in_monitor  in_mon;
  rx_out_monitor out_mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sqr     = rx_sequencer::type_id::create("sqr", this);
    drv     = rx_driver::type_id::create("drv", this);
    in_mon  = rx_in_monitor::type_id::create("in_mon", this);
    out_mon = rx_out_monitor::type_id::create("out_mon", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass


class rx_env extends uvm_env;
  `uvm_component_utils(rx_env)

  rx_agent      agent;
  rx_scoreboard scb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = rx_agent::type_id::create("agent", this);
    scb   = rx_scoreboard::type_id::create("scb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    agent.in_mon.ap.connect(scb.exp_imp);
    agent.out_mon.ap.connect(scb.out_imp);
    agent.out_mon.err_ap.connect(scb.err_imp);
  endfunction
endclass
