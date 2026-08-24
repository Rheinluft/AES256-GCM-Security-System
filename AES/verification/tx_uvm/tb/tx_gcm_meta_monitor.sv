class tx_gcm_meta_monitor extends uvm_monitor;
  `uvm_component_utils(tx_gcm_meta_monitor)

  virtual tx_gcm_if vif;
  uvm_analysis_port #(tx_gcm_meta_item) ap;
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
    byte unsigned aad[AAD_BYTES];
    int packet = 0;
    bit expect_tag = 0;
    longint unsigned cycle = 0;
    bit previous_stalled = 0;
    logic [127:0] previous_data;
    logic [15:0] previous_keep;
    logic previous_last;
    int unsigned consecutive_stall = 0;

    forever begin
      @(vif.mon_cb);
      cycle++;
      if (!vif.mon_cb.aresetn) begin
        packet = 0;
        expect_tag = 0;
        previous_stalled = 0;
        consecutive_stall = 0;
      end else begin
        if (previous_stalled &&
            ({vif.mon_cb.m_meta_tvalid, vif.mon_cb.m_meta_tdata,
              vif.mon_cb.m_meta_tkeep, vif.mon_cb.m_meta_tlast} !==
             {1'b1, previous_data, previous_keep, previous_last})) begin
          stability_errors++;
          `uvm_error("META_STABILITY",
                     $sformatf("Metadata changed while stalled: packet=%0d cycle=%0d",
                               packet, cycle))
        end

        previous_stalled = vif.mon_cb.m_meta_tvalid &&
                           !vif.mon_cb.m_meta_tready;
        if (previous_stalled) begin
          stall_cycles++;
          if (consecutive_stall == 0)
            stall_events++;
          consecutive_stall++;
          if (consecutive_stall > max_stall_cycles)
            max_stall_cycles = consecutive_stall;
          previous_data = vif.mon_cb.m_meta_tdata;
          previous_keep = vif.mon_cb.m_meta_tkeep;
          previous_last = vif.mon_cb.m_meta_tlast;
        end else begin
          consecutive_stall = 0;
        end

        if (vif.mon_cb.m_meta_tvalid && vif.mon_cb.m_meta_tready) begin
        if (vif.mon_cb.m_meta_tkeep !== 16'hffff)
          `uvm_error(get_type_name(), $sformatf("Bad metadata TKEEP packet=%0d", packet))

        if (!expect_tag) begin
          if (vif.mon_cb.m_meta_tlast !== 1'b0)
            `uvm_error(get_type_name(), $sformatf("AAD has TLAST packet=%0d", packet))
          for (int lane = 0; lane < AXIS_BYTES; lane++)
            aad[lane] = vif.mon_cb.m_meta_tdata[(lane*8)+:8];
          expect_tag = 1;
        end else begin
          tx_gcm_meta_item item;
          if (vif.mon_cb.m_meta_tlast !== 1'b1)
            `uvm_error(get_type_name(), $sformatf("TAG lacks TLAST packet=%0d", packet))
          item = tx_gcm_meta_item::type_id::create($sformatf("meta_%0d", packet));
          item.packet_index = packet;
          item.cycle = cycle;
          item.aad = aad;
          for (int lane = 0; lane < AXIS_BYTES; lane++)
            item.tag[lane] = vif.mon_cb.m_meta_tdata[(lane*8)+:8];
          ap.write(item);
          packet++;
          expect_tag = 0;
        end
        end
      end
    end
  endtask

endclass
