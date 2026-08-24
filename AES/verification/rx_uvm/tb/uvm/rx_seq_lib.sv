// ---------------------------------------------------------------------------
// Sequences 1..8 of doc section 6.2.
// Every record starts as a pristine golden record; scenarios mutate a copy.
// ---------------------------------------------------------------------------
class rx_base_seq extends uvm_sequence #(rx_record_item);
  `uvm_object_utils(rx_base_seq)

  rx_vector_db db;
  int unsigned num_packets = 8;
  int unsigned stall_pct   = 0;

  function new(string name = "rx_base_seq");
    super.new(name);
  endfunction

  task pre_start();
    if (!uvm_config_db#(rx_vector_db)::get(null, "*", "db", db))
      `uvm_fatal("SEQ", "golden vector db not set")
    void'(uvm_config_db#(int unsigned)::get(null, "*", "num_packets", num_packets));
    void'(uvm_config_db#(int unsigned)::get(null, "*", "stall_pct", stall_pct));
  endtask

  // Build a pristine item for a golden packet index.
  function rx_record_item golden(int unsigned index);
    rx_record_item it = rx_record_item::type_id::create("it");
    it.packet_index = index;
    foreach (it.data[b]) it.data[b] = db.rec[index][b];
    it.kind = TK_NONE;
    it.last_of_frame = (index == LAST_PACKET);
    it.stall_pct = stall_pct;
    return it;
  endfunction

  task send(rx_record_item it);
    start_item(it);
    finish_item(it);
  endtask
endclass


// --- 1. 정상 패킷 -----------------------------------------------------------
class rx_normal_seq extends rx_base_seq;
  `uvm_object_utils(rx_normal_seq)
  function new(string name = "rx_normal_seq"); super.new(name); endfunction

  task body();
    for (int unsigned i = 0; i < num_packets; i++)
      send(golden(i));
  endtask
endclass


// --- 2. TAG 변조 ------------------------------------------------------------
class rx_tag_tamper_seq extends rx_base_seq;
  `uvm_object_utils(rx_tag_tamper_seq)
  int unsigned victim = 1;
  function new(string name = "rx_tag_tamper_seq"); super.new(name); endfunction

  task body();
    for (int unsigned i = 0; i < num_packets; i++) begin
      rx_record_item it = golden(i);
      if (i == victim) it.flip_tag_bit(0);
      send(it);
    end
  endtask
endclass


// --- 3. Ciphertext 변조 -----------------------------------------------------
class rx_cipher_tamper_seq extends rx_base_seq;
  `uvm_object_utils(rx_cipher_tamper_seq)
  int unsigned victim = 1;
  function new(string name = "rx_cipher_tamper_seq"); super.new(name); endfunction

  task body();
    for (int unsigned i = 0; i < num_packets; i++) begin
      rx_record_item it = golden(i);
      if (i == victim) it.flip_cipher_bit(0);
      send(it);
    end
  endtask
endclass


// --- 4. 변조 후 정상 복구 ---------------------------------------------------
// handoff README section 9: 0 normal, 1 TAG, 2 normal, 3 cipher, 4 normal
class rx_recovery_seq extends rx_base_seq;
  `uvm_object_utils(rx_recovery_seq)
  function new(string name = "rx_recovery_seq"); super.new(name); endfunction

  task body();
    for (int unsigned i = 0; i < num_packets; i++) begin
      rx_record_item it = golden(i);
      if (i == 1) it.flip_tag_bit(3);
      if (i == 3) it.flip_cipher_bit(11520);  // middle of the payload
      send(it);
    end
  endtask
endclass


// --- 5. Replay --------------------------------------------------------------
// Doc section 6.2: only authenticated packets enter the replay bitmap, so the
// resent record must be pristine.
class rx_replay_seq extends rx_base_seq;
  `uvm_object_utils(rx_replay_seq)
  int unsigned replay_index = 1;
  function new(string name = "rx_replay_seq"); super.new(name); endfunction

  task body();
    for (int unsigned i = 0; i < num_packets; i++)
      send(golden(i));
    send(golden(replay_index));   // pristine resend of an accepted index
  endtask
endclass


// --- 6. Sequence ------------------------------------------------------------
class rx_sequence_gap_seq extends rx_base_seq;
  `uvm_object_utils(rx_sequence_gap_seq)
  int unsigned skip_to = 5;
  function new(string name = "rx_sequence_gap_seq"); super.new(name); endfunction

  task body();
    send(golden(0));
    send(golden(1));
    send(golden(skip_to));         // jumps over 2..4
    for (int unsigned i = skip_to + 1; i < num_packets; i++)
      send(golden(i));
  endtask
endclass


// --- 7. Session -------------------------------------------------------------
// gcm_rx_error_detector gates hit_session with !rekey_active, and rekey_left_us
// is reloaded with REKEY_US (100us here) on key_commit.  At ~8.85us per record
// the grace window covers roughly the first 11 packets, so the foreign-session
// record must land after it or the detector legitimately stays silent.
class rx_session_seq extends rx_base_seq;
  `uvm_object_utils(rx_session_seq)
  int unsigned victim = 13;
  function new(string name = "rx_session_seq"); super.new(name); endfunction

  task body();
    for (int unsigned i = 0; i < num_packets; i++) begin
      rx_record_item it = golden(i);
      if (i == victim) begin
        it.set_aad_session(32'hDEAD_BEEF);
        it.kind = TK_SESSION;
      end
      send(it);
    end
  endtask
endclass


// --- 8. Timeout -------------------------------------------------------------
class rx_timeout_seq extends rx_base_seq;
  `uvm_object_utils(rx_timeout_seq)
  // TIMEOUT_US=200 at 150 MHz -> 30000 clocks; idle well past it.
  int unsigned idle_clocks = 45000;
  function new(string name = "rx_timeout_seq"); super.new(name); endfunction

  task body();
    rx_record_item idle;
    send(golden(0));
    send(golden(1));
    idle = rx_record_item::type_id::create("idle");
    idle.kind = TK_TIMEOUT;
    idle.idle_clocks = idle_clocks;
    send(idle);
  endtask
endclass
