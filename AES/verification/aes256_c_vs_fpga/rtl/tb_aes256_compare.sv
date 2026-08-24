`timescale 1ns / 1ps

module tb_aes256_compare;
  localparam int RECORD_COUNT = 10000;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic key_start = 1'b0;
  logic [255:0] key_in = 256'b0;
  logic key_busy;
  logic round_keys_valid;
  wire [1919:0] round_keys;
  logic data_start = 1'b0;
  logic [127:0] data_in = 128'b0;
  logic data_busy;
  logic data_done;
  logic [127:0] data_out;

  logic [255:0] keys [0:RECORD_COUNT-1];
  logic [127:0] plaintexts [0:RECORD_COUNT-1];
  logic [127:0] golden [0:RECORD_COUNT-1];
  logic [127:0] golden_fixed [0:RECORD_COUNT-1];

  longint unsigned cycle_count = 0;

  always #3.333 clk = ~clk;

  always_ff @(posedge clk) begin
    if (!rst_n)
      cycle_count <= 0;
    else
      cycle_count <= cycle_count + 1;
  end

  aes256_key_expansion u_key_expansion (
      .clk(clk),
      .rst_n(rst_n),
      .start(key_start),
      .key_in(key_in),
      .busy(key_busy),
      .round_keys_valid(round_keys_valid),
      .round_keys(round_keys)
  );

  aes256_iterative_core u_aes (
      .clk(clk),
      .rst_n(rst_n),
      .start(data_start),
      .data_in(data_in),
      .round_keys(round_keys),
      .round_keys_valid(round_keys_valid),
      .busy(data_busy),
      .done(data_done),
      .data_out(data_out)
  );

  task automatic start_new_key(
      input logic [255:0] key,
      output longint unsigned accepted_cycle
  );
    if (key_busy)
      $fatal(1, "Key start attempted while key expansion busy");
    key_in = key;
    key_start = 1'b1;
    @(negedge clk);
    key_start = 1'b0;
    accepted_cycle = cycle_count;
  endtask

  task automatic wait_for_round_keys;
    int waited;
    waited = 0;
    while (!round_keys_valid && waited < 100) begin
      @(negedge clk);
      waited++;
    end
    if (!round_keys_valid)
      $fatal(1, "Key expansion timeout after %0d clocks", waited);
  endtask

  task automatic encrypt_one_block(
      input logic [127:0] plaintext,
      output logic [127:0] ciphertext,
      output longint unsigned accepted_cycle,
      output longint unsigned completed_cycle
  );
    int waited;
    if (data_busy || !round_keys_valid)
      $fatal(1, "AES start attempted when core is not ready");
    data_in = plaintext;
    data_start = 1'b1;
    @(negedge clk);
    data_start = 1'b0;
    accepted_cycle = cycle_count;

    waited = 0;
    while (!data_done && waited < 40) begin
      @(negedge clk);
      waited++;
    end
    if (!data_done)
      $fatal(1, "AES block timeout after %0d clocks", waited);
    ciphertext = data_out;
    completed_cycle = cycle_count;
  endtask

  initial begin
    logic [127:0] ciphertext;
    longint unsigned key_cycle;
    longint unsigned block_cycle;
    longint unsigned done_cycle;
    longint unsigned included_first_cycle;
    longint unsigned included_last_cycle;
    longint unsigned included_latency_sum;
    longint unsigned excluded_first_cycle;
    longint unsigned excluded_last_cycle;
    int included_matches;
    int excluded_matches;
    int i;

    $readmemh("vectors/keys.hex", keys);
    $readmemh("vectors/plaintexts.hex", plaintexts);
    $readmemh("vectors/golden.hex", golden);
    $readmemh("vectors/golden_fixed_key.hex", golden_fixed);

    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);

    start_new_key(
        256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f,
        key_cycle
    );
    wait_for_round_keys();
    encrypt_one_block(
        128'h00112233445566778899aabbccddeeff,
        ciphertext,
        block_cycle,
        done_cycle
    );
    if (ciphertext !== 128'h8ea2b7ca516745bfeafc49904b496089)
      $fatal(1, "RTL FIPS AES-256 KAT mismatch: %032h", ciphertext);
    $display("RTL_FIPS PASS ciphertext=%032h key_cycles=%0d block_cycles=%0d",
             ciphertext, block_cycle - key_cycle, done_cycle - block_cycle);

    included_matches = 0;
    included_latency_sum = 0;
    included_first_cycle = 0;
    included_last_cycle = 0;
    for (i = 0; i < RECORD_COUNT; i++) begin
      start_new_key(keys[i], key_cycle);
      if (i == 0)
        included_first_cycle = key_cycle;
      wait_for_round_keys();
      encrypt_one_block(plaintexts[i], ciphertext, block_cycle, done_cycle);
      included_latency_sum += done_cycle - key_cycle;
      included_last_cycle = done_cycle;
      if (ciphertext === golden[i])
        included_matches++;
      else
        $fatal(1, "RTL key-included mismatch at record %0d: got=%032h expected=%032h",
               i, ciphertext, golden[i]);
    end
    $display("RTL_KEY_INCLUDED blocks=%0d cycles=%0d latency_cycles_sum=%0d matches=%0d",
             RECORD_COUNT, included_last_cycle - included_first_cycle,
             included_latency_sum, included_matches);

    start_new_key(keys[0], key_cycle);
    wait_for_round_keys();
    excluded_matches = 0;
    excluded_first_cycle = 0;
    excluded_last_cycle = 0;
    for (i = 0; i < RECORD_COUNT; i++) begin
      encrypt_one_block(plaintexts[i], ciphertext, block_cycle, done_cycle);
      if (i == 0)
        excluded_first_cycle = block_cycle;
      excluded_last_cycle = done_cycle;
      if (ciphertext === golden_fixed[i])
        excluded_matches++;
      else
        $fatal(1, "RTL key-excluded mismatch at record %0d: got=%032h expected=%032h",
               i, ciphertext, golden_fixed[i]);
    end
    $display("RTL_KEY_EXCLUDED blocks=%0d cycles=%0d matches=%0d",
             RECORD_COUNT, excluded_last_cycle - excluded_first_cycle,
             excluded_matches);
    $display("RTL_CLOCK frequency_hz=150000000 period_ns=6.666666667");
    $finish;
  end
endmodule
