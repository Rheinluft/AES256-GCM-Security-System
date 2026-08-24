class tx_gcm_full_frame_sequence extends uvm_sequence #(tx_gcm_packet_item);
  `uvm_object_utils(tx_gcm_full_frame_sequence)

  function new(string name = "tx_gcm_full_frame_sequence");
    super.new(name);
  endfunction

  virtual task body();
    int fd;
    int count;
    string path = "golden/plaintext_1280.bin";

    fd = $fopen(path, "rb");
    if (fd == 0)
      `uvm_fatal(get_type_name(), $sformatf("Cannot open %s", path))

    for (int packet = 0; packet < PACKET_COUNT; packet++) begin
      tx_gcm_packet_item item;
      item = tx_gcm_packet_item::type_id::create($sformatf("packet_%0d", packet));
      item.packet_index = packet;
      count = $fread(item.payload, fd);
      if (count != PAYLOAD_BYTES)
        `uvm_fatal(get_type_name(),
                   $sformatf("Short plaintext read: packet=%0d bytes=%0d",
                             packet, count))
      start_item(item);
      finish_item(item);
    end
    $fclose(fd);
  endtask
endclass
