`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// STEP 2 smoke testbench (directed, no UVM).
//
// Purpose: prove the RTL + golden-vector + byte-ordering combination works
// before any UVM code exists, so a later UVM failure cannot be ambiguous
// between "RTL bug", "bad vectors" and "testbench bug".
//
// Feeds N golden records (AAD | ciphertext | TAG) into s_axis and compares the
// decrypted m_axis payload against the golden plaintext.
// ---------------------------------------------------------------------------
module tb_rx_smoke;

  // Overridable from the command line: -pvalue+tb_rx_smoke.PKT_COUNT=1280
  parameter int unsigned PKT_COUNT     = 8;
  parameter int unsigned AAD_BYTES     = 16;
  parameter int unsigned PAYLOAD_BYTES = 1440;
  parameter int unsigned TAG_BYTES     = 16;
  parameter int unsigned RECORD_BYTES  = AAD_BYTES + PAYLOAD_BYTES + TAG_BYTES;
  parameter int unsigned RECORD_WORDS  = RECORD_BYTES / 16;   // 92
  parameter int unsigned PAYLOAD_WORDS = PAYLOAD_BYTES / 16;  // 90

  localparam int unsigned STIM_BYTES = PKT_COUNT * RECORD_BYTES;
  localparam int unsigned GOLD_BYTES = PKT_COUNT * PAYLOAD_BYTES;

  // 150 MHz
  localparam time CLK_PERIOD = 6.667ns;

  logic aclk = 1'b0;
  logic aresetn = 1'b0;
  always #(CLK_PERIOD/2) aclk = ~aclk;

  // ---- DUT interface -------------------------------------------------------
  logic         sw3_decrypt;
  logic [31:0]  session_id;
  logic [255:0] session_key;
  logic         session_key_valid;
  logic         key_commit;
  logic         key_clear;
  logic [15:0]  key_epoch;

  logic [127:0] s_axis_tdata;
  logic [15:0]  s_axis_tkeep;
  logic         s_axis_tvalid;
  logic         s_axis_tready;
  logic         s_axis_tlast;

  logic [127:0] m_axis_tdata;
  logic [15:0]  m_axis_tkeep;
  logic         m_axis_tvalid;
  logic         m_axis_tready;
  logic         m_axis_tlast;

  logic [31:0]  frame_status;
  logic         key_ready;
  logic         busy;

  logic [31:0]  error_control;
  logic [31:0]  error_status;
  logic         error_irq;

  logic         err_valid;
  logic [4:0]   err_flags;
  logic [2:0]   err_code;
  logic [4:0]   err_sticky;
  logic [191:0] err_record;

  // Doc section 7: shrink the timeouts, otherwise SESSION/TIMEOUT detection is
  // masked for 7.5M clocks after reset and simulation time explodes.
  axis_gcm_rx_frame_processor #(
      .RECORD_WORDS (RECORD_WORDS),
      .FRAME_PACKETS(1280),
      .CLK_HZ       (150_000_000),
      .TIMEOUT_US   (32'd200),
      .REKEY_US     (32'd100)
  ) dut (
      .aclk(aclk), .aresetn(aresetn),
      .sw3_decrypt(sw3_decrypt),
      .session_id(session_id),
      .session_key(session_key),
      .session_key_valid(session_key_valid),
      .key_commit(key_commit), .key_clear(key_clear),
      .key_epoch(key_epoch),
      .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep),
      .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready),
      .s_axis_tlast(s_axis_tlast),
      .m_axis_tdata(m_axis_tdata), .m_axis_tkeep(m_axis_tkeep),
      .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready),
      .m_axis_tlast(m_axis_tlast),
      .frame_status(frame_status), .key_ready(key_ready), .busy(busy),
      .error_control(error_control), .error_status(error_status),
      .error_irq(error_irq),
      .err_valid(err_valid), .err_flags(err_flags), .err_code(err_code),
      .err_sticky(err_sticky), .err_record(err_record)
  );

  // ---- vector storage ------------------------------------------------------
  // Dynamic so they can be passed by ref to load(); sized at time 0 below.
  logic [7:0] stim     [];
  logic [7:0] gold     [];
  logic [7:0] captured [];
  int unsigned captured_bytes = 0;

  initial begin
    stim     = new[STIM_BYTES];
    gold     = new[GOLD_BYTES];
    captured = new[GOLD_BYTES];
  end

  int unsigned err_events = 0;
  int unsigned err_sticky_seen = 0;

  string stim_path;
  string gold_path;

  function automatic void load(input string path, ref logic [7:0] mem [],
                               input int unsigned expect_bytes);
    int fd;
    int unsigned got;
    fd = $fopen(path, "rb");
    if (fd == 0) begin
      $fatal(1, "cannot open %s", path);
    end
    got = $fread(mem, fd);
    $fclose(fd);
    if (got != expect_bytes)
      $fatal(1, "%s: read %0d bytes, expected %0d", path, got, expect_bytes);
    $display("[TB] loaded %s (%0d bytes)", path, got);
  endfunction

  // ---- stimulus ------------------------------------------------------------
  task automatic drive_beat(input int unsigned byte_base, input bit last);
    for (int lane = 0; lane < 16; lane++)
      s_axis_tdata[lane*8 +: 8] <= stim[byte_base + lane];
    s_axis_tkeep  <= 16'hffff;
    s_axis_tlast  <= last;
    s_axis_tvalid <= 1'b1;
    @(posedge aclk);
    while (!s_axis_tready) @(posedge aclk);
    s_axis_tvalid <= 1'b0;
    s_axis_tlast  <= 1'b0;
  endtask

  task automatic send_packet(input int unsigned index);
    int unsigned base = index * RECORD_BYTES;
    bit last_of_frame;
    for (int w = 0; w < RECORD_WORDS; w++) begin
      // TLAST only on the final beat of the final protocol packet (1279).
      last_of_frame = (index == 1279) && (w == RECORD_WORDS-1);
      drive_beat(base + w*16, last_of_frame);
    end
  endtask

  // ---- output capture ------------------------------------------------------
  always @(posedge aclk) begin
    if (aresetn && m_axis_tvalid && m_axis_tready) begin
      for (int lane = 0; lane < 16; lane++) begin
        if (captured_bytes + lane < GOLD_BYTES)
          captured[captured_bytes + lane] <= m_axis_tdata[lane*8 +: 8];
      end
      captured_bytes <= captured_bytes + 16;
    end
  end

  // ---- error event log -----------------------------------------------------
  always @(posedge aclk) begin
    if (aresetn && err_valid) begin
      err_events <= err_events + 1;
      $display("[TB] %0t ERROR err_flags=%b err_code=%0d", $time,
               err_flags, err_code);
    end
  end

  // ---- main ----------------------------------------------------------------
  int unsigned mismatches;
  int unsigned first_bad;

  initial begin
    if (!$value$plusargs("STIM=%s", stim_path))
      stim_path = $sformatf("../data/rx_normal_%0dpkt.bin", PKT_COUNT);
    if (!$value$plusargs("GOLD=%s", gold_path))
      gold_path = $sformatf("../data/rx_plain_%0dpkt.bin", PKT_COUNT);

    load(stim_path, stim, STIM_BYTES);
    load(gold_path, gold, GOLD_BYTES);

    sw3_decrypt       = 1'b1;   // decrypt mode
    session_id        = 32'h0000_0001;
    session_key       = 256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
    session_key_valid = 1'b0;
    key_commit        = 1'b0;
    key_clear         = 1'b0;
    key_epoch         = 16'd1;
    error_control     = 32'd0;  // error_enable = 0 -> all five enabled
    s_axis_tdata      = '0;
    s_axis_tkeep      = 16'hffff;
    s_axis_tvalid     = 1'b0;
    s_axis_tlast      = 1'b0;
    m_axis_tready     = 1'b1;

    repeat (10) @(posedge aclk);
    aresetn = 1'b1;
    repeat (5) @(posedge aclk);

    // Key commit sequence (doc section 7).
    session_key_valid <= 1'b1;
    @(posedge aclk);
    key_commit <= 1'b1;
    @(posedge aclk);
    key_commit <= 1'b0;

    fork begin
      repeat (2000) @(posedge aclk);
      $fatal(1, "key_ready never asserted");
    end
    begin
      wait (key_ready === 1'b1);
    end
    join_any
    disable fork;
    $display("[TB] key_ready at %0t", $time);

    for (int unsigned i = 0; i < PKT_COUNT; i++) begin
      send_packet(i);
      if ((i % 128) == 0)
        $display("[TB] injected packet %0d", i);
    end
    $display("[TB] all %0d packets injected at %0t", PKT_COUNT, $time);

    // Drain the output pipeline.  Must stay well under TIMEOUT_US (200us).
    fork begin
      repeat (60000) @(posedge aclk);
    end
    begin
      wait (captured_bytes >= GOLD_BYTES);
      repeat (20) @(posedge aclk);
    end
    join_any
    disable fork;

    err_sticky_seen = err_sticky;

    // ---- scoreboard --------------------------------------------------------
    mismatches = 0;
    first_bad  = 32'hffff_ffff;
    for (int unsigned b = 0; b < GOLD_BYTES; b++) begin
      if (captured[b] !== gold[b]) begin
        mismatches++;
        if (first_bad == 32'hffff_ffff) first_bad = b;
      end
    end

    $display("\n================ SMOKE RESULT ================");
    $display(" packets injected : %0d", PKT_COUNT);
    $display(" bytes expected   : %0d", GOLD_BYTES);
    $display(" bytes captured   : %0d", captured_bytes);
    $display(" byte mismatches  : %0d", mismatches);
    if (mismatches != 0)
      $display(" first bad byte   : %0d (pkt %0d) got=%02h exp=%02h",
               first_bad, first_bad / PAYLOAD_BYTES,
               captured[first_bad], gold[first_bad]);
    $display(" err_valid events : %0d", err_events);
    $display(" err_sticky       : %b", err_sticky_seen);
    $display(" frame_status     : %08h", frame_status);

    if (captured_bytes == GOLD_BYTES && mismatches == 0 && err_events == 0)
      $display("================ SMOKE PASS ================\n");
    else
      $display("================ SMOKE FAIL ================\n");
    $finish;
  end

endmodule
