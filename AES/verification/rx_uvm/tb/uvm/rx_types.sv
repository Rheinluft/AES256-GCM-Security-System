// ---------------------------------------------------------------------------
// Shared types + the golden vector database.
// ---------------------------------------------------------------------------

typedef enum int {
  TK_NONE       = 0,  // pristine golden record
  TK_TAG_FLIP   = 1,  // 1 bit inverted in the TAG
  TK_CIPHER_FLIP= 2,  // 1 bit inverted in the ciphertext
  TK_REPLAY     = 3,  // resend of an already authenticated packet index
  TK_SEQUENCE   = 4,  // packet index skipped forward
  TK_SESSION    = 5,  // AAD carries a foreign session id
  TK_TIMEOUT    = 6   // no beats at all, just idle
} tamper_e;

// err_flags / err_sticky bit positions, mirroring gcm_rx_error_detector.sv
typedef enum int {
  ERRB_TAG      = 0,
  ERRB_REPLAY   = 1,
  ERRB_SEQUENCE = 2,
  ERRB_SESSION  = 3,
  ERRB_TIMEOUT  = 4
} err_bit_e;

parameter int unsigned AAD_BYTES      = 16;
parameter int unsigned PAYLOAD_BYTES  = 1440;
parameter int unsigned TAG_BYTES      = 16;
parameter int unsigned RECORD_BYTES   = AAD_BYTES + PAYLOAD_BYTES + TAG_BYTES;
parameter int unsigned RECORD_WORDS   = RECORD_BYTES / 16;    // 92
parameter int unsigned PAYLOAD_WORDS  = PAYLOAD_BYTES / 16;   // 90
parameter int unsigned FRAME_PACKETS  = 1280;
parameter int unsigned LAST_PACKET    = FRAME_PACKETS - 1;

parameter logic [31:0] GOLDEN_MAGIC      = 32'h5043414d;  // "PCAM"
parameter logic [31:0] GOLDEN_SESSION_ID = 32'h0000_0001;
parameter logic [255:0] GOLDEN_KEY =
    256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;


// ---------------------------------------------------------------------------
// Holds the OpenSSL-generated golden vectors.  These are reference data read
// from disk, not a model: the scoreboard compares DUT output against bytes
// that were independently produced and SHA-256 verified.
// ---------------------------------------------------------------------------
class rx_vector_db extends uvm_object;
  `uvm_object_utils(rx_vector_db)

  int unsigned  num_packets;
  byte unsigned rec  [][];   // [packet][1472]  AAD | ciphertext | TAG
  byte unsigned plain[][];   // [packet][1440]  expected recovered payload

  function new(string name = "rx_vector_db");
    super.new(name);
  endfunction

  function void load(string stim_path, string gold_path, int unsigned n);
    int stim_fd, gold_fd;
    int unsigned got;
    byte unsigned stim_buf[];
    byte unsigned gold_buf[];

    num_packets = n;
    stim_buf = new[n * RECORD_BYTES];
    gold_buf = new[n * PAYLOAD_BYTES];

    stim_fd = $fopen(stim_path, "rb");
    if (stim_fd == 0) `uvm_fatal("VECDB", $sformatf("cannot open %s", stim_path))
    got = $fread(stim_buf, stim_fd);
    $fclose(stim_fd);
    if (got != n * RECORD_BYTES)
      `uvm_fatal("VECDB", $sformatf("%s: got %0d bytes, want %0d",
                                    stim_path, got, n * RECORD_BYTES))

    gold_fd = $fopen(gold_path, "rb");
    if (gold_fd == 0) `uvm_fatal("VECDB", $sformatf("cannot open %s", gold_path))
    got = $fread(gold_buf, gold_fd);
    $fclose(gold_fd);
    if (got != n * PAYLOAD_BYTES)
      `uvm_fatal("VECDB", $sformatf("%s: got %0d bytes, want %0d",
                                    gold_path, got, n * PAYLOAD_BYTES))

    rec   = new[n];
    plain = new[n];
    foreach (rec[i]) begin
      rec[i]   = new[RECORD_BYTES];
      plain[i] = new[PAYLOAD_BYTES];
      foreach (rec[i][b])   rec[i][b]   = stim_buf[i * RECORD_BYTES + b];
      foreach (plain[i][b]) plain[i][b] = gold_buf[i * PAYLOAD_BYTES + b];
    end

    `uvm_info("VECDB", $sformatf("loaded %0d golden packets from %s",
                                 n, stim_path), UVM_LOW)
  endfunction

  // Byte offset helpers into a 1472-byte record.
  static function int unsigned tag_offset();     return AAD_BYTES + PAYLOAD_BYTES; endfunction
  static function int unsigned payload_offset(); return AAD_BYTES;                 endfunction
endclass
