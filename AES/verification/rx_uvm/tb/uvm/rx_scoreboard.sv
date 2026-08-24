`uvm_analysis_imp_decl(_exp)
`uvm_analysis_imp_decl(_out)
`uvm_analysis_imp_decl(_err)

// ---------------------------------------------------------------------------
// Triple judgement per doc section 6.3:
//   1. plaintext equality for authenticated packets
//   2. zero substitution for rejected packets (no early plaintext leak)
//   3. error-code tally against what the scenario declared
// ---------------------------------------------------------------------------
class rx_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(rx_scoreboard)

  uvm_analysis_imp_exp #(rx_expect_item, rx_scoreboard) exp_imp;
  uvm_analysis_imp_out #(rx_out_item,    rx_scoreboard) out_imp;
  uvm_analysis_imp_err #(rx_err_item,    rx_scoreboard) err_imp;

  rx_expect_item exp_q[$];
  rx_err_item    err_q[$];

  int unsigned n_checked;
  int unsigned n_plain_ok;
  int unsigned n_zero_ok;
  int unsigned n_fail;

  // Declared by the test: how many events are expected per err_flags bit.
  int unsigned exp_err_count[5];
  bit          err_check_enabled = 1'b1;

  // Functional coverage over the five error classes (doc STEP 4).
  logic [4:0] cov_flags;
  logic [2:0] cov_code;

  covergroup err_cg;
    option.per_instance = 1;
    cp_code: coverpoint cov_code {
      bins tag      = {3'd1};
      bins replay   = {3'd2};
      bins seq_gap  = {3'd3};
      bins session  = {3'd4};
      bins timeout  = {3'd5};
    }
    cp_tag      : coverpoint cov_flags[ERRB_TAG]      { bins hit = {1'b1}; }
    cp_replay   : coverpoint cov_flags[ERRB_REPLAY]   { bins hit = {1'b1}; }
    cp_sequence : coverpoint cov_flags[ERRB_SEQUENCE] { bins hit = {1'b1}; }
    cp_session  : coverpoint cov_flags[ERRB_SESSION]  { bins hit = {1'b1}; }
    cp_timeout  : coverpoint cov_flags[ERRB_TIMEOUT]  { bins hit = {1'b1}; }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    exp_imp = new("exp_imp", this);
    out_imp = new("out_imp", this);
    err_imp = new("err_imp", this);
    err_cg  = new();
    foreach (exp_err_count[i]) exp_err_count[i] = 0;
  endfunction

  function void write_exp(rx_expect_item e);
    exp_q.push_back(e);
  endfunction

  function void write_err(rx_err_item e);
    err_q.push_back(e);
    cov_flags = e.flags;
    cov_code  = e.code;
    err_cg.sample();
  endfunction

  function void write_out(rx_out_item o);
    rx_expect_item e;
    int unsigned bad;
    int unsigned first_bad;

    if (exp_q.size() == 0) begin
      `uvm_error("SCB", "output packet with no pending expectation")
      n_fail++;
      return;
    end
    e = exp_q.pop_front();
    n_checked++;

    bad = 0;
    first_bad = 32'hffff_ffff;
    if (e.expect_zero) begin
      foreach (o.plain[b])
        if (o.plain[b] !== 8'h00) begin
          bad++;
          if (first_bad == 32'hffff_ffff) first_bad = b;
        end
      if (bad == 0) begin
        n_zero_ok++;
        `uvm_info("SCB", $sformatf("pkt %0d zero-substituted as expected (%s)",
                                   e.packet_index, e.reason), UVM_MEDIUM)
      end else begin
        n_fail++;
        `uvm_error("SCB", $sformatf(
            "pkt %0d PLAINTEXT LEAK: %0d non-zero bytes, first at %0d = %02h",
            e.packet_index, bad, first_bad, o.plain[first_bad]))
      end
    end else begin
      foreach (o.plain[b])
        if (o.plain[b] !== e.plain[b]) begin
          bad++;
          if (first_bad == 32'hffff_ffff) first_bad = b;
        end
      if (bad == 0) begin
        n_plain_ok++;
        `uvm_info("SCB", $sformatf("pkt %0d plaintext matches golden",
                                   e.packet_index), UVM_HIGH)
      end else begin
        n_fail++;
        `uvm_error("SCB", $sformatf(
            "pkt %0d PLAINTEXT MISMATCH: %0d bytes, first at %0d got=%02h exp=%02h",
            e.packet_index, bad, first_bad,
            o.plain[first_bad], e.plain[first_bad]))
      end
    end
  endfunction

  // Called by the test before the run finishes.
  function void expect_error(err_bit_e which, int unsigned count = 1);
    exp_err_count[int'(which)] = count;
  endfunction

  function int unsigned seen_error(err_bit_e which);
    int unsigned n = 0;
    foreach (err_q[i])
      if (err_q[i].flags[int'(which)]) n++;
    return n;
  endfunction

  function void check_phase(uvm_phase phase);
    string names[5] = '{"TAG", "REPLAY", "SEQUENCE", "SESSION", "TIMEOUT"};
    super.check_phase(phase);

    if (exp_q.size() != 0) begin
      `uvm_error("SCB", $sformatf("%0d expected packets never produced output",
                                  exp_q.size()))
      n_fail++;
    end

    if (err_check_enabled) begin
      for (int i = 0; i < 5; i++) begin
        int unsigned got = seen_error(err_bit_e'(i));
        if (got != exp_err_count[i]) begin
          `uvm_error("SCB", $sformatf("err_flags[%0d] (%s): saw %0d events, expected %0d",
                                      i, names[i], got, exp_err_count[i]))
          n_fail++;
        end else if (exp_err_count[i] != 0) begin
          `uvm_info("SCB", $sformatf("err_flags[%0d] (%s): %0d events as expected",
                                     i, names[i], got), UVM_LOW)
        end
      end
    end

    `uvm_info("SCB", $sformatf(
        "\n=============== SCOREBOARD ===============\n packets checked   : %0d\n plaintext match   : %0d\n zero-substituted  : %0d\n error events      : %0d\n failures          : %0d\n==========================================",
        n_checked, n_plain_ok, n_zero_ok, err_q.size(), n_fail), UVM_NONE)
  endfunction

endclass
