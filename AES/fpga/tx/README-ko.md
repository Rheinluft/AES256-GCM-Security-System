# AES-GCM 영상 송수신 운용 요약

현재 TX 구현의 상세 빌드·검증값은 [`README.md`](README.md), TX/RX 공통 RTL
구조는 [FPGA 설계 문서](../README.md), 암호 packet 계산은
[AES 상세 설계](../../README.md)를 기준으로 한다.

## 전체 경로

```text
Pcam
  -> Zybo TX MIPI/PL
  -> PL AES-256-GCM 또는 SW3 plaintext bypass
  -> DDR에는 PL 처리 후 frame만 기록
  -> UDP 5602
  -> Jetson br-video 투명 L2 bridge
  -> Zybo RX 인증·복호
  -> HDMI
  -> USB capture board
  -> PC

Zybo RX 5-pin UART -> PC Receiver Console
Jetson Dashboard   -> 공격 제어와 Weak-Key/VLM 데모
```

Secure mode에서는 카메라 평문을 DDR에 먼저 쓴 뒤 암호화하지 않는다.
`axis_video16_to_frame128`이 YUYV16 stream을 128-bit block으로 묶고,
`axis_gcm_tx_frame_processor_v1`과 `video_aes_gcm_tx_top`이 DDR write보다 앞에서
AES-256-GCM을 수행한다. SW3로 plaintext bypass를 명시적으로 선택한 경우만
암호화 전 영상이 통과한다.

## 고정 packet 규격

| 항목 | 값 |
|---|---:|
| 영상 | 1280×720 YUYV |
| frame당 packet | 1,280 |
| AAD | 16 B |
| payload | 1,440 B = 90 × 128-bit block |
| TAG | 16 B |
| UDP payload | 1,472 B |
| video UDP port | 5602 |

AAD는 `PCAM` magic, session ID, frame ID, packet ID, flags/version으로 구성한다.
nonce는 `session_id || frame_id || 16'h0000 || packet_id`로 재구성한다. 같은
session 안에서 frame/packet counter를 되돌리지 않아 nonce 재사용을 막는다.

## Session과 물리 입력

- 부팅 기본값은 Secure Session이다.
- TX와 RX는 X25519 pinned peer, HKDF-SHA256, AES-GCM capsule과
  READY/COMMIT/DONE 절차로 session을 적용한다.
- Jetson의 `CREATE_SECURE_SESSION`과 `CREATE_WEAK_SESSION(seed_bits=N)`은 부팅
  이후 session을 바꾸는 관리 명령이며 최초 Secure Session의 필수 trigger가 아니다.
- TX `SW3 OFF`는 plaintext bypass, `SW3 ON`은 현재 session의 AES-GCM 경로다.
- TX/RX의 `SW2`, `BTN3`는 데모 session 제어에 사용하지 않는다.

## RX 오류와 PC 상태 경로

RX의 `gcm_rx_error_detector`는 TAG, REPLAY, SEQUENCE, SESSION, TIMEOUT을
독립 계수한다. 현재 상태 전송은 예전 UDP telemetry가 아니라 RX 5-pin UART를
사용한다.

```text
ZYBO_RX_V1 T <CRC32> <telemetry JSON>
ZYBO_RX_V1 E <CRC32> <security-event JSON>
```

기본 UART는 `/dev/ttyPS0`, `115200 baud`, 약 5 Hz다. PC backend는 prefix,
frame 종류, CRC32, `source_role=zybo-rx`, `transport=uart`를 검사한다. RX HDMI
영상과 UART 상태를 함께 보려면 [PC Receiver Console](../../pc/dashboard/README.md)을
사용한다.

## 재현과 검증

```powershell
vivado -mode batch -source .\AES\fpga\tx\vivado\tcl\build_aes_gcm_tx.tcl
vivado -mode batch -source .\AES\fpga\rx\vivado\tcl\build_aes_gcm_rx.tcl
```

NIST AES KAT, C/OpenSSL 비교, TX/RX UVM, 실제 TX record의 RX handoff와 session
host test는 [검증 문서](../../verification/README.md)에 시험 자극과 합격 조건을
구분해 기록했다.
