// ---------------------------------------------------------------------------
// One 1472-byte RX record as it will actually appear on s_axis, plus the
// tamper annotation that produced it.
// ---------------------------------------------------------------------------
class rx_record_item extends uvm_sequence_item;

  int unsigned  packet_index;      // index carried in the AAD
  byte unsigned data[];            // RECORD_BYTES, post-tamper
  tamper_e      kind = TK_NONE;
  bit           last_of_frame;     // drives TLAST on beat 91
  int unsigned  stall_pct = 0;     // AXI backpressure knob for the driver
  int unsigned  idle_clocks = 0;   // TK_TIMEOUT only: idle instead of driving

  `uvm_object_utils_begin(rx_record_item)
    `uvm_field_int(packet_index, UVM_ALL_ON | UVM_DEC)
    `uvm_field_enum(tamper_e, kind, UVM_ALL_ON)
    `uvm_field_int(last_of_frame, UVM_ALL_ON)
    `uvm_field_int(stall_pct, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(idle_clocks, UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "rx_record_item");
    super.new(name);
    data = new[RECORD_BYTES];
  endfunction

  // Flip one bit inside the TAG field.
  function void flip_tag_bit(int unsigned bit_pos = 0);
    int unsigned byte_i = rx_vector_db::tag_offset() + (bit_pos / 8);
    data[byte_i] ^= (8'd1 << (bit_pos % 8));
    kind = TK_TAG_FLIP;
  endfunction

  // Flip one bit inside the ciphertext field.
  function void flip_cipher_bit(int unsigned bit_pos = 0);
    int unsigned byte_i = rx_vector_db::payload_offset() + (bit_pos / 8);
    data[byte_i] ^= (8'd1 << (bit_pos % 8));
    kind = TK_CIPHER_FLIP;
  endfunction

  // AAD is big endian: byte 0 is the MSB of MAGIC.
  function void set_aad_session(logic [31:0] sid);
    data[4] = sid[31:24];
    data[5] = sid[23:16];
    data[6] = sid[15:8];
    data[7] = sid[7:0];
  endfunction

  function logic [31:0] aad_session();
    return {data[4], data[5], data[6], data[7]};
  endfunction

  function logic [15:0] aad_index();
    return {data[12], data[13]};
  endfunction

  function logic [15:0] aad_flags();
    return {data[14], data[15]};
  endfunction

endclass
