# PC Receiver Design

PC는 복호 영상과 보안 상태를 사람이 판단할 수 있는 하나의 콘솔로 합칩니다. 영상이 보인다는 사실만으로 정상이라고 판단하지 않고, RX telemetry의 freshness와 Jetson 공격 lifecycle을 함께 표시합니다.

![RX HDMI 영상과 보안 상태를 함께 표시하는 PC 수신 콘솔](../assets/pc_receiver.png)

## 입력 데이터

| 입력 | 수집 경로 | 사용 목적 |
|---|---|---|
| RX HDMI | USB3 capture device → browser video element | 실제 복호 영상과 frame liveness |
| RX UART | USB serial → Python backend | active session, 5종 detector, last error context |
| Jetson attack status | HTTP `/api/attack/status` polling | 공격 mode·phase·rate·실제 engine result |
| OCC 판정 | UART/backend state | fresh `PASS` 기반 receiver access gate |
| 사용자 질문 | browser → local Python proxy | 현재 evidence snapshot을 포함한 보안 분석 |

## Backend 상태 합성

[`dashboard/server.py`](dashboard/server.py)는 RX UART에서 `ZYBO_RX_V1`, CRC32, `source_role=zybo-rx`, `transport=uart` 계약을 검사합니다. COM 번호를 고정하기보다 올바른 role frame을 보내는 장치를 찾습니다.

Jetson 상태는 약 200 ms 주기로 읽고 일정 시간 새 snapshot이 없으면 offline/stale로 표시합니다. 공격 명령을 보낸 시점과 RX detector가 증가한 시점을 별도 event로 기록하기 때문에 다음을 구분할 수 있습니다.

- 공격 준비만 됐고 아직 packet이 변경되지 않은 상태
- 공격 engine이 실제 running인 상태
- RX가 오류를 검출해 counter를 올린 상태
- 공격은 끝났지만 마지막 실제 결과를 보존하는 상태
- 정상 packet이 돌아와 영상이 복구된 상태

## 화면 구성

### 01 / Live Receiver

- USB HDMI capture 영상
- video frame change/liveness와 content FPS
- 현재 OCC lock/unlock 상태
- RX session과 telemetry freshness
- Jetson 연결·공격 mode와 phase
- 5종 detector 누계와 마지막 오류 context

### 02 / Security Analysis

![PC 보안 분석 페이지](../assets/pc_attack_overview.png)

- 최근 30초 FPS, drop, jitter와 reject rate
- TAG/REPLAY/SEQUENCE/SESSION/TIMEOUT detector 카드
- 공격 시작·탐지·중지·복구 event timeline
- 같은 session에서 반복되는 low-level event의 집계
- 최근 의미 있는 공격 구간으로 자동 focus

### Event log

![PC 보안 이벤트 로그](../assets/pc_event_log.png)

이벤트 로그는 heartbeat마다 같은 문장을 추가하지 않습니다. session과 attack lifecycle을 기준으로 중복을 묶고, counter가 실제 증가하거나 phase가 바뀔 때 새 항목을 만듭니다.

### Security Assistant

AI 요청에는 현재 PC/RX/Jetson evidence snapshot을 붙입니다. 답변이 완료된 뒤에도 어떤 상태를 근거로 분석했는지 확인할 수 있게 snapshot lifecycle을 유지합니다. API key는 browser source가 아니라 로컬 backend 환경 파일에만 둡니다.

## OCC 접근 게이트

기본 시작 화면은 잠겨 있습니다. UI를 여는 조건은 다음 둘뿐입니다.

1. 새로 수신한 OCC `PASS`와 `unlockSource=OCC`
2. 개발용 Q+W+E 명시적 해제

`FAIL`, 오래된 PASS, 단순 Jetson online이나 AES 영상 수신만으로는 gate를 열지 않습니다. L+K+J는 개발 중 다시 잠그는 조합입니다.

## 영상 상태 해석

HDMI carrier는 720p60이지만 FPGA가 새 영상 내용을 만드는 속도는 약 29~30 fps입니다. 따라서 capture device가 60 fps를 보고해도 같은 frame만 반복될 수 있습니다.

`video-frame-monitor`는 연속 frame의 변화 시점과 정지 시간을 추적해 다음을 구분합니다.

- carrier 자체가 끊긴 상태
- carrier는 살아 있지만 같은 화면만 반복되는 상태
- 실제 pixel content가 계속 갱신되는 상태

단순 HDMI 점검만 필요할 때는 [`preview`](preview/README.md)의 OpenCV 도구를 사용할 수 있습니다.

## 실행과 설정

```bat
cd AES\pc\dashboard
copy pc_rx_ui.env.example.cmd pc_rx_ui.env.cmd
run_pc_ui.bat
```

기본 주소는 `http://127.0.0.1:8765/`이며 사용 중이면 다음 빈 port를 찾습니다. `pc_rx_ui.env.cmd`에는 장비별 Jetson 주소, UART 설정과 선택적 AI API key를 넣으며 Git에서는 제외됩니다.

## 테스트가 보장하는 것

- OCC gate가 fresh PASS 또는 명시적 QWE 외에는 열리지 않는지
- 공격 timeline이 prepare/running/stop/heartbeat recovery 순서를 유지하는지
- session event가 의미 단위로 집계되는지
- video frame liveness가 실제 frame 변화로 계산되는지
- production UI가 mock field가 아닌 backend API 계약을 사용하는지
- AI 답변, evidence snapshot과 자동 focus lifecycle이 함께 유지되는지
- timeout/error 응답이 빈 분석 결과로 조용히 처리되지 않는지

실행 명령과 7개 UI 테스트의 상세 항목은 [verification/README.md](../verification/README.md)에 있습니다.
