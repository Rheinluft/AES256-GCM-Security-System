class tx_gcm_driver extends uvm_driver #(tx_gcm_packet_item);
  `uvm_component_utils(tx_gcm_driver)

  virtual tx_gcm_if vif;
  bit stall_enable = 0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual tx_gcm_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "tx_gcm_if was not set")
    void'(uvm_config_db#(bit)::get(this, "", "stall_enable", stall_enable));
  endfunction

  task initialize_dut();
    byte unsigned key_bytes[KEY_BYTES];
    logic [255:0] packed_key;
    int fd;
    int count;

    vif.drv_cb.aresetn          <= 1'b0;
    vif.drv_cb.sw3_encrypt      <= 1'b1;
    vif.drv_cb.session_id       <= 32'h0000_0001;
    vif.drv_cb.session_key      <= '0;
    vif.drv_cb.session_key_valid <= 1'b0;
    vif.drv_cb.key_commit       <= 1'b0;
    vif.drv_cb.key_clear        <= 1'b0;
    vif.drv_cb.s_axis_tdata     <= '0;
    vif.drv_cb.s_axis_tkeep     <= '0;
    vif.drv_cb.s_axis_tvalid    <= 1'b0;
    vif.drv_cb.s_axis_tuser     <= 1'b0;
    vif.drv_cb.s_axis_tlast     <= 1'b0;
    vif.drv_cb.m_axis_tready    <= 1'b1;
    vif.drv_cb.m_meta_tready    <= 1'b1;

    repeat (10) @(vif.drv_cb);
    vif.drv_cb.aresetn <= 1'b1;
    repeat (3) @(vif.drv_cb);

    fd = $fopen("golden/key.bin", "rb");
    if (fd == 0)
      `uvm_fatal(get_type_name(), "Cannot open golden/key.bin")
    count = $fread(key_bytes, fd);
    $fclose(fd);
    if (count != KEY_BYTES)
      `uvm_fatal(get_type_name(), $sformatf("key.bin size=%0d", count))

    packed_key = '0;
    for (int i = 0; i < KEY_BYTES; i++)
      packed_key[255-(i*8)-:8] = key_bytes[i];

    vif.drv_cb.session_key       <= packed_key;
    vif.drv_cb.session_key_valid <= 1'b1;
    vif.drv_cb.key_commit        <= 1'b1;
    @(vif.drv_cb);
    vif.drv_cb.key_commit <= 1'b0;

    while (!vif.drv_cb.key_ready)
      @(vif.drv_cb);
    `uvm_info(get_type_name(), "AES-256 key setup completed", UVM_LOW)
  endtask

  task drive_output_ready();
    int unsigned cipher_stall_cycles = 0;
    int unsigned meta_stall_cycles = 0;
    bit cipher_ready;
    bit meta_ready;

    if (stall_enable)
      `uvm_info(get_type_name(),
                $sformatf("Random output stalls enabled (max %0d cycles)",
                          MAX_STALL_CYCLES), UVM_LOW)

    forever begin
      @(vif.drv_cb);
      if (!stall_enable) begin
        cipher_ready = 1'b1;
        meta_ready = 1'b1;
      end else begin
        cipher_ready = (cipher_stall_cycles >= MAX_STALL_CYCLES) ? 1'b1 :
                       ($urandom_range(0, 99) < READY_PERCENT);
        meta_ready = (meta_stall_cycles >= MAX_STALL_CYCLES) ? 1'b1 :
                     ($urandom_range(0, 99) < READY_PERCENT);
      end

      vif.drv_cb.m_axis_tready <= cipher_ready;
      vif.drv_cb.m_meta_tready <= meta_ready;
      cipher_stall_cycles = cipher_ready ? 0 : cipher_stall_cycles + 1;
      meta_stall_cycles = meta_ready ? 0 : meta_stall_cycles + 1;
    end
  endtask

  task drive_packet(tx_gcm_packet_item item);
    logic [127:0] word;

    for (int beat = 0; beat < PAYLOAD_BEATS; beat++) begin
      word = '0;
      for (int lane = 0; lane < AXIS_BYTES; lane++)
        word[(lane*8)+:8] = item.payload[(beat*AXIS_BYTES)+lane];

      vif.drv_cb.s_axis_tdata  <= word;
      vif.drv_cb.s_axis_tkeep  <= 16'hffff;
      vif.drv_cb.s_axis_tvalid <= 1'b1;
      vif.drv_cb.s_axis_tuser  <= (item.packet_index == 0 && beat == 0);
      vif.drv_cb.s_axis_tlast  <= (item.packet_index == PACKET_COUNT-1 &&
                                   beat == PAYLOAD_BEATS-1);
      do @(vif.drv_cb); while (!vif.drv_cb.s_axis_tready);
    end

    vif.drv_cb.s_axis_tdata  <= '0;
    vif.drv_cb.s_axis_tkeep  <= '0;
    vif.drv_cb.s_axis_tvalid <= 1'b0;
    vif.drv_cb.s_axis_tuser  <= 1'b0;
    vif.drv_cb.s_axis_tlast  <= 1'b0;
  endtask

  task run_phase(uvm_phase phase);
    tx_gcm_packet_item item;
    initialize_dut();
    fork
      drive_output_ready();
      forever begin
        seq_item_port.get_next_item(item);
        drive_packet(item);
        seq_item_port.item_done();
      end
    join
  endtask
endclass
