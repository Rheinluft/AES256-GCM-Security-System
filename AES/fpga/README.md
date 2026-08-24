# FPGA Design

Zybo Z7-20 두 대가 AES 영상 보안의 신뢰 종단을 구성합니다. TX는 Pcam 평문을 PL에서 암호화하고, RX는 인증이 끝난 packet만 복호 영상 경로에 반영합니다. PetaLinux는 packet 송수신과 session orchestration을 담당하지만 AES/GHASH datapath와 최종 승인 판정은 RTL에 있습니다.

## 보드 역할

| 구분 | TX | RX |
|---|---|---|
| 영상 입력·출력 | Pcam MIPI 1280×720 YUYV 입력 | HDMI 1280×720p60 출력 |
| 암호 역할 | AES-256-GCM encryption, AAD/TAG 생성 | AES-256-GCM authentication/decryption |
| packet 문맥 | session/frame/packet ID 생성 | session/header/freshness 검사 |
| DDR에 저장되는 영상 | ciphertext | 승인된 plaintext display frame |
| 오류 관찰 | protocol/health status | TAG/REPLAY/SEQUENCE/SESSION/TIMEOUT |
| PS 역할 | ciphertext frame을 UDP packet으로 전송 | UDP record 공급, UART telemetry 전송 |

## TX PL 데이터 경로

```text
Pcam MIPI RX
  -> YUYV16 AXI4-Stream
  -> axis_video16_to_frame128
  -> axis_gcm_tx_frame_processor_v1
       -> video_aes_gcm_tx_top
          -> aes256_key_expansion / aes256_iterative_core
          -> CTR counter encryption
          -> ghash_mul16 authentication
  -> axis_frame128_to_video16
  -> Video Frame Buffer Write
  -> DDR ciphertext frame
```

주요 설계 포인트:

- 16-bit video beat를 128-bit AES block으로 묶으며 packet당 payload는 1440 bytes입니다.
- AAD는 암호화하지 않지만 TAG 계산에는 포함돼 session/frame/packet metadata 변경을 검출합니다.
- PL encryption 뒤의 ciphertext만 DDR로 보내므로 secure mode에서 Pcam 평문이 PS memory를 왕복하지 않습니다.
- ciphertext와 metadata AXI output은 각각 독립 backpressure를 받을 수 있습니다.
- `metadata_status_cdc`와 `tx_pipeline_health_status`가 clock domain을 넘어 현재 packet과 pipeline 상태를 PS에 제공합니다.

핵심 소스는 [`tx/vivado/rtl`](tx/vivado/rtl), 재현 빌드는 [`build_aes_gcm_tx.tcl`](tx/vivado/tcl/build_aes_gcm_tx.tcl)입니다.

## RX PL 데이터 경로

```text
Encrypted record from PS/DDR
  -> axis_gcm_rx_frame_processor_v2
       -> AAD/header/session/freshness pre-check
       -> video_aes_gcm_rx_top
          -> GHASH/TAG verification
          -> CTR decryption
       -> packet_buffer_bram
       -> authenticated commit or zero substitution
  -> YUYV32 to RGB24
  -> 720p video timing
  -> rgb2dvi IP
  -> HDMI
```

RX가 내리는 판정은 세 가지 층으로 나뉩니다.

1. Header/session/sequence 문맥이 잘못되면 decrypt 결과를 승인하지 않습니다.
2. GCM TAG가 맞지 않으면 packet payload 전체를 zero로 내보냅니다.
3. 정상 packet은 입력 vector에 대응하는 plaintext와 byte 단위로 같아야 합니다.

`gcm_rx_error_detector`는 메인 stream의 handshake를 변경하지 않는 tap입니다. 각 error bit, sticky 상태, 발생 횟수와 마지막 session/frame/packet context를 레지스터로 제공하고 IRQ/UART telemetry의 근거가 됩니다.

핵심 소스는 [`rx/vivado/rtl`](rx/vivado/rtl), 재현 빌드는 [`build_aes_gcm_rx.tcl`](rx/vivado/tcl/build_aes_gcm_rx.tcl)입니다. HDMI 출력에는 Digilent `rgb2dvi` IP source가 [`rx/vivado/ip_repo`](rx/vivado/ip_repo)에 포함돼 있습니다.

## Session key 적용

TX/RX 공통 `aes_session_key_regs`는 software가 쓰는 candidate key와 datapath가 사용하는 active key 사이의 경계를 만듭니다.

```text
PS session agent
  -> session_id + AES-256 key write
  -> session_key_valid
  -> key_commit pulse
  -> key expansion
  -> key_ready
  -> safe packet/frame boundary에서 active session 전환
```

RX detector는 rekey 직후 제한된 grace window를 두어 commit 전후 packet이 잘못된 SESSION 이벤트를 만들지 않게 합니다. grace window가 끝난 뒤에는 AAD의 session ID가 active session과 다르면 SESSION 오류로 기록됩니다.

## PetaLinux와 session control

[`session_control`](session_control/README.md)은 다음 기능을 제공합니다.

- X25519 static-static ECDH와 pinned peer key 확인
- HKDF-SHA256 wrapping key 유도
- AES-256-GCM session capsule 암복호화
- TX/RX counter와 PENDING/ACTIVE/TERMINATED durable state
- READY/COMMIT/DONE 재시도와 응답 유실 복구
- USB Wi-Fi interface 탐색·health check·restart supervision
- RX 재부팅과 TX agent 재시작 뒤 현재 PL session 대조

각 보드의 PetaLinux recipe와 application source는 `tx/petalinux/project-spec`과 `rx/petalinux/project-spec`에 있습니다. build directory, bitstream, XSA, boot image와 SD image는 생성물이므로 저장소에 포함하지 않습니다.

## 보조 MCU

[`stm32`](stm32/)에는 NUCLEO-F411용 bare-metal UART echo source가 있습니다. clock/startup/linker script와 UART·LED·key driver를 함께 보존해 PC–보드 serial path를 단독 점검할 수 있습니다.

## 빌드 진입점

저장소 루트에서:

```powershell
vivado -mode batch -source .\AES\fpga\tx\vivado\tcl\build_aes_gcm_tx.tcl
vivado -mode batch -source .\AES\fpga\rx\vivado\tcl\build_aes_gcm_rx.tcl
```

PetaLinux:

```bash
cd AES/fpga/tx/petalinux
./build_petalinux.sh
```

RX도 `AES/fpga/rx/petalinux`에서 동일한 방식으로 실행합니다. 개발 당시 케이블/COM 기본값은 하위 JTAG script에 남아 있으므로 실제 장비에서는 인자나 환경변수로 지정합니다.

## FPGA 검증 연결

| 검증 | 확인 대상 |
|---|---|
| NIST KAT | AES-256 core와 key expansion의 표준 벡터 정확성 |
| C/OpenSSL ↔ RTL | 10,000 block 결과와 cycle 기반 성능 |
| TX UVM | 1280 packet AAD/ciphertext/TAG와 AXI stall 안정성 |
| RX UVM | authenticate-before-release, zero substitution, 5종 detector |
| TX→RX loopback | 실제 TX RTL record를 RX 입력으로 사용한 종단 handoff |
| Session host tests | capsule tamper/pinned-peer 거부, 재부팅·응답 유실·Wi-Fi 복구 |

자극과 합격 조건은 [verification/README.md](../verification/README.md)에 자세히 설명합니다.
