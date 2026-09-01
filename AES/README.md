# AES-256-GCM Secure Video Pipeline

Pcam 영상이 DDR에 평문으로 기록되기 전에 Zybo TX의 PL에서 암호화되고, Jetson 중간 노드를 거쳐 Zybo RX에서 인증·복호화되는 종단간 영상 보안 데모입니다. Jetson은 정상 트래픽 관찰과 공격 시연을 담당하고, RX와 PC 콘솔은 공격 탐지 결과와 복호 영상을 보여줍니다.

설계 바로가기: [최종 RTL 계층](#rtl-모듈-계층과-자원-역할) · [packet/AAD/nonce](#packet-aad와-nonce-구조) · [GCM 계산](#gcm-계산-문맥) · [TX 처리](#tx-처리-순서-평문이-ddr에-도달하기-전-암호화) · [RX 인증 후 방출](#rx-처리-순서-authenticate-before-release) · [독립형 코어와 비교](#통합-코어와-독립형-참고-코어)

## 설계 목표와 핵심 결정

| 목표 | 설계 결정 | 이유 |
|---|---|---|
| 카메라 평문 노출 최소화 | TX PL에서 AES-GCM을 수행한 뒤 ciphertext만 frame buffer/DDR 경로로 전달 | PS software나 DDR dump에서 원본 영상이 노출되는 구형 구조를 피함 |
| 인증 전 plaintext 차단 | RX가 TAG와 header/freshness를 모두 판정한 뒤에만 plaintext를 승인 | 변조 packet의 일부 평문이 먼저 출력되는 early-release 문제 방지 |
| 공격 노드와 보안 종단 분리 | Jetson은 key를 갖지 않는 2-NIC bridge/attacker, 암복호화는 Zybo TX/RX에서 수행 | 중간 노드가 침해되거나 악의적으로 동작해도 GCM 종단 보안 확인 가능 |
| 데이터·제어 plane 분리 | 영상은 유선 UDP, key/session은 별도 USB Wi-Fi 채널 | 영상 bridge 조작과 session 협상을 분리하고 장애 원인을 구분 |
| 재현 가능한 공격 | Tamper, Replay, Weak Session을 명시적 상태 기계와 API로 제어 | 데모 화면의 애니메이션이 아니라 실제 packet 조작 결과를 반복 검증 |
| 여러 계층의 증거 연결 | Jetson 공격 상태 + RX detector/UART + PC event timeline | “공격 버튼을 눌렀다”와 “수신단이 차단했다”를 별도 증거로 확인 |

## 위협 모델과 신뢰 경계

- Jetson과 TX–RX 사이의 Ethernet 구간은 관찰·변조·삭제·지연·재전송이 가능한 비신뢰 구간으로 봅니다.
- AES key와 session 상태를 보유하는 신뢰 종단은 Zybo TX/RX입니다. Jetson은 정상 secure session의 key를 받지 않습니다.
- 공격자가 유효한 packet을 그대로 복사하더라도 RX의 replay/sequence/session 문맥을 통과해야 합니다.
- Weak Session은 key space 축소의 위험을 보여주기 위한 교육용 모드이며 정상 운용 보안 수준을 나타내지 않습니다.
- 이 데모는 FPGA endpoint 자체 탈취, side-channel, secure boot/bitstream 암호화와 생산 환경의 HSM key 보관까지 해결하는 시스템은 아닙니다.

![AES-256-GCM 영상 보안 데모 전체 구성](assets/system_overview.png)

## 데이터 흐름

```text
Pcam
  │ 1280×720 YUYV
  v
Zybo Z7-20 TX
  PL pack128 -> AES-256-GCM -> UDP video packet
  │
  │ AAD 16 B + Ciphertext 1440 B + TAG 16 B
  v
Jetson Orin Nano (2-NIC transparent bridge)
  ├─ packet metadata / entropy / throughput observation
  ├─ ciphertext tamper
  ├─ authenticated packet replay
  └─ weak-session key search + recovered frame VLM analysis
  │
  v
Zybo Z7-20 RX
  PL authentication -> replay/sequence/session/timeout checks -> decrypt
  ├─ HDMI 720p60 carrier, content 약 30 fps
  └─ UART security telemetry
  │
  v
PC Receiver Console
  live video + attack state + detector counters + event timeline
```

세션 키는 별도 Wi-Fi 제어 채널에서 X25519 static-static ECDH와 HKDF-SHA256으로 유도하고, 인증된 AES-GCM session capsule을 통해 TX/RX에 적용합니다. 영상 경로의 Jetson은 L2 bridge로 동작하므로 정상 모드에서는 암호화 패킷을 수정하지 않습니다.

## 최종 AES-256-GCM 상세 설계

이 절은 현재 TX/RX에 통합된 RTL을 기준으로 암호 코어, packet 형식과 인증 실패 동작을 연결해 설명합니다. 공통 상수와 필드 조합은 [`gcm_protocol_pkg.sv`](fpga/tx/vivado/rtl/aes256_gcm/gcm_protocol_pkg.sv)에 정의되어 있습니다.

### RTL 모듈 계층과 자원 역할

```text
TX axis_gcm_tx_frame_processor
└─ video_aes_gcm_tx_top
   ├─ aes256_key_expansion       : 256-bit key -> RK0 ... RK14
   ├─ aes256_iterative_core × 2  : payload CTR / H·TAG mask 계산
   └─ ghash_mul16                : AAD·ciphertext·length 인증 누산

RX axis_gcm_rx_frame_processor
├─ video_aes_gcm_rx_top
│  ├─ aes256_key_expansion
│  ├─ aes256_iterative_core × 2
│  ├─ ghash_mul16
│  └─ packet_buffer_bram         : 90-block packet bank × 2
└─ gcm_rx_error_detector         : TAG/REPLAY/SEQUENCE/SESSION/TIMEOUT
```

| 블록 | 구현 방식 | 최종 설계에서의 역할 |
|---|---|---|
| [`aes256_key_expansion`](fpga/tx/vivado/rtl/aes256_gcm/aes256_key_expansion.sv) | AES-256의 15개 round key `RK0`~`RK14`를 외부 확장 | data/auxiliary AES가 같은 session key schedule을 공유 |
| [`aes256_iterative_core`](fpga/tx/vivado/rtl/aes256_gcm/aes256_iterative_core.sv) | 128-bit state에 한 clock당 한 round를 적용하는 14-round iterative core | data core는 CTR keystream, auxiliary core는 `H`와 `E_K(J0)` 계산 |
| [`ghash_mul16`](fpga/tx/vivado/rtl/aes256_gcm/ghash_mul16.sv) | 8 multiplier bits/clock, 한 번의 GF(2¹²⁸) 곱셈에 16 clocks | AAD, 90개 ciphertext block과 length block을 순서대로 인증 |
| [`packet_buffer_bram`](fpga/rx/vivado/rtl/aes256_gcm/packet_buffer_bram.sv) | 180 × 128-bit simple dual-port RAM | 90-block bank 두 개로 인증 중인 packet과 출력 packet을 분리 |

키가 commit되면 round key를 만들고 `H = AES_K(0¹²⁸)`를 한 번 계산합니다. 이후 packet마다 두 AES 자원을 병렬로 사용해 payload counter keystream과 TAG mask를 준비합니다.

### Packet, AAD와 nonce 구조

한 영상 frame은 1,280개 packet으로 나뉘며 packet index는 `0`~`1279`입니다. UDP payload는 1,472바이트이고 IPv4 20바이트와 UDP 8바이트를 더하면 표준 MTU인 1,500바이트가 됩니다.

| UDP payload byte | 크기 | 필드 | 인증/암호화 |
|---:|---:|---|---|
| `0..3` | 4 B | Magic `0x5043414D` (`PCAM`) | AAD로 인증, 평문 전송 |
| `4..7` | 4 B | `session_id` | AAD로 인증, 평문 전송 |
| `8..11` | 4 B | `frame_id` | AAD로 인증, 평문 전송 |
| `12..13` | 2 B | `packet_index` | AAD로 인증, 평문 전송 |
| `14..15` | 2 B | `flags` | AAD로 인증, 평문 전송 |
| `16..1455` | 1,440 B | 영상 payload, 128-bit block × 90 | AES-CTR 암호화 + GHASH 인증 |
| `1456..1471` | 16 B | GCM authentication tag | 수신 TAG 비교 |

모든 다중 바이트 필드는 network byte order(big-endian)입니다. 첫 16바이트는 별도 비밀 데이터가 아니라 packet을 영상·세션 문맥에 묶는 AAD입니다.

```text
AAD   = magic || session_id || frame_id || packet_index || flags
nonce = session_id[31:0] || frame_id[31:0] || 16'h0000 || packet_index[15:0]
```

| `flags` bit | 의미 | 유효 조건 |
|---|---|---|
| `[15:12]` | protocol version | 현재 `1` |
| `[11:3]` | reserved | 모두 `0` |
| `[2]` | EOF | packet `1279`에서만 `1` |
| `[1]` | SOF | packet `0`에서만 `1` |
| `[0]` | encrypted | AES-GCM mode이면 `1` |

96-bit nonce는 전송하지 않고 양쪽이 AAD의 session/frame/packet 문맥으로 동일하게 재구성합니다. 정상 session에서 세 값의 조합이 packet마다 달라지므로 같은 key 아래 counter block이 재사용되지 않습니다.

### GCM 계산 문맥

NIST GCM 표기와 RTL의 계산 관계는 다음과 같습니다.

```text
H       = AES_K(0^128)
J0      = nonce || 32'd1
CTR_i   = nonce || BE32(i + 2),  i = 0 ... 89
C_i     = P_i XOR AES_K(CTR_i)
S       = GHASH_H(AAD, C_0 ... C_89, [128]_64 || [11520]_64)
TAG     = AES_K(J0) XOR S
```

마지막 GHASH 입력의 `128`과 `11520`은 각각 AAD와 ciphertext의 bit 길이입니다. TAG는 128비트를 잘라 쓰지 않고 전체 비교합니다. AXI byte lane 0과 GCM의 최상위 byte 표기 차이는 protocol package의 byte-reversal 함수로 경계에서만 변환합니다.

### TX 처리 순서: 평문이 DDR에 도달하기 전 암호화

```text
Pcam MIPI -> YUYV16 -> 128-bit packer
  -> AAD/nonce 생성
  -> {E_K(J0), E_K(CTR_0), GHASH(AAD)} 병렬 준비
  -> 90회: plaintext XOR keystream -> ciphertext, GHASH(ciphertext)
  -> GHASH(length) -> TAG 생성
  -> ciphertext + {AAD, TAG} record writer
  -> Video Frame Buffer Write / DDR -> PS UDP sender
```

[`video_aes_gcm_tx_top.sv`](fpga/tx/vivado/rtl/aes256_gcm/video_aes_gcm_tx_top.sv)은 packet 시작 시 auxiliary AES로 `E_K(J0)`, data AES로 첫 counter keystream, GHASH로 AAD 인증을 동시에 시작합니다. 각 plaintext block을 받아 ciphertext를 출력하면서 다음 counter를 미리 계산하고, 90번째 block 뒤에 length block을 누산해 TAG를 확정합니다. 따라서 원본 영상은 TX의 frame buffer/DDR 앞에서 이미 암호문으로 바뀝니다.

Ciphertext와 AAD/TAG metadata는 독립 AXI channel이지만 하나의 packet commit으로 묶입니다. backpressure가 걸린 동안에는 `TVALID`가 유지되는 data와 metadata가 변하지 않도록 출력 register가 값을 보존합니다.

### RX 처리 순서: authenticate-before-release

```text
AAD 1 beat -> header/session/flags 검사 + nonce 재구성
  -> 90회: GHASH(ciphertext) + plaintext 임시 복호
  -> plaintext를 write bank에 보관, 외부 출력은 아직 금지
  -> GHASH(length) -> 수신 TAG 128-bit 비교
  -> PASS: 저장된 plaintext 90 blocks 방출
     FAIL: 같은 길이의 zero 90 blocks 방출
```

[`video_aes_gcm_rx_top.sv`](fpga/rx/vivado/rtl/aes256_gcm/video_aes_gcm_rx_top.sv)은 첫 128-bit beat에서 AAD를 파싱하고 magic, active session, packet index, version/reserved bit와 SOF/EOF 일관성을 검사합니다. 이어지는 90개 ciphertext block은 GHASH에 넣는 동시에 CTR로 복호화하지만, 그 결과를 바로 외부로 내보내지 않고 ping-pong packet buffer의 write bank에 저장합니다.

마지막 TAG beat에서 header·stream 형식과 `received_tag == E_K(J0) XOR GHASH`를 모두 판정한 뒤 bank를 commit합니다. 성공한 bank만 plaintext를 내보내며, TAG·header·형식 중 하나라도 실패하면 해당 bank를 zero-output으로 표시해 90개의 0 block을 방출합니다. 이렇게 downstream video 길이와 timing은 유지하면서 인증되지 않은 평문이 먼저 노출되는 early-release를 차단합니다.

RX record의 AXI 입력은 `AAD 1 + ciphertext 90 + TAG 1 = 92`개의 128-bit transfer입니다. 모든 transfer의 `TKEEP`은 `16'hFFFF`이고, `TLAST`는 frame의 마지막 packet인 index `1279`의 TAG에서만 올라옵니다.

[`gcm_rx_error_detector.sv`](fpga/rx/vivado/rtl/rx/gcm_rx_error_detector.sv)는 stream을 바꾸지 않는 입력 tap으로 다음 이벤트를 별도 sticky bit·counter·last context에 기록합니다.

| Detector | 발생 조건 | 데모에서 보이는 의미 |
|---|---|---|
| TAG | ciphertext 또는 TAG 변경으로 GCM 인증 불일치 | 전송 중 bit 변조가 cryptographic integrity에서 차단됨 |
| REPLAY | 이미 인증되어 replay bitmap에 기록된 packet index 재등장 | 과거의 정상 packet도 다시 사용할 수 없음 |
| SEQUENCE | 같은 frame/session에서 예상 다음 packet index가 아님 | packet 누락·점프·역순을 freshness 문맥으로 검출 |
| SESSION | rekey grace window 이후 AAD session ID가 active session과 다름 | 다른 session의 packet 혼입 차단 |
| TIMEOUT | active stream이 설정된 idle 한계를 초과 | cable/flow 중단과 장시간 packet 공백 가시화 |

### Session control: key 합의와 원자적 활성화

TX와 RX는 pinned peer public key를 사용한 X25519 ECDH로 shared secret을 만들고 HKDF-SHA256으로 wrapping key를 유도합니다. 실제 AES video key, session ID와 counter는 AES-GCM capsule로 전달합니다.

```text
TX candidate 생성
  -> authenticated capsule
  -> RX durable PENDING
  -> RX PL key commit
  -> RX ACTIVE / DONE
  -> TX active session 확정
```

READY/COMMIT/DONE 단계와 durable state를 분리해 응답 유실이나 RX 재부팅이 발생해도 같은 capsule을 재시도할 수 있습니다. termination과 rekey도 event counter와 현재 PL session을 대조하므로 오래된 응답이 새 session을 덮지 않도록 설계했습니다.

### Jetson: 관찰자와 공격자

Jetson의 `br-video`는 두 유선 NIC를 잇고 packet parser가 UDP 5602 traffic에서 session/frame/packet metadata, entropy, IAT jitter, throughput과 NIC drop을 계산합니다. 공격 엔진은 UI 상태만 바꾸는 mock이 아니라 실제 traffic path를 조작합니다.

- Tamper: 선택 비율의 packet에서 ciphertext bit를 변경하고 원래 TAG는 유지합니다.
- Replay: 정상 record를 capture·저장한 뒤 frame 경계에 맞춰 재주입합니다.
- Weak-Key: TX에 명시적 Weak Session을 요청하고 관찰 record의 TAG가 맞는 후보만 정답으로 인정합니다.
- VLM: 완료된 search run과 SHA-256 identity가 일치하는 recovered frame만 로컬 분석 서비스에 전달합니다.

### PC: 서로 다른 증거의 합성

PC backend는 RX HDMI 영상, RX UART telemetry와 Jetson `/api/attack/status`를 수집합니다. UI는 공격 명령을 성공으로 간주하지 않고, Jetson의 실제 phase와 RX detector counter 증가를 구분해 event timeline에 기록합니다. OCC `PASS` 또는 명시적 개발 해제만 live receiver gate를 열 수 있습니다.

## 하드웨어 구성

| 영상 입력 | 암호화·복호화 FPGA | 중간 보안 노드 | 제어망 어댑터 |
|---|---|---|---|
| <img src="assets/hardware/pcam.jpg" alt="Digilent Pcam" width="180"><br>Pcam | <img src="assets/hardware/zybo_z7_20.jpg" alt="Zybo Z7-20" width="180"><br>Zybo Z7-20 × 2 | <img src="assets/hardware/jetson_ports.png" alt="Jetson Orin Nano 포트 구성" width="220"><br>Jetson Orin Nano | <img src="assets/hardware/wifi_adapter.png" alt="USB Wi-Fi 어댑터" width="160"><br>USB Wi-Fi |

TX는 Pcam과 연결되고 RX는 HDMI capture board 및 UART로 PC에 연결됩니다. Jetson의 두 유선 NIC는 TX와 RX 사이의 `br-video`에 들어가며, Wi-Fi는 대시보드 접속과 세션 제어에 사용합니다.

## 데모 화면

### 복호화 전후 영상 비교

| RX 복호화 활성 — 정상 평문 | RX 복호화 비활성 — 암호문 노이즈 |
|---|---|
| ![RX에서 AES-256-GCM 복호화한 정상 평문 영상](assets/rx_decryption_enabled.gif) | ![복호화하지 않은 암호화 영상 데이터가 컬러 노이즈로 표시되는 화면](assets/rx_decryption_disabled_noise.gif) |

왼쪽은 RX가 인증·복호화한 뒤 복원한 영상이고, 오른쪽은 비교를 위해 복호화를
끄고 암호화된 frame data를 영상으로 표시한 결과입니다. 암호문에서는 사람이나
배경의 시각적 구조를 알아볼 수 없습니다. 오른쪽 화면은 TAG 인증 실패 동작을
뜻하지 않으며, 최종 secure RX는 인증에 실패한 packet을 노이즈로 출력하지 않고
payload 전체를 0으로 치환합니다.

### 정상 수신과 이벤트 기록

![RX HDMI 영상과 보안 상태를 함께 표시하는 PC 수신 콘솔](assets/pc_receiver.png)

정상 수신 화면은 복호 영상, Jetson 연결 상태, RX 보안 상태와 5종 탐지 누계를 함께 표시합니다. 보안 분석 페이지와 이벤트 로그는 공격의 시작·탐지·복구 흐름을 시간순으로 남깁니다.

| 보안 분석 페이지 | 이벤트 로그 |
|---|---|
| ![PC 보안 분석 페이지](assets/pc_attack_overview.png) | ![PC 보안 이벤트 로그](assets/pc_event_log.png) |

### 위·변조 및 재전송 공격

Jetson의 Tamper 엔진은 ciphertext 비트를 바꾸고 기존 TAG를 유지해 GCM 인증 실패를 유도합니다. Replay 엔진은 정상 인증 패킷을 저장한 뒤 다시 주입해 RX의 freshness 검사를 자극합니다.

| Ciphertext tamper | Authenticated packet replay |
|---|---|
| ![변조 공격 분석과 TAG 오류 탐지](assets/tamper_detection.png) | ![재전송 공격 분석과 REPLAY 탐지](assets/replay_detection.png) |

### 약한 키 탐색과 VLM 분석

Weak Session은 교육·데모를 위한 명시적 모드입니다. Jetson이 요청 ID, seed bit 수와 실제 session ID를 대조한 뒤 관찰 패킷의 TAG 검증에 성공하는 키를 찾고, 복원 프레임은 사용자가 요청할 때만 로컬 VLM으로 분석합니다.

| 키 탐색 결과 | 복원 프레임 VLM 분석 |
|---|---|
| ![약한 키 탐색 결과](assets/weak_key_search.png) | ![복원 프레임의 로컬 VLM 분석 결과](assets/weak_key_vlm.png) |

## 데모 진행 순서와 판정 포인트

| 단계 | 조작 | Jetson에서 확인 | RX/PC에서 확인 |
|---:|---|---|---|
| 1. Normal | bridge와 TX/RX 기동 | ingress/egress packet rate, entropy, drop delta | live video, auth reject 0, 5종 detector 증가 없음 |
| 2. Tamper prepare/start | 공격률 선택 후 시작 | 실제 engine active, modified packet 수 | TAG counter 증가, 해당 packet zero substitution, 이벤트 기록 |
| 3. Tamper stop | 공격 중지 | last real result 유지 후 engine inactive | 정상 packet부터 영상 자동 복구 |
| 4. Replay prepare/start | 정상 packet capture 후 재주입 | capture → store → inject phase | REPLAY와 SEQUENCE flag, 재주입 packet 차단 |
| 5. Weak prepare | seed bit 수와 request ID로 session 요청 | ACK profile/request ID와 관찰 session 일치 | Weak Session이 된 뒤에만 search-ready |
| 6. Key search | CPU/CUDA search 시작 | keys tested, elapsed time, TAG match | verified key로 recovered frame 생성 |
| 7. VLM | 현재 recovered frame 분석 요청 | run ID와 image SHA-256 gate 통과 | 분석 결과와 근거 이미지 표시 |
| 8. Secure/reset | secure session 복귀 요청 | 이전 weak task 종료, matching secure packet 관찰 | 새 session에서 정상 영상과 detector 기준선 확인 |

공격이 성공했다는 판정과 수신 보안이 실패했다는 판정은 다릅니다. 데모의 정상 결과는 **Jetson이 공격 packet을 만들었고, RX가 그것을 탐지·차단했으며, 이후 정상 packet에서 영상이 복구되는 것**입니다.

## 소스 구조

```text
AES/
├── fpga/
│   ├── tx/                    TX RTL, XDC, Tcl, TB, PetaLinux source
│   ├── rx/                    RX RTL, 5종 detector, HDMI, IP repo, PetaLinux
│   ├── session_control/       ECDH/HKDF/capsule agent와 복구 테스트
│   ├── stm32/                 NUCLEO-F411 UART echo source
│   └── scripts/               TX/RX 공통 빌드·JTAG·SD 보조 스크립트
├── jetson/
│   ├── bridge/                2-NIC L2 bridge 적용·복구 스크립트
│   └── dashboard/             backend, UI source, 공격·분석 엔진, 테스트
├── pc/
│   ├── dashboard/             HDMI/UART 수신 웹 콘솔과 설정 예시
│   └── preview/               경량 HDMI capture 미리보기
├── verification/
│   ├── nist_kat/              NIST AESAVS 405-vector KAT
│   ├── aes256_c_vs_fpga/      C/OpenSSL golden과 RTL 10,000건 비교
│   ├── tx_uvm/                TX UVM TB와 1280-packet golden handoff
│   ├── rx_uvm/                RX 인증·5종 오류 UVM regression
│   └── tx_rx_loopback/        TX 출력에서 RX 복호까지 loopback
├── reference/
│   └── original_aes256_gcm_core/
│                              독립형 AES/GCM 참고 코어와 자체 검증
└── assets/                    이 문서에 사용하는 구조·장비·데모 이미지
```

| 위치 | 역할 |
|---|---|
| [`fpga`](fpga/README.md) | TX/RX PL datapath, PetaLinux와 session control의 연결 구조 |
| [`fpga/tx`](fpga/tx/README.md) | 카메라 16-bit stream을 128-bit로 묶고 PL에서 AES-GCM 암호화 |
| [`fpga/rx`](fpga/rx/README.md) | 패킷 인증·복호화, 5종 오류 계수, HDMI와 UART 상태 출력 |
| [`fpga/session_control`](fpga/session_control/README.md) | 세션 생성·capsule 전달·재부팅 복구·Wi-Fi supervision |
| [`jetson`](jetson/README.md) | bridge, telemetry, 공격 engine과 UI/API 상태 기계 |
| [`jetson/bridge`](jetson/bridge/README.md) | 두 유선 NIC의 투명 bridge 구성 |
| [`jetson/dashboard`](jetson/dashboard/README.md) | 관찰 UI, Tamper/Replay/Weak-Key/VLM backend |
| [`pc`](pc/README.md) | HDMI·UART·Jetson API를 합치는 PC data flow와 화면 의미 |
| [`pc/dashboard`](pc/dashboard/README.md) | RX HDMI·UART와 Jetson 상태를 통합한 PC 콘솔 |
| [`pc/preview`](pc/preview/README.md) | USB HDMI capture 단독 점검 도구 |
| [`verification`](verification/README.md) | 암호 코어부터 TX/RX 종단까지의 검증 계층 |
| [`reference/original_aes256_gcm_core`](reference/original_aes256_gcm_core/README.md) | 플랫폼 결합을 제외한 독립형 AES-256-GCM RTL과 자체 검증 결과 |

### 통합 코어와 독립형 참고 코어

두 구현은 AES-256-GCM의 수학적 연산은 같지만 교체 가능한 동일 wrapper가 아닙니다.
`fpga/tx`와 `fpga/rx`의 코어는 1,280-packet 영상 frame과 AXI/DMA 경로에 맞춘
최종 구현이고, [`reference/original_aes256_gcm_core`](reference/original_aes256_gcm_core/README.md)는
플랫폼과 packet protocol을 제거해 암호 연산 자체를 독립적으로 구동할 수 있게 한
초기 standalone 계열입니다.

| 구분 | 최종 통합 구현 | 독립형 참고 구현 |
|---|---|---|
| 대표 top | [`video_aes_gcm_tx_top`](fpga/tx/vivado/rtl/aes256_gcm/video_aes_gcm_tx_top.sv), [`video_aes_gcm_rx_top`](fpga/rx/vivado/rtl/aes256_gcm/video_aes_gcm_rx_top.sv) | [`gcm_tx_engine`](reference/original_aes256_gcm_core/rtl/gcm_tx_engine.sv), [`gcm_rx_engine`](reference/original_aes256_gcm_core/rtl/gcm_rx_engine.sv) |
| 입력 문맥 | `session_id`, `frame_id`, `packet_index`로 AAD와 nonce를 내부 생성 | `cmd_key`, `cmd_iv`, `cmd_aad`, `cmd_payload_blocks`를 외부 명령으로 입력 |
| 데이터 인터페이스 | 영상용 128-bit AXI4-Stream, `TKEEP/TLAST`와 별도 AAD/TAG metadata channel | AXI에 종속되지 않는 128-bit `valid/ready` command/data interface |
| Payload 길이 | packet당 90 blocks 고정, frame당 1,280 packets | full-block 개수를 command로 지정; 독립 buffer 기본값은 80 blocks |
| AES 자원 | 외부 key expansion 1개 + iterative AES 2개(data/auxiliary) | round-key cache를 내장한 iterative AES 1개 |
| 연산 scheduling | payload CTR과 `H`/TAG mask를 두 AES에 분담해 병렬 준비 | 단일 AES를 단계별로 재사용하고 AES와 GHASH를 block 단위로 중첩 |
| GHASH 구조 | `ghash_mul16` 한 모듈이 8 bits/clock으로 종속 누산 | `ghash_engine_seq` 제어기와 `gf128_mult_8bit_seq` 곱셈기를 분리 |
| Protocol 검사 | `PCAM`, version/flags, session, SOF/EOF, sequence와 stream 형식 검사 포함 | GCM message만 처리하며 영상 header, replay/sequence 의미는 모름 |
| 인증 전 평문 | 2 × 90-block ping-pong BRAM에 저장; 실패 시 90개 zero block 출력 | 별도 `authenticated_packet_buffer`에 저장; 실패 시 packet을 출력하지 않음 |
| 실패 시 timing | 영상 pipeline 길이를 보존해 HDMI 경로가 계속 진행 | generic consumer가 다음 동작을 결정하도록 출력 자체를 억제 |
| 검증 근거 | 반복형 AES VCS KAT 405개와 packet/UVM/TX→RX/system 시험 | 현재 `aes256_core` xsim KAT 405개와 후속 GCM engine 4-block directed 시험 |
| 사용 위치 | 최종 TX/RX bitstream의 실제 합성 경로 | 코어 단독 학습·재사용·구조 비교용이며 최종 bitstream에는 자동 포함되지 않음 |

가장 큰 구조 차이는 **AES 개수와 책임 범위**입니다. 독립형은 AES 하나와 GHASH
하나를 재사용하는 범용 message engine이므로 상위 계층이 IV, AAD, 길이와 packet
격리를 제공해야 합니다. 최종 통합형은 AES를 두 개로 나누고 영상 protocol 생성,
header/freshness 검사와 실패 packet의 zero-fill까지 포함해 보드의 고정 streaming
경로를 직접 책임집니다.

독립형 코어는 AES/GCM 연산을 이해하고 단독 검증하기 좋은 기준이며, 최종 통합
코어는 그 기능을 영상 전송 규격에 맞게 확장한 시스템 구현입니다. 따라서 독립형을
최종 경로에 넣으려면 AXI adapter만 연결하는 것으로는 부족하고, 90-block packet
계약, AAD/nonce 생성, session·sequence 검사와 zero-fill 정책을 함께 구현해야 합니다.

검증 이력도 구현 시점별로 구분해야 합니다. 초기 `aes256_iterative_core`에 보존된
직접 근거는 NIST AESAVS 405-vector VCS/Verdi KAT입니다. 독립형 폴더의 GCM
TX/RX·TAG 변조·quarantine PASS는 이후 추가된 `gcm_tx_engine`, `gcm_rx_engine`,
`authenticated_packet_buffer`의 4-block directed test이며, 초기 AES 코어에 대한
GCM KAT나 최종 영상 시스템 UVM 결과를 뜻하지 않습니다.

## 실행 개요

### FPGA

Vivado 2025.2와 Zybo Z7-20 board files가 준비된 환경에서 저장소 루트를 기준으로 실행합니다. Tcl은 자신의 위치를 기준으로 RTL과 XDC를 찾고 `project/`를 새로 생성합니다.

```powershell
vivado -mode batch -source .\AES\fpga\tx\vivado\tcl\build_aes_gcm_tx.tcl
vivado -mode batch -source .\AES\fpga\rx\vivado\tcl\build_aes_gcm_rx.tcl
```

PetaLinux 사용자 소스와 빌드 진입점은 각 보드의 `petalinux/`에 있습니다.

```bash
cd AES/fpga/tx/petalinux
./build_petalinux.sh
```

RX도 같은 방식으로 `AES/fpga/rx/petalinux`에서 실행합니다. 생성되는 bitstream, XSA, boot image와 SD card 파일은 저장소에 포함하지 않습니다.

### Jetson

두 유선 NIC를 bridge로 묶은 뒤 대시보드를 시작합니다.

```bash
cd AES/jetson/bridge
sudo ./scripts/apply_br_video.sh
```

```bash
cd AES/jetson/dashboard
./operator/start-dashboard.sh
```

대시보드는 기본적으로 `0.0.0.0:4173`에서 서비스됩니다. CUDA 검색기는 `bruteforce/weakkey_search.cu`, 로컬 VLM 앱은 `local-vlm-test/`에 소스만 포함돼 있습니다. 모델과 CUDA runtime은 장비에 별도로 배치해야 합니다.

### PC

```bat
cd AES\pc\dashboard
copy pc_rx_ui.env.example.cmd pc_rx_ui.env.cmd
run_pc_ui.bat
```

기본 주소는 `http://127.0.0.1:8765/`이며, HDMI capture device는 브라우저에서 선택합니다. 실제 API 키나 장비별 주소가 든 `pc_rx_ui.env.cmd`는 Git 대상에서 제외됩니다.

## 검증 결과

![AES 코어·TX·RX 단계별 검증 구성](assets/verification_overview.png)

| 계층 | 검증 내용 | 정리 시 확인 결과 |
|---|---|---|
| 통합 반복형 AES core | NIST AESAVS ECB-256 KAT, VCS/Verdi | 405/405, 0 fail |
| 후속 standalone AES core | NIST AESAVS ECB-256 KAT, xsim | 405/405, 0 fail |
| 후속 standalone GCM engines | 4-block TX/RX, TAG 변조, 인증 전 평문 격리 directed test | GCM engine PASS |
| C ↔ RTL | OpenSSL golden 기반 10,000개 AES-256 block | C 10,000/10,000, RTL 10,000/10,000 일치 |
| TX UVM | ciphertext/AAD/TAG, AXI backpressure, 1280 packets | mismatch 0, protocol error 0 |
| RX UVM | 정상·TAG/Cipher tamper·replay·sequence·session·timeout·backpressure | regression PASS |
| TX → RX | 실제 TX handoff record를 RX에 입력해 plaintext와 비교 | loopback PASS |
| Jetson backend | packet metadata, attack status, weak-key/VLM lifecycle | Python 19 tests PASS |
| Jetson UI | replay/tamper/weak-key 표시 계약 | JavaScript 8 tests PASS |
| PC UI | event timeline, OCC gate, AI evidence, video frame 상태 | JavaScript 7 tests PASS |
| PC backend | UART/API/state 자체 검사 | self-test PASS |

재현 명령과 각 검증의 범위는 [verification/README.md](verification/README.md)에 모았습니다.

## 설계 자료

- [AES-256 요약](../DOC/AES_GCM/AES_Summary.pdf)
- [GCM 동작 모드](../DOC/AES_GCM/GCM_Mode.pdf)
- [GCM 요약](../DOC/AES_GCM/GCM_Summary.pdf)
