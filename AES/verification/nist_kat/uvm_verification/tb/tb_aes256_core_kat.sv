`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// NIST AESAVS known-answer test for aes256_iterative_core.
//
// NIST 가 배포하는 .rsp 파일을 변환 없이 그대로 읽는다.  [ENCRYPT] 섹션만
// 사용한다 - 이 코어는 암호화 전용이라 [DECRYPT] 섹션은 대상이 아니다.
//
// 기본적으로 시뮬레이터의 작업 디렉토리에서 .rsp 를 찾는다.  런처가 벡터를
// 작업 디렉토리로 복사해 두므로, 트리를 다른 경로/OS 로 옮겨도 그대로 돈다.
// (RX 쪽 tb_rx_captured_frame.sv 와 같은 방식)
//
//   +VECDIR=<dir>   다른 디렉토리에서 읽고 싶을 때만 지정
// ---------------------------------------------------------------------------
// 파형/실행량 제어 (xsim: -d NAME=값 / VCS: +define+NAME=값)
//   KAT_MAX_VECTORS  파일당 실행할 벡터 수.  0 = 전체(405).  파형을 볼 때는
//                    5 정도로 줄인다 - 전체를 덤프하면 파일이 수 GB 가 된다.
//   KAT_DUMP_VCD     VCD 를 남긴다.  VCS/GTKWave 등 xsim 밖에서 볼 때 사용.
//                    Vivado GUI 로 볼 거면 런처의 -DumpWave 를 쓰는 편이 낫다.
`ifndef KAT_MAX_VECTORS
  `define KAT_MAX_VECTORS 0
`endif

module tb_aes256_core_kat;

  localparam int MAX_VEC = `KAT_MAX_VECTORS;

  // 벡터 디렉토리 후보.  순서대로 시도해서 처음 열리는 곳을 쓴다.
  //   "."  : 스탠드얼론 런처가 벡터를 작업 디렉토리로 복사해 둔 경우
  //   ../..: Vivado 프로젝트에서 돌릴 때.  작업 디렉토리가
  //          <proj>.sim/sim_1/behav/xsim 이라 트리 루트까지 6 단계 올라간다
  //   절대 : 위 둘이 모두 실패할 때의 최후 수단
  localparam int NUM_SEARCH = 3;
  string search_dirs [NUM_SEARCH] = '{
      ".",
      "../../../../../../uvm_verification/kat_vectors",
      "D:/RSA_AES256/uvm_verification/kat_vectors"
  };
  localparam int    NUM_FILES      = 4;

  string vec_files [NUM_FILES] = '{
      "ECBGFSbox256.rsp",
      "ECBKeySbox256.rsp",
      "ECBVarKey256.rsp",
      "ECBVarTxt256.rsp"
  };

  // ---------------------------------------------------------------- clocking
  logic clk = 1'b0;
  always #5 clk = ~clk;          // 100 MHz

  logic rst_n = 1'b0;

  // ------------------------------------------------------------------- DUT
  logic          key_start = 1'b0;
  logic [255:0]  key_in    = 256'h0;
  logic          key_busy;
  logic          round_keys_valid;
  wire  [1919:0] round_keys;

  logic          data_start = 1'b0;
  logic [127:0]  data_in    = 128'h0;
  logic          data_busy;
  logic          data_done;
  logic [127:0]  data_out;

  aes256_key_expansion u_key_expansion (
      .clk(clk), .rst_n(rst_n), .start(key_start), .key_in(key_in),
      .busy(key_busy), .round_keys_valid(round_keys_valid),
      .round_keys(round_keys)
  );

  aes256_iterative_core u_dut (
      .clk(clk), .rst_n(rst_n), .start(data_start), .data_in(data_in),
      .round_keys(round_keys), .round_keys_valid(round_keys_valid),
      .busy(data_busy), .done(data_done), .data_out(data_out)
  );

  // --------------------------------------------------------------- tallies
  int total_vectors = 0;
  int total_fail    = 0;
  int expand_count  = 0;

  logic [255:0] loaded_key = 256'hx;
  bit           key_loaded = 1'b0;

  // ---------------------------------------------------------------- helpers
  function automatic bit has_prefix(input string s, input string p);
    if (s.len() < p.len()) return 1'b0;
    return (s.substr(0, p.len()-1) == p);
  endfunction

  // 해당 디렉토리에서 첫 번째 벡터 파일이 열리는지 확인한다.
  function automatic bit dir_has_vectors(input string dir);
    int fd;
    fd = $fopen({dir, "/", vec_files[0]}, "r");
    if (fd == 0) return 1'b0;
    $fclose(fd);
    return 1'b1;
  endfunction

  // 라운드키 확장.  키가 바뀔 때만 재실행한다 - GFSbox/VarTxt 는 키가 고정이라
  // 405 벡터 전체에서 확장은 실제로 273 회만 일어난다.
  task automatic load_key(input logic [255:0] k);
    if (key_loaded && (k === loaded_key)) return;
    @(negedge clk);
    key_in    = k;
    key_start = 1'b1;
    @(negedge clk);
    key_start = 1'b0;
    while (!round_keys_valid) @(negedge clk);
    loaded_key   = k;
    key_loaded   = 1'b1;
    expand_count = expand_count + 1;
  endtask

  // 단일 블록 암호화.  done 이 뜨는 클럭의 negedge 에서 data_out 을 샘플한다.
  task automatic encrypt_block(input logic [127:0] pt, output logic [127:0] ct);
    @(negedge clk);
    data_in    = pt;
    data_start = 1'b1;
    @(negedge clk);
    data_start = 1'b0;
    do @(negedge clk); while (!data_done);
    ct = data_out;
  endtask

  // ------------------------------------------------------------ .rsp reader
  task automatic run_file(input string path, input string label);
    int           fd;
    int           code;
    string        line;
    bit           in_encrypt;
    logic [255:0] k;
    logic [127:0] p;
    logic [127:0] c;
    logic [127:0] got;
    int           count;
    int           fails;

    in_encrypt = 1'b0;
    count      = 0;
    fails      = 0;

    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "[KAT] cannot open vector file: %s", path);

    forever begin
      line = "";
      code = $fgets(line, fd);
      if (code <= 0) break;

      if (has_prefix(line, "[ENCRYPT]")) begin
        in_encrypt = 1'b1;
      end else if (has_prefix(line, "[DECRYPT]")) begin
        // 복호화 섹션은 이 코어의 대상이 아니다.  여기서 파일을 끊는다.
        break;
      end else if (in_encrypt) begin
        if ($sscanf(line, "KEY = %h", k) == 1) begin
          // 다음 CIPHERTEXT 줄에서 실행할 때까지 보관만 한다.
        end else if ($sscanf(line, "PLAINTEXT = %h", p) == 1) begin
          // 보관
        end else if ($sscanf(line, "CIPHERTEXT = %h", c) == 1) begin
          // KEY / PLAINTEXT / CIPHERTEXT 삼중이 모두 모인 시점에 실행한다.
          load_key(k);
          encrypt_block(p, got);
          count = count + 1;
          if (got !== c) begin
            fails = fails + 1;
            if (fails <= 5)
              $display("  [FAIL] %s #%0d\n         KEY = %064h\n         PT  = %032h\n         EXP = %032h\n         GOT = %032h",
                       label, count-1, k, p, c, got);
          end
          if ((MAX_VEC != 0) && (count >= MAX_VEC)) break;
        end
      end
    end
    $fclose(fd);

    $display("  %-18s vectors=%0d  fail=%0d  %s",
             label, count, fails, (fails == 0) ? "PASS" : "*** FAIL ***");

    total_vectors = total_vectors + count;
    total_fail    = total_fail + fails;
  endtask

  // ------------------------------------------------------------------- main
  initial begin
    string vec_dir;
    string path;

    if ($value$plusargs("VECDIR=%s", vec_dir)) begin
      if (!dir_has_vectors(vec_dir))
        $fatal(1, "[KAT] cannot open %s in +VECDIR=%s",
               vec_files[0], vec_dir);
    end else begin
      vec_dir = "";
      foreach (search_dirs[i])
        if (dir_has_vectors(search_dirs[i])) begin
          vec_dir = search_dirs[i];
          break;
        end
      if (vec_dir == "") begin
        $display("[KAT] vector directory not found.  tried:");
        foreach (search_dirs[i]) $display("        %s", search_dirs[i]);
        $fatal(1, "[KAT] no .rsp files found - specify +VECDIR=<dir>");
      end
    end

`ifdef KAT_DUMP_VCD
    $dumpfile("aes_core_kat.vcd");
    $dumpvars(0, tb_aes256_core_kat);
`endif
`ifdef KAT_DUMP_FSDB
    // Verdi PLI 가 링크되어 있을 때만 쓴다 (make WAVE=fsdb).
    $fsdbDumpfile("aes_core_kat.fsdb");
    $fsdbDumpvars(0, tb_aes256_core_kat);
`endif

    $display("========================================================");
    $display(" AES-256 ECB Known Answer Test (NIST AESAVS)");
    $display(" DUT        : aes256_iterative_core");
    $display(" Vector dir : %s", vec_dir);
    if (MAX_VEC != 0)
      $display(" NOTE       : limited to %0d vectors per file - waveform run, NOT full verification", MAX_VEC);
    $display("========================================================");

    repeat (8) @(negedge clk);
    rst_n = 1'b1;
    repeat (4) @(negedge clk);

    foreach (vec_files[i]) begin
      path = {vec_dir, "/", vec_files[i]};
      run_file(path, vec_files[i]);
    end

    $display("--------------------------------------------------------");
    $display(" TOTAL      : %0d vectors, %0d fail", total_vectors, total_fail);
    $display(" key expand : %0d times", expand_count);
    $display("--------------------------------------------------------");

    // 벡터 수 제한이 걸린 파형 확인용 실행에서는 405 개수 검사를 건너뛴다.
    if ((MAX_VEC == 0) && (total_vectors != 405))
      $fatal(1, "[KAT] expected 405 ENCRYPT vectors, parsed %0d - parse failed", total_vectors);
    if (total_fail != 0)
      $fatal(1, "[KAT] FAILED: %0d/%0d mismatch", total_fail, total_vectors);

    if (MAX_VEC != 0)
      $display(" RESULT     : PASS - %0d vectors matched (LIMITED RUN, not full verification)",
               total_vectors);
    else
      $display(" RESULT     : PASS - all %0d NIST AESAVS vectors matched", total_vectors);
    $display("========================================================");
    $finish;
  end

  initial begin
    #50000000;
    $fatal(1, "[KAT] simulation timeout");
  end

endmodule
