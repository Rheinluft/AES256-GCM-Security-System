// ---------------------------------------------------------------------------
// Watches s_axis, reassembles each 92-beat record, and turns it into the
// expected DUT behaviour for that packet (doc section 6.3: "기대 평문 생성").
//
// The prediction reimplements the protocol acceptance rules from
// video_aes_gcm_rx_top.sv / gcm_protocol_pkg.sv independently, and takes the
// expected plaintext from the OpenSSL golden file rather than from a model.
// ---------------------------------------------------------------------------

class rx_expect_item extends uvm_object;
  `uvm_object_utils(rx_expect_item)

  int unsigned  packet_index;
  bit           expect_zero;   // authentication/protocol failure -> 90 zero beats
  byte unsigned plain[];       // valid only when expect_zero == 0
  string        reason;

  function new(string name = "rx_expect_item");
    super.new(name);
  endfunction
endclass


class rx_in_monitor extends uvm_component;
  `uvm_component_utils(rx_in_monitor)

  virtual rx_if vif;
  rx_vector_db  db;
  uvm_analysis_port #(rx_expect_item) ap;

  // Protocol context, mirroring the core's frame_context_* registers.
  bit          ctx_valid;
  logic [31:0] ctx_session;
  logic [31:0] ctx_frame;
  bit          ctx_encrypted;
  logic [15:0] expect_index;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual rx_if)::get(this, "", "vif", vif))
      `uvm_fatal("IMON", "virtual interface not set")
    if (!uvm_config_db#(rx_vector_db)::get(this, "", "db", db))
      `uvm_fatal("IMON", "golden vector db not set")
  endfunction

  task run_phase(uvm_phase phase);
    byte unsigned rec[];
    int unsigned  count;
    rec = new[RECORD_BYTES];
    count = 0;
    forever begin
      @(posedge vif.aclk);
      if (vif.aresetn !== 1'b1) begin
        count = 0;
        continue;
      end
      if (vif.s_axis_tvalid === 1'b1 && vif.s_axis_tready === 1'b1) begin
        for (int lane = 0; lane < 16; lane++)
          rec[count * 16 + lane] = vif.s_axis_tdata[lane*8 +: 8];
        count++;
        if (count == RECORD_WORDS) begin
          predict(rec);
          count = 0;
        end
      end
    end
  endtask

  function void predict(const ref byte unsigned rec[]);
    rx_expect_item e = rx_expect_item::type_id::create("expect");
    logic [31:0] magic   = {rec[0], rec[1], rec[2], rec[3]};
    logic [31:0] session = {rec[4], rec[5], rec[6], rec[7]};
    logic [31:0] frame   = {rec[8], rec[9], rec[10], rec[11]};
    logic [15:0] index   = {rec[12], rec[13]};
    logic [15:0] flags   = {rec[14], rec[15]};
    bit sequence_good, header_good, tampered;

    // input_sequence_good
    sequence_good = (index == 16'd0) ||
                    (ctx_valid && (session == ctx_session) &&
                     (frame == ctx_frame) && (flags[0] == ctx_encrypted) &&
                     (index == expect_index));

    // input_header_good (TKEEP/TLAST are always legal from this driver)
    header_good = (magic == GOLDEN_MAGIC) &&
                  (session == GOLDEN_SESSION_ID) &&
                  (index <= LAST_PACKET) &&
                  (flags[15:12] == 4'h1) &&
                  (flags[11:3] == 9'b0) &&
                  (flags[1] == (index == 16'd0)) &&
                  (flags[2] == (index == LAST_PACKET)) &&
                  sequence_good;

    // A record is "tampered" when its ciphertext or TAG differs from the
    // pristine golden bytes for that index; the TAG check must then fail.
    tampered = 1'b0;
    if (index < db.num_packets) begin
      for (int b = AAD_BYTES; b < RECORD_BYTES; b++)
        if (rec[b] != db.rec[index][b]) tampered = 1'b1;
    end else begin
      tampered = 1'b1;
    end

    e.packet_index = index;
    if (!header_good) begin
      e.expect_zero = 1'b1;
      e.reason = "header/sequence rejected -> DROP, zero payload";
    end else if (tampered) begin
      e.expect_zero = 1'b1;
      e.reason = "TAG mismatch -> auth_fail, zero payload";
    end else begin
      e.expect_zero = 1'b0;
      e.plain = new[PAYLOAD_BYTES];
      foreach (e.plain[b]) e.plain[b] = db.plain[index][b];
      e.reason = "authenticated -> golden plaintext";
    end

    // Context update, mirroring the core.  Note both the ST_IDLE capture and
    // the packet_commit update run regardless of input_header_good: a rejected
    // record still advances expected_packet_index, so the packet after a bad
    // one is accepted again rather than cascading failures.
    if (index == 16'd0) begin
      ctx_valid     = 1'b1;
      ctx_session   = session;
      ctx_frame     = frame;
      ctx_encrypted = flags[0];
      expect_index  = 16'd1;
    end else if (index == LAST_PACKET) begin
      ctx_valid    = 1'b0;
      expect_index = 16'd0;
    end else begin
      expect_index = index + 16'd1;
    end

    `uvm_info("IMON", $sformatf("pkt %0d: %s", index, e.reason), UVM_HIGH)
    ap.write(e);
  endfunction

endclass
