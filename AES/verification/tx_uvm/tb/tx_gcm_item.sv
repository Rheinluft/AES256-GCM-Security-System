class tx_gcm_packet_item extends uvm_sequence_item;
  int unsigned packet_index;
  byte unsigned payload[PAYLOAD_BYTES];

  `uvm_object_utils(tx_gcm_packet_item)

  function new(string name = "tx_gcm_packet_item");
    super.new(name);
  endfunction
endclass

class tx_gcm_cipher_item extends uvm_sequence_item;
  int unsigned packet_index;
  longint unsigned cycle;
  byte unsigned data[PAYLOAD_BYTES];

  `uvm_object_utils(tx_gcm_cipher_item)

  function new(string name = "tx_gcm_cipher_item");
    super.new(name);
  endfunction
endclass

class tx_gcm_meta_item extends uvm_sequence_item;
  int unsigned packet_index;
  longint unsigned cycle;
  byte unsigned aad[AAD_BYTES];
  byte unsigned tag[TAG_BYTES];

  `uvm_object_utils(tx_gcm_meta_item)

  function new(string name = "tx_gcm_meta_item");
    super.new(name);
  endfunction
endclass
