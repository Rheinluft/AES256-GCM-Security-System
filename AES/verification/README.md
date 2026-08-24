# Verification

AES-256 block core의 표준 벡터부터 TX packet 생성, RX authenticate-before-release, 실제 TX 출력의 RX handoff와 Jetson/PC 상태 계약까지 단계별로 검증합니다. 각 단계는 앞 단계의 결과를 재사용하지만 판정 기준은 독립적으로 둡니다.

![AES 코어·TX·RX 단계별 검증 구성](../assets/verification_overview.png)

## 검증 전략

```text
NIST AESAVS
  -> AES-256 core / key expansion 정답성
OpenSSL + scalar C
  -> 10,000 block 결과와 RTL 성능 비교
TX UVM
  -> AAD/ciphertext/TAG/protocol/backpressure
  -> verified 1280-packet handoff record 생성
RX UVM
  -> plaintext/zero substitution/error flags/coverage
TX -> RX loopback
  -> TX RTL이 만든 실제 record를 RX가 정확히 처리하는지
Session host tests
  -> key capsule과 재부팅·응답 유실·Wi-Fi 복구
Jetson/PC tests
  -> 공격 lifecycle과 화면이 실제 backend 상태를 왜곡하지 않는지
```

| 계층 | DUT / 범위 | 독립 기준 | 보관된 최종 결과 |
|---|---|---|---|
| [`nist_kat`](nist_kat/README.md) | AES-256 ECB core와 key expansion | NIST AESAVS `.rsp` | 405/405, 0 fail |
| [`aes256_c_vs_fpga`](aes256_c_vs_fpga/README.md) | scalar C와 FPGA AES core | OpenSSL AES-256 golden | C/RTL 각각 10,000/10,000 일치 |
| [`tx_uvm`](tx_uvm/README.md) | `video_aes_gcm_tx_top` | C/OpenSSL packet golden | 1280 packet, mismatch/protocol error 0 |
| [`rx_uvm`](rx_uvm/) | RX authentication/decryption과 5종 detector | golden plaintext + scenario error signature | 10개 scenario regression PASS |
| [`tx_rx_loopback`](tx_rx_loopback/) | TX record에서 RX plaintext까지 | TX UVM handoff + RX golden | 8/16/1280 packet handoff PASS |
| [`fpga/session_control`](../fpga/session_control/) | ECDH/capsule/session state | host mock와 persistent state assertions | crypto/recovery/supervision PASS |
| [`jetson/dashboard/tests`](../jetson/dashboard/tests/) | 공격·Weak-Key·telemetry backend | Python unittest | 19 tests PASS |
| Jetson UI | 표시·animation 계약 | Node test runner | 8 tests PASS |
| PC UI/backend | evidence·timeline·OCC gate·UART contract | Node tests + Python self-test | UI 7 tests, self-test PASS |

## 1. NIST AES-256 Known Answer Test

### 대상

- `aes256_iterative_core`
- `aes256_key_expansion`
- AES round/S-box/key schedule 하위 모듈

### 입력

NIST CAVP AESAVS의 ECB-256 `[ENCRYPT]` vector 4종을 변환 없이 직접 읽습니다.

| Vector file | 개수 | 자극 목적 |
|---|---:|---|
| `ECBGFSbox256.rsp` | 5 | zero key에서 S-box 기본 경로 |
| `ECBKeySbox256.rsp` | 16 | zero plaintext에서 key schedule 경로 |
| `ECBVarKey256.rsp` | 256 | key 256 bit를 하나씩 변화시켜 모든 key bit 반영 확인 |
| `ECBVarTxt256.rsp` | 128 | plaintext 128 bit를 하나씩 변화시켜 모든 data bit 반영 확인 |
| 합계 | 405 | AES core와 key expansion 전체 경로 |

### 판정

TB는 `KEY`, `PLAINTEXT`, `CIPHERTEXT`를 읽고 DUT `done` clock의 `data_out`을 NIST ciphertext와 128 bit 전체 비교합니다. 하나라도 다르면 해당 vector의 key/plaintext/expected/got을 출력합니다. 기대 ciphertext 한 글자를 바꾸는 역검증으로 TB가 실제 mismatch를 잡는 것도 확인했습니다.

### 실행

Synopsys VCS:

```bash
cd AES/verification/nist_kat/uvm_verification
make sim
```

Vivado xsim:

```powershell
cd AES\verification\nist_kat\uvm_verification
.\sim\run_aes_core_kat.ps1
```

xsim 일부 버전은 `$fatal` 뒤에도 process exit code 0을 반환할 수 있으므로 launcher는 로그의 `RESULT : PASS`를 직접 검사합니다.

### 통과가 의미하는 것

AES-256 ECB encryption과 key expansion이 표준 vector에 맞는다는 뜻입니다. GHASH, GCM nonce/AAD 조립, AXI protocol은 이 테스트 범위가 아니며 TX UVM에서 별도로 검증합니다.

## 2. Scalar C / OpenSSL / RTL 비교

### 목적

정답 검증과 성능 비교의 기준을 분리합니다. OpenSSL은 신뢰할 수 있는 정답 생성기로만 사용하고, 성능은 CPU AES 전용 명령을 쓰지 않는 scalar C와 150 MHz RTL cycle 수를 비교합니다.

### 시험 절차

1. OpenSSL로 서로 다른 key/plaintext 10,000쌍의 golden ciphertext를 생성합니다.
2. `test_aes256.c`가 FIPS-style known-answer와 C core 기본 동작을 확인합니다.
3. scalar C를 `-mno-aes -mno-pclmul -mno-avx -mno-avx2`와 vectorization 비활성화 옵션으로 빌드합니다.
4. `objdump`에서 AES-NI, VAES, PCLMUL 등 금지 명령이 없는지 검사합니다.
5. C가 10,000개 ciphertext를 golden과 비교합니다.
6. 같은 vector를 RTL TB에 공급하고 10,000개 결과를 비교합니다.
7. key expansion 포함/제외 두 조건을 warm-up 뒤 11회 실행하고 중앙값을 사용합니다.
8. RTL source의 SHA-256 manifest가 운영 TX AES source와 같은지 확인합니다.

### 합격 조건

- C ciphertext mismatch = 0
- RTL ciphertext mismatch = 0
- vector file count/record width와 key/plaintext 대응이 정확함
- scalar C binary에 금지 명령이 없음
- RTL provenance hash가 manifest와 일치함

### 보관 결과

| 조건 | scalar C | FPGA 150 MHz 환산 | 비교 |
|---|---:|---:|---:|
| key expansion 포함 | 6.2024 ms | 2.799993 ms | FPGA 2.215× |
| key expansion 제외 | 2.3442 ms | 0.999993 ms | FPGA 2.344× |

```powershell
cd AES\verification\aes256_c_vs_fpga
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_all.ps1
```

## 3. TX AES-256-GCM UVM

### 대상과 입력

`video_aes_gcm_tx_top`에 한 frame에 해당하는 1280개 plaintext packet을 입력합니다. packet마다 payload 1440 B, AAD 16 B와 TAG 16 B를 사용합니다.

```text
session_id = 0x00000001
frame_id   = 0x00000000
packet_id  = 0..1279
nonce      = session_id || frame_id || 16'h0000 || packet_id
```

### Scoreboard 비교

packet마다 다음 세 그룹을 독립 비교하므로 full frame에서 총 3,840개 comparison group이 생깁니다.

1. RTL ciphertext 1440 B ↔ C/OpenSSL golden ciphertext
2. RTL AAD 16 B ↔ 기대 protocol metadata
3. RTL TAG 16 B ↔ golden authentication tag

Scoreboard는 packet 수뿐 아니라 byte mismatch 수를 별도로 집계합니다. 모든 그룹이 통과하고 UVM error/fatal이 0일 때만 RX handoff 파일을 생성합니다.

### Test cases

| Test | 자극 | 추가 판정 |
|---|---|---|
| `tx_gcm_full_frame_test` | 1280개 packet 연속 입력 | timeout 없음, `protocol_error=0`, 마지막 상태 `frame_id=1`, `packet_index=0` |
| `tx_gcm_stall_test` | ciphertext와 metadata output에 독립 bounded random stall | stall이 실제 발생해야 하며 stall 중 data/TLAST/metadata stability error = 0 |

### 합격 조건

- ciphertext/AAD/TAG packet 각각 1280/1280
- 세 영역 byte mismatch = 0
- full-frame timeout과 DUT `protocol_error` 없음
- output stall 중 `TVALID && !TREADY`인 beat의 값이 변하지 않음
- busy 종료 뒤 frame/packet status가 다음 frame 경계와 일치

### RX handoff 산출물

PASS일 때만 다음 binary를 만듭니다.

```text
tx_rtl_records_1280.bin = 1280 × (AAD[16] || Ciphertext[1440] || TAG[16])
plaintext_1280.bin      = RX가 복원해야 하는 1280 × 1440 B
key.bin / iv_1280.bin  = key와 nonce reference
```

이 파일들은 이후 RX test가 자체 생성한 “가짜 ciphertext”가 아니라 실제 TX RTL output을 사용하도록 연결합니다.

## 4. RX authentication UVM

### Scoreboard의 세 가지 동시 판정

RX UVM은 영상이 나오는지만 확인하지 않습니다.

1. **정상 packet:** output 1440 B가 golden plaintext와 byte 단위로 같아야 합니다.
2. **거부 packet:** output 1440 B 전체가 0이어야 합니다. non-zero byte 하나라도 있으면 `PLAINTEXT LEAK`입니다.
3. **오류 문맥:** TAG/REPLAY/SEQUENCE/SESSION/TIMEOUT flag별 실제 발생 횟수가 test가 선언한 기대 횟수와 같아야 합니다.

따라서 공격 packet이 우연히 화면에서 안 보이더라도 잘못된 error code를 내거나 평문의 일부를 흘리면 실패합니다.

### 10개 regression scenario

| # | Test / packet 수 | 실제 자극 | 기대 판정 |
|---:|---|---|---|
| 1 | `rx_normal_test`, 8 | golden record 0..7 순서 입력 | 8 plaintext match, error 0 |
| 2 | `rx_tag_tamper_test`, 8 | packet 1의 TAG bit 0 반전 | TAG 1회, victim payload 전체 zero |
| 3 | `rx_cipher_tamper_test`, 8 | packet 1의 ciphertext bit 0 반전 | TAG 1회, victim payload 전체 zero |
| 4 | `rx_recovery_test`, 8 | pkt 1 TAG 변조, pkt 3 payload 중간 bit 변조, 사이 정상 packet | TAG 2회, 두 victim zero, pkt 2/4부터 정상 plaintext 복구 |
| 5 | `rx_replay_test`, 8 | 정상 0..7 승인 후 pristine packet 1 재전송 | REPLAY 1 + SEQUENCE 1; priority code는 REPLAY |
| 6 | `rx_sequence_test`, 8 | 0, 1 다음 2..4를 건너뛰고 5 입력 | SEQUENCE 1, gap packet 차단 |
| 7 | `rx_session_test`, 16 | rekey grace 이후 packet 13 AAD session을 `0xDEADBEEF`로 변경 | SESSION 1, foreign-session packet 차단 |
| 8 | `rx_timeout_test`, 8 | packet 0,1 뒤 45,000 clock idle | 150 MHz에서 200 µs 한계를 넘겨 TIMEOUT 1 |
| 9 | `rx_normal_test`, 8, `STALL=25` | 정상 입력에 25% AXI backpressure | plaintext/error 판정 유지, handshake 안정성 |
| 10 | `rx_normal_test`, 1280 | 한 frame 전체 정상 handoff | 1280 plaintext match, error 0, full-frame 처리 |

Replay packet은 cryptographically valid하므로 먼저 정상 승인된 pristine record를 다시 보냅니다. 변조되어 인증 실패한 packet은 replay bitmap에 들어가지 않는다는 조건까지 반영한 자극입니다.

### Coverage

regression build는 line/condition/FSM/toggle/branch code coverage를 수집하고, functional covergroup은 5개 error code와 각 flag hit를 별도 bin으로 기록합니다. `urg` merge report는 생성물이므로 Git에는 포함하지 않습니다.

```bash
cd AES/verification/rx_uvm/sim
./run_regression.sh
FULL=1 ./run_regression.sh
```

개별 test는 다음 형식입니다.

```bash
./run_uvm.sh rx_recovery_test 8 0
./run_uvm.sh rx_normal_test 1280 20
```

## 5. TX → RX loopback / handoff

[`tx_rx_loopback`](tx_rx_loopback/)은 RX test용 record가 TX와 무관하게 생성되는 것을 막습니다.

### 절차

1. TX UVM PASS 결과인 `tx_rtl_records_1280.bin`을 읽습니다.
2. `verify_tx_handoff.py`가 record 크기, AAD/session/frame/packet ordering과 file 구성을 확인합니다.
3. `pack_tx_vectors.py`가 같은 원본에서 8/16/1280 packet subset을 만듭니다.
4. RX RTL/UVM에 실제 TX AAD+ciphertext+TAG를 입력합니다.
5. 정상 packet은 TX plaintext와 일치하고 공격 scenario는 RX의 zero/error signature를 만족해야 합니다.

이 검증은 TX와 RX가 각각 자기 golden에만 맞고 서로는 byte ordering이나 nonce 조립이 다른 통합 오류를 잡습니다.

```bash
cd AES/verification/tx_rx_loopback/sim
./run_regression.sh
```

## 6. Session-control host tests

### `test_ecdh_session_crypto.c`

- Alice/Bob 양방향 X25519 shared secret 일치
- HKDF-SHA256으로 유도한 wrapping key와 AES-256-GCM capsule 복호
- pinned peer가 다른 경우 거부
- capsule salt/ciphertext 변조 거부
- 같은 secret도 fresh wrapping을 사용해 동일 capsule을 반복하지 않음
- encode/decode 뒤 session ID/key/counter 일치와 sensitive buffer clear

### `test_session_recovery.sh`

production localhost protocol과 임시 persistent state를 사용해 다음 fault를 주입합니다.

- 첫 DONE 유실 시 새 key를 만들지 않고 같은 capsule로 재시도
- Weak Demo KDF와 Jetson management request의 엄격한 parsing
- 고정 peer 없이 RX announcement로 현재 DHCP 주소 발견
- exchange error 중 termination event 보존과 PL update gate
- RX가 PL commit 뒤 crash한 경우 PENDING write-ahead record를 ACTIVE로 승격
- remote DONE 직후 local cancel race에서 candidate를 TERMINATED 처리
- 짧은 press/release도 level이 아니라 termination counter로 검출
- TERMINATE 응답 유실 뒤 RX restart가 duplicate 요청을 인증
- button release 뒤 old TERMINATED session에 막히지 않고 새 session으로 rekey
- TX agent restart가 keyless teardown credential을 복구해 양쪽 key를 지우고 이후 rekey

### supervision tests

| Script | 검사 내용 |
|---|---|
| `test_init_supervision.sh` | TX/RX agent crash 시 restart, Wi-Fi ifindex 변경 감지, clean stop/restart 뒤 supervisor 단일성 |
| `test_wifi_recovery.sh` | stale/disabled WPA 교체, TX/RX role 유지, USB recovery hook, wired/virtual NIC 배제 |

## 7. Jetson backend tests — 19개

| 영역 | Test 수 | 구체적으로 확인하는 것 |
|---|---:|---|
| Attack status contract | 3 | Tamper가 attacker가 아는 field만 노출, Replay injection 전 결과 미생성, stop 뒤 마지막 실제 결과 유지 |
| Traffic metrics | 3 | deterministic stride sample이 전체 stream을 대표, 30초 drop delta가 실제 counter 차이, bridge 방향을 rate로 탐색 |
| Weak-Key prepare/recovery | 7 | timeout retry의 동일 request ID, matching session capture 대기, 64-bit ID 전달, secure/reset/stop 경쟁 직렬화, stale search snapshot 차단 |
| Packet metadata | 2 | 마지막 실제 record 선택, IAT jitter를 packet timestamp 표준편차로 계산 |
| VLM gate | 3 | 현재 verified image 허용, searching state 거부, 다른 run/image identity 거부 |
| Search graph origin | 1 | 새 search history가 이전 run 값을 물려받지 않고 0에서 시작 |

```bash
cd AES/jetson/dashboard
python3 -m unittest discover -s tests -p 'test_*.py'
```

## 8. Jetson UI tests — 8개

- key found label이 실제 bit width, CPU/CUDA profile과 elapsed time을 표시
- comparison graph의 y축 단위가 시간이 아니라 tested keys임을 명시
- Weak prepare pipeline이 backend에서 관찰된 event만 단계로 표시
- Replay가 capture → store → re-inject 세 단계를 모두 노출
- Replay 세 단계 animation이 중첩되지 않고 순차 동기화
- packet storage bay가 label과 겹치지 않는 layout 유지
- Tamper marker가 ciphertext 변경을 알아볼 수 있는 크기인지
- 커진 marker가 이동 packet 영역을 침범하지 않는지

```bash
cd AES/jetson/dashboard/dashboard-source
npm ci
npm test
```

## 9. PC UI/backend tests

### UI 7개

| Test file | 확인 내용 |
|---|---|
| `attack-timeline-and-occ-gate` | fresh OCC PASS 또는 QWE만 unlock, 최근 공격으로 timeline focus |
| `timeline-attack-lifecycle` | running gap, stop과 heartbeat recovery가 잘못 합쳐지지 않음 |
| `event-log-aggregation` | 같은 session의 반복 event를 의미 단위로 집계 |
| `video-frame-monitor` | carrier FPS가 아니라 실제 frame 변화로 liveness 판정 |
| `pc-ui-design-merge` | production UI drawer와 실제 backend API field 계약 |
| `ai-evidence-lifecycle` | AI 답변, evidence snapshot과 자동 focus의 수명주기 |
| `gemini-timeout-diagnostics` | timeout/error가 빈 정상 응답으로 숨지 않고 진단 정보 유지 |

### Backend self-test

`server.py --self-test`는 RX UART frame/CRC/role parsing, OCC lock 전이와 격리된 Jetson attack-status contract를 외부 장비 없이 검사합니다.

```powershell
cd AES\pc\dashboard
py -3 .\server.py --self-test
node --test .\web\tests\*.test.js
```

## 결과를 해석할 때의 제한

- NIST KAT PASS는 AES block core 정답성을 의미하며 GCM protocol 전체를 대신하지 않습니다.
- UVM PASS는 사용한 RTL과 scenario에 대한 결과이며 실제 board timing closure, cable 품질과 OS driver를 대신하지 않습니다.
- 화면 테스트는 UI가 backend evidence를 정확히 표현하는지 확인하며 실제 packet 공격 성공을 대신하지 않습니다.
- Weak-Key search 성공은 의도적으로 축소한 demo key space의 결과이며 AES-256 brute-force 가능성을 뜻하지 않습니다.
- 실제 board 검증에서는 Vivado timing/DRC, JTAG/SD boot, 약 30 fps content와 RX detector/UART를 별도 확인해야 합니다.

## 기준 소스와 중복 관리

운영 FPGA 정본은 [`../fpga/tx/vivado/rtl`](../fpga/tx/vivado/rtl)과 [`../fpga/rx/vivado/rtl`](../fpga/rx/vivado/rtl)입니다. 검증 폴더의 RTL 복사본은 기존 filelist와 handoff를 그대로 재현하기 위해 유지합니다.

새 기능을 수정할 때는 다음 순서를 따릅니다.

1. 운영 RTL을 먼저 수정합니다.
2. 관련 unit/UVM test와 golden 생성 절차를 갱신합니다.
3. 검증 복사본의 SHA-256 동일성을 확인합니다.
4. TX handoff를 다시 만든 뒤 RX/loopback regression을 실행합니다.
5. 최종 결과 숫자와 README를 함께 갱신합니다.

NIST KAT 소스는 기존 archive에서 `uvm_verification/`만 풀어 넣었고, simulator binary, coverage DB와 원시 log는 저장소에서 제외했습니다.
