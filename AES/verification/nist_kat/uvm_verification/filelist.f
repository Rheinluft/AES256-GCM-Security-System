// AES-256 KAT : 패키지를 먼저 둔다.  aes_subbytes / aes_subword32 는 module
// 선언 밖(compilation-unit 스코프)에서 import 하므로 순서가 바뀌면 컴파일이
// 깨진다.  Vivado xsim 런처(sim/run_aes_core_kat.ps1)도 이 파일을 읽는다.

./aes256_gcm/aes_sbox_pkg.sv
./aes256_gcm/aes_key_rcon_pkg.sv

./aes256_gcm/aes_addroundkey.sv
./aes256_gcm/aes_shiftrows.sv
./aes256_gcm/aes_mixcolumns.sv
./aes256_gcm/aes_subbytes.sv
./aes256_gcm/aes_subword32.sv
./aes256_gcm/aes_round.sv
./aes256_gcm/aes_next_round_key.sv
./aes256_gcm/aes256_key_transform.sv
./aes256_gcm/aes256_key_expansion.sv
./aes256_gcm/aes256_iterative_core.sv

./tb/tb_aes256_core_kat.sv
