// ---------------------------------------------------------------------------
// Drives 92-beat records onto s_axis, and owns the reset / key-commit
// sequence described in doc section 7.
// ---------------------------------------------------------------------------
class rx_driver extends uvm_driver #(rx_record_item);
  `uvm_component_utils(rx_driver)

  virtual rx_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual rx_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "virtual interface not set")
  endfunction

  task run_phase(uvm_phase phase);
    rx_record_item item;
    idle_bus();
    reset_and_commit_key();
    forever begin
      seq_item_port.get_next_item(item);
      if (item.kind == TK_TIMEOUT)
        idle_for(item.idle_clocks);
      else
        send_record(item);
      seq_item_port.item_done();
    end
  endtask

  task idle_bus();
    vif.s_axis_tdata  <= '0;
    vif.s_axis_tkeep  <= 16'hffff;
    vif.s_axis_tvalid <= 1'b0;
    vif.s_axis_tlast  <= 1'b0;
  endtask

  // Reset release -> session_key_valid -> key_commit pulse -> key_ready.
  // Doc section 7: key_ready takes roughly 45 clocks (key expansion + H).
  task reset_and_commit_key();
    vif.sw3_decrypt       <= 1'b1;
    vif.session_id        <= GOLDEN_SESSION_ID;
    vif.session_key       <= GOLDEN_KEY;
    vif.session_key_valid <= 1'b0;
    vif.key_commit        <= 1'b0;
    vif.key_clear         <= 1'b0;
    vif.key_epoch         <= 16'd1;
    vif.error_control     <= 32'd0;      // enable == 0 -> all five detectors on
    vif.m_axis_tready     <= 1'b1;

    wait (vif.aresetn === 1'b1);
    repeat (5) @(posedge vif.aclk);

    vif.session_key_valid <= 1'b1;
    @(posedge vif.aclk);
    vif.key_commit <= 1'b1;
    @(posedge vif.aclk);
    vif.key_commit <= 1'b0;

    fork
      begin
        repeat (2000) @(posedge vif.aclk);
        `uvm_fatal("DRV", "key_ready never asserted")
      end
      wait (vif.key_ready === 1'b1);
    join_any
    disable fork;
    `uvm_info("DRV", $sformatf("key_ready at %0t", $time), UVM_LOW)
  endtask

  task idle_for(int unsigned clocks);
    idle_bus();
    `uvm_info("DRV", $sformatf("idling %0d clocks (timeout stimulus)", clocks),
              UVM_LOW)
    repeat (clocks) @(posedge vif.aclk);
  endtask

  task send_record(rx_record_item item);
    for (int w = 0; w < RECORD_WORDS; w++) begin
      if (item.stall_pct != 0 && ($urandom_range(99) < item.stall_pct)) begin
        idle_bus();
        @(posedge vif.aclk);
      end
      drive_beat(item, w);
    end
    idle_bus();
  endtask

  task drive_beat(rx_record_item item, int w);
    int unsigned base = w * 16;
    // File byte 0 goes to TDATA[7:0] (handoff README section 5).
    for (int lane = 0; lane < 16; lane++)
      vif.s_axis_tdata[lane*8 +: 8] <= item.data[base + lane];
    vif.s_axis_tkeep  <= 16'hffff;
    vif.s_axis_tvalid <= 1'b1;
    vif.s_axis_tlast  <= item.last_of_frame && (w == RECORD_WORDS - 1);
    @(posedge vif.aclk);
    while (vif.s_axis_tready !== 1'b1) @(posedge vif.aclk);
    vif.s_axis_tvalid <= 1'b0;
    vif.s_axis_tlast  <= 1'b0;
  endtask

endclass
