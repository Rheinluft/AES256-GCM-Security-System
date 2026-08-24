# AES-256 pure C versus FPGA core results

- Run time: 2026-08-13 17:59:46 +09:00
- CPU: 12th Gen Intel(R) Core(TM) i7-1260P (pinned to logical CPU 0)
- C compiler: gcc.exe (MinGW-W64 x86_64-ucrt-posix-seh, built by Brecht Sanders, r8) 13.2.0
- OpenSSL golden generator: OpenSSL 3.3.0 9 Apr 2024 (Library: OpenSSL 3.3.0 9 Apr 2024)
- Disassembly audit: GNU objdump (Binutils for MinGW-W64 x86_64, built by Brecht Sanders, r8) 2.42
- FPGA simulator: Vivado Simulator v2025.2
- FPGA clock: 150 MHz (6.667 ns)
- Original AES RTL: D:\git\vivado_25.2_win\aes\AES_GCM_TX_PL_DIRECT_260811_1826\vivado\rtl\aes256_gcm
- Post-route timing evidence: D:\git\vivado_25.2_win\aes\AES_GCM_TX_PL_DIRECT_260811_1826\vivado\artifacts\timing_summary.rpt (WNS 0.095 ns, all constraints met)

## Main results

| Condition | Pure C total (ms) | FPGA total (ms) | Pure C (ns/block) | FPGA (ns/block) | Pure C (Gbps) | FPGA (Gbps) | FPGA speedup |
|---|---:|---:|---:|---:|---:|---:|---:|
| Key expansion included | 6.202400 | 2.799993 | 620.240 | 279.999 | 0.206372 | 0.457144 | 2.215x |
| Key expansion excluded | 2.344200 | 0.999993 | 234.420 | 99.999 | 0.546028 | 1.280009 | 2.344x |

FPGA speedup is pure-C total time divided by FPGA total time. A value above 1 means the FPGA is faster.

## Correctness

| Comparison | Key expansion included | Key expansion excluded |
|---|---:|---:|
| Pure C versus OpenSSL | 10000/10000 | 10000/10000 |
| FPGA RTL versus OpenSSL | 10000/10000 | 10000/10000 |

- FIPS-197 AES-256 single-block KAT: PASS in OpenSSL, pure C, and FPGA RTL
- Forbidden CPU instructions: 0 AESENC/AESDEC/AESKEYGENASSIST/VAES/PCLMUL-family instructions
- Pure-C build: compiler auto-vectorization and AES/CLMUL/AVX/AVX2 disabled

## FPGA cycle measurements

| Condition | Total cycles for 10,000 blocks | Continuous cycles/block | Single-operation latency |
|---|---:|---:|---:|
| Key expansion included | 419999 | 41.9999 | 41 cycles (key 27 + block 14) |
| Key expansion excluded | 149999 | 14.9999 | 14 cycles |

Total time and throughput use the measured cycle count from continuous valid/ready traffic.

## Scope and fairness

- Both sides process the same 10,000 AES-256 ECB single-block records.
- Included mode expands a distinct 256-bit key for every record and encrypts one block.
- Excluded mode expands or loads the same fixed key once before timing and encrypts 10,000 blocks.
- File I/O, vector generation, OpenSSL, compilation, RTL elaboration, and simulator wall time are not timed.
- OpenSSL creates expected ciphertext and runs KATs only; its speed is not part of the comparison.
- FPGA time converts RTL handshake cycles using the original implemented design post-route 150 MHz clock.
- C time is the median of 11 runs of 10,000 blocks after warm-up, pinned to CPU 0.
