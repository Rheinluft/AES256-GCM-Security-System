# AES-256-GCM Secure Video Pipeline

Pcam 영상이 DDR에 평문으로 기록되기 전에 Zybo TX의 PL에서 암호화되고, Jetson 중간 노드를 거쳐 Zybo RX에서 인증·복호화되는 종단간 영상 보안 데모입니다. Jetson은 정상 트래픽 관찰과 공격 시연을 담당하고, RX와 PC 콘솔은 공격 탐지 결과와 복호 영상을 보여줍니다.

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

## 내부 설계

### TX: 평문이 DDR에 도달하기 전 암호화

```text
Pcam MIPI
  -> PL YUYV16 stream
  -> axis_video16_to_frame128
  -> axis_gcm_tx_frame_processor_v1
       ├─ AAD = protocol/session/frame/packet metadata
       ├─ CTR encryption
       └─ GHASH authentication tag
  -> axis_frame128_to_video16
  -> Video Frame Buffer Write / DDR ciphertext
  -> PS UDP sender
```

`video_aes_gcm_tx_top`은 AES-256 key expansion, counter mode encryption과 GHASH를 결합합니다. packet마다 16-byte AAD와 96-bit nonce 문맥을 만들고 1440-byte payload를 암호화합니다. ciphertext와 metadata 출력은 독립 AXI channel이므로 backpressure가 걸려도 `TVALID`가 유지되는 동안 data와 metadata가 바뀌지 않아야 합니다.

### RX: authenticate-before-release

```text
PS/DDR encrypted record
  -> axis_gcm_rx_frame_processor_v2
  -> video_aes_gcm_rx_top
       ├─ AAD/header/session 검사
       ├─ GHASH/TAG 재계산
       ├─ replay/sequence/timeout 문맥
       └─ 승인 packet만 plaintext commit
  -> packet_buffer_bram
  -> YUYV/RGB video path
  -> HDMI
```

정상 packet은 golden plaintext와 일치해야 합니다. TAG나 header가 거부된 packet은 출력 길이를 유지하되 payload 전체를 0으로 치환합니다. 이 방식은 downstream video timing을 유지하면서 인증 실패 데이터가 평문처럼 노출되는 것을 막습니다.

`gcm_rx_error_detector`는 stream을 바꾸지 않는 입력 tap으로 다음 이벤트를 별도 sticky bit·counter·last context에 기록합니다.

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

## 보안·패킷 계약

| 항목 | 값 |
|---|---|
| 영상 | 1280×720 YUYV, 약 29~30 fps |
| 알고리즘 | AES-256-GCM |
| 패킷 | AAD 16 B + ciphertext 1440 B + authentication tag 16 B = 1472 B |
| GCM nonce | `session_id[31:0] || frame_id[31:0] || 16'h0000 || packet_id[15:0]` |
| 다중 바이트 필드 | Network / big-endian |
| 세션 설정 | X25519 ECDH + HKDF-SHA256 + AES-GCM capsule |
| RX 탐지 | TAG, REPLAY, SEQUENCE, SESSION, TIMEOUT |
| 영상 출력 | RX HDMI 1280×720p60 carrier |
| 상태 출력 | RX UART 115200 baud + Jetson HTTP API |

## 하드웨어 구성

| 영상 입력 | 암호화·복호화 FPGA | 중간 보안 노드 | 제어망 어댑터 |
|---|---|---|---|
| <img src="assets/hardware/pcam.jpg" alt="Digilent Pcam" width="180"><br>Pcam | <img src="assets/hardware/zybo_z7_20.jpg" alt="Zybo Z7-20" width="180"><br>Zybo Z7-20 × 2 | <img src="assets/hardware/jetson_ports.png" alt="Jetson Orin Nano 포트 구성" width="220"><br>Jetson Orin Nano | <img src="assets/hardware/wifi_adapter.png" alt="USB Wi-Fi 어댑터" width="160"><br>USB Wi-Fi |

TX는 Pcam과 연결되고 RX는 HDMI capture board 및 UART로 PC에 연결됩니다. Jetson의 두 유선 NIC는 TX와 RX 사이의 `br-video`에 들어가며, Wi-Fi는 대시보드 접속과 세션 제어에 사용합니다.

## 데모 화면

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

두 구현은 같은 AES-256-GCM을 수행하지만 용도와 구조가 다릅니다. `fpga/tx`와
`fpga/rx` 아래의 코어가 최종 영상 시스템의 실제 합성 경로이며, `reference`의
코어는 플랫폼·AXI packet adapter와 분리해 암호 연산 구조와 검증 근거를
보존하는 독립형 참고 구현입니다.

| 구분 | 최종 통합 구현 | 독립형 참고 구현 |
|---|---|---|
| 위치 | `fpga/tx`, `fpga/rx` | `reference/original_aes256_gcm_core` |
| AES 구조 | 외부 key expansion + `aes256_iterative_core` | round-key cache를 포함한 `aes256_core` |
| GCM 결합 | 영상 packet/AXI stream 전용 TX·RX top | command 및 128-bit `valid/ready` GCM engine |
| 인증 전 평문 | RX packet BRAM에서 판정 후 commit | `authenticated_packet_buffer`에서 격리 |
| 빌드 관계 | 최종 TX/RX bitstream 대상 | 최종 bitstream에는 자동 포함되지 않는 참고 코어 |
| 관리 목적 | 최종 TX/RX 시스템 재현 | 코어 단독 재사용과 구조·검증 비교 |

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
| AES-256 core | NIST AESAVS ECB-256 KAT, xsim/VCS | 405/405, 0 fail |
| Standalone reference core | NIST KAT 및 GCM TX/RX 정상·TAG 변조·평문 격리 | AES 405/405, GCM engine PASS |
| C ↔ RTL | OpenSSL golden 기반 10,000개 AES-256 block | C 10,000/10,000, RTL 10,000/10,000 일치 |
| TX UVM | ciphertext/AAD/TAG, AXI backpressure, 1280 packets | mismatch 0, protocol error 0 |
| RX UVM | 정상·TAG/Cipher tamper·replay·sequence·session·timeout·backpressure | regression PASS |
| TX → RX | 실제 TX handoff record를 RX에 입력해 plaintext와 비교 | loopback PASS |
| Jetson backend | packet metadata, attack status, weak-key/VLM lifecycle | Python 19 tests PASS |
| Jetson UI | replay/tamper/weak-key 표시 계약 | JavaScript 8 tests PASS |
| PC UI | event timeline, OCC gate, AI evidence, video frame 상태 | JavaScript 7 tests PASS |
| PC backend | UART/API/state 자체 검사 | self-test PASS |

재현 명령과 각 검증의 범위는 [verification/README.md](verification/README.md)에 모았습니다.
