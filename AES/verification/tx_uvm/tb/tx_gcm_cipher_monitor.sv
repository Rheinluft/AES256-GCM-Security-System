class tx_gcm_cipher_monitor extends uvm_monitor;
  `uvm_component_utils(tx_gcm_cipher_monitor)

  virtual tx_gcm_if vif;
  uvm_analysis_port #(tx_gcm_cipher_item) ap;
  int unsigned stability_errors;
  int unsigned stall_events;
  int unsigned stall_cycles;
  int unsigned max_stall_cycles;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual tx_gcm_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "tx_gcm_if was not set")
  endfunction

  task run_phase(uvm_phase phase);
    byte unsigned packet_data[PAYLOAD_BYTES];
    int packet = 0;
    int beat = 0;
    longint unsigned cycle = 0;
    bit previous_stalled = 0;
    logic [127:0] previous_data;
    logic [15:0] previous_keep;
    logic previous_user;
    logic previous_last;
    int unsigned consecutive_stall = 0;

    forever begin
      @(vif.mon_cb);
      cycle++;
      if (!vif.mon_cb.aresetn) begin
        packet = 0;
        beat = 0;
        previous_stalled = 0;
        consecutive_stall = 0;
      end else begin
        if (previous_stalled &&
            ({vif.mon_cb.m_axis_tvalid, vif.mon_cb.m_axis_tdata,
              vif.mon_cb.m_axis_tkeep, vif.mon_cb.m_axis_tuser,
              vif.mon_cb.m_axis_tlast} !==
             {1'b1, previous_data, previous_keep,
              previous_user, previous_last})) begin
          stability_errors++;
          `uvm_error("CIPHER_STABILITY",
                     $sformatf("Output changed while stalled: packet=%0d beat=%0d cycle=%0d",
                               packet, beat, cycle))
        end

        previous_stalled = vif.mon_cb.m_axis_tvalid &&
                           !vif.mon_cb.m_axis_tready;
        if (previous_stalled) begin
          stall_cycles++;
          if (consecutive_stall == 0)
            stall_events++;
          consecutive_stall++;
          if (consecutive_stall > max_stall_cycles)
            max_stall_cycles = consecutive_stall;
          previous_data = vif.mon_cb.m_axis_tdata;
          previous_keep = vif.mon_cb.m_axis_tkeep;
          previous_user = vif.mon_cb.m_axis_tuser;
          previous_last = vif.mon_cb.m_axis_tlast;
        end else begin
          consecutive_stall = 0;
        end

        if (vif.mon_cb.m_axis_tvalid && vif.mon_cb.m_axis_tready) begin
        if (vif.mon_cb.m_axis_tkeep !== 16'hffff)
          `uvm_error(get_type_name(), $sformatf("Bad output TKEEP packet=%0d beat=%0d", packet, beat))
        if (vif.mon_cb.m_axis_tuser !== (packet == 0 && beat == 0))
          `uvm_error(get_type_name(), $sformatf("Bad output TUSER packet=%0d beat=%0d", packet, beat))
        if (vif.mon_cb.m_axis_tlast !== (packet == PACKET_COUNT-1 && beat == PAYLOAD_BEATS-1))
          `uvm_error(get_type_name(), $sformatf("Bad output TLAST packet=%0d beat=%0d", packet, beat))

        for (int lane = 0; lane < AXIS_BYTES; lane++)
          packet_data[(beat*AXIS_BYTES)+lane] =
              vif.mon_cb.m_axis_tdata[(lane*8)+:8];

        if (beat == PAYLOAD_BEATS-1) begin
          tx_gcm_cipher_item item;
          item = tx_gcm_cipher_item::type_id::create($sformatf("cipher_%0d", packet));
          item.packet_index = packet;
          item.cycle = cycle;
          item.data = packet_data;
          ap.write(item);
          packet++;
          beat = 0;
        end else begin
          beat++;
        end
        end
      end
    end
  endtask

endclass
