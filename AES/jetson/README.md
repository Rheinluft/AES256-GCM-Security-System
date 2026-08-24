# Jetson Design

Jetson Orin Nano는 Zybo TX와 RX 사이의 비신뢰 중간 노드입니다. 정상 상태에서는 두 유선 NIC 사이에서 encrypted packet을 통과시키고, 동시에 traffic을 관찰합니다. 데모 명령이 있을 때만 Tamper·Replay·Weak-Key 작업을 실행합니다.

## 네트워크 위치와 신뢰 경계

```text
Zybo TX 10.10.15.2
   │ encrypted UDP video
   v
Jetson NIC 1 ── br-video ── Jetson NIC 2
   │              │
   │              ├─ packet capture/statistics
   │              ├─ Tamper engine
   │              ├─ Replay engine
   │              └─ Weak-Key capture/search
   v
Zybo RX 10.10.15.3

Jetson Wi-Fi / management network
   └─ dashboard API, PC status polling, session-control request
```

Jetson은 정상 secure key를 소유하지 않습니다. 따라서 정상 traffic에서는 payload 의미를 알 수 없고, ciphertext entropy·metadata·timing·interface counter만 관찰합니다. 공격 성공 여부도 “원본 영상을 알았다”가 아니라 packet을 실제로 변경하거나 재주입했다는 engine 증거로 표현합니다.

## 구성요소

| 위치 | 역할 |
|---|---|
| [`bridge`](bridge/README.md) | 유선 NIC 자동 탐색, `br-video` 적용과 rollback |
| [`dashboard/backend`](dashboard/backend/) | telemetry, 공격 상태, Weak-Key와 VLM API |
| [`dashboard/dashboard-source`](dashboard/dashboard-source/) | React/Vite UI source와 표시 계약 테스트 |
| [`dashboard/dashboard`](dashboard/dashboard/) | Jetson에서 바로 서비스하는 정적 build |
| [`dashboard/tamper`](dashboard/tamper/README.md) | ciphertext bit 변조 kernel/user control source |
| [`dashboard/replay`](dashboard/replay/README.md) | packet capture·저장·재주입 engine source |
| [`dashboard/bruteforce`](dashboard/bruteforce/) | Weak Session 요청, CPU/CUDA search, frame recovery |
| [`dashboard/local-vlm-test`](dashboard/local-vlm-test/README.md) | 검증된 recovered frame의 로컬 VLM 분석 서비스 |
| [`dashboard/operator`](dashboard/operator/) | service·desktop·start/stop 운영 script |

## 정상 traffic 관찰

Page 01은 packet payload를 복호하지 않고 다음 값을 계산합니다.

- AAD 16 B, ciphertext 1440 B, TAG 16 B의 고정 record 구조
- 마지막 실제 session ID, frame ID와 packet ID
- ciphertext byte distribution, Shannon entropy와 serial correlation
- packet timestamp의 inter-arrival-time 표준편차
- ingress/egress packet rate와 throughput
- NIC drop/error counter의 30초 delta와 누계
- bridge 양방향 counter rate로 추정한 TX→RX 방향
- Jetson board power와 backend freshness

UI는 200 ms snapshot polling을 사용하지만 packet parser는 별도로 계속 동작합니다. 따라서 화면 refresh 주기와 packet 처리율을 같은 값으로 해석하지 않습니다.

## 공격 상태 기계

공격은 `idle → prepared → running → stopped/reset` 단계를 갖습니다. UI는 아직 일어나지 않은 결과를 미리 표시하지 않고 backend가 관찰한 phase만 보여줍니다.

### Tamper

1. 선택한 비율만큼 대상 packet을 고릅니다.
2. ciphertext bit를 변경하고 기존 TAG는 유지합니다.
3. 변경 packet 수와 실제 engine 상태를 API에 기록합니다.
4. RX가 TAG failure로 차단하는지 PC detector와 대조합니다.

### Replay

1. 정상 packet을 capture합니다.
2. source record를 runtime 저장소에 고정합니다.
3. frame boundary에 맞춰 과거 record를 재주입합니다.
4. RX의 REPLAY bitmap과 SEQUENCE detector 반응을 확인합니다.

### Weak-Key

1. backend가 64-bit request ID를 생성하고 TX에 Weak Session을 요청합니다.
2. ACK의 profile/request ID/seed bits와 실제 관찰 packet session을 모두 대조합니다.
3. 관찰 record의 AES-GCM TAG를 기준으로 CPU/CUDA key candidate를 검증합니다.
4. 찾은 key로 frame을 복원하고 run ID·image SHA-256을 기록합니다.
5. Secure/reset은 기존 weak 작업을 직렬화한 뒤 matching secure packet을 볼 때까지 상태를 유지합니다.

### VLM gate

VLM은 검색 중이거나 이전 run에서 남은 이미지, metadata SHA-256이 다른 이미지를 거부합니다. 현재 완료 run에서 cryptographically verified key로 만든 recovered frame만 분석 대상으로 넘깁니다. 모델과 CUDA runtime은 장비별 대용량 의존성이므로 저장소에는 포함하지 않습니다.

## 주요 API

| 경로 | 의미 |
|---|---|
| `GET /api/telemetry/latest` | packet·NIC·board 최신 snapshot |
| `GET /api/attack/status` | Tamper/Replay 실제 phase와 마지막 결과 |
| `POST /api/attack/prepare|start|stop|reset` | integrity attack lifecycle |
| `GET /api/bruteforce/status` | Weak Session/search/recovery 상태 |
| `POST /api/bruteforce/prepare|start|stop|secure|reset` | Weak-Key lifecycle |
| `GET /api/bruteforce/recovered-frame` | 현재 검증된 복원 이미지 |
| `POST /api/vlm/analyze` | identity gate를 통과한 frame 분석 |

## 실행

```bash
cd AES/jetson/bridge
sudo ./scripts/apply_br_video.sh
```

```bash
cd AES/jetson/dashboard
./operator/start-dashboard.sh
```

기본 dashboard 주소는 `0.0.0.0:4173`입니다. Tamper engine과 VLM은 별도 system/user service로 실행되며 자세한 service 이름은 [dashboard/README.md](dashboard/README.md)를 따릅니다.

## 테스트가 보장하는 것

- attack status가 공격자 측에서 실제로 아는 정보만 노출하는지
- Replay가 injection 전 target/result를 지어내지 않는지
- stop 뒤 마지막 실제 결과는 유지하되 engine active는 해제되는지
- bridge direction, drop delta, entropy sampling과 packet jitter 계산이 실제 counter/timestamp를 쓰는지
- Weak prepare retry가 같은 request ID를 유지하고 matching session을 기다리는지
- secure/reset/stop 경쟁에서 이전 search 결과가 새 secure phase를 덮지 않는지
- VLM이 search 중·다른 run·다른 SHA-256 이미지를 거부하는지
- UI가 Replay 3단계와 Tamper marker, 실제 key bit 수·elapsed time을 정확히 표시하는지

세부 테스트명과 실행 명령은 [verification/README.md](../verification/README.md)에 있습니다.
