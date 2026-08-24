# Jetson 2-NIC 중간 삽입 재배선·운용

Zybo TX와 RX 사이에 Jetson Orin Nano를 투명 L2 중간 노드로 연결할 때 사용하는
운용 절차다. 실제 bridge 생성과 rollback은
[Jetson Bridge](../../jetson/bridge/README.md)의 스크립트를 사용한다.

## 신호 경로

```text
Video data plane
Pcam -> Zybo TX -> Jetson NIC1 -> br-video -> Jetson NIC2 -> Zybo RX

Display plane
Zybo RX HDMI -> USB capture board -> PC

RX observability plane
Zybo RX 5-pin UART -> PC Receiver Console

Management plane
PC browser -> Jetson Dashboard -> 공격/Weak-Key 제어
TX <-> RX Wi-Fi -> Secure Session control
```

영상 packet은 Jetson user-space, HTTP 또는 WebSocket relay를 통과하지 않는다.
Jetson은 원래 Ethernet destination MAC을 보존하는 Linux kernel bridge로
전달하면서 packet을 관찰하거나 명시적으로 선택된 공격만 적용한다.

현재 RX telemetry는 `10.10.15.1:47000/UDP`가 아니라 PC와 직접 연결한
`ZYBO_RX_V1` framed UART다. 따라서 telemetry를 받기 위해 `br-video`에
`10.10.15.1/24`를 지정할 필요가 없다.

## 고정 영상 계약

| 항목 | TX | RX |
|---|---|---|
| 영상 IPv4 | `10.10.15.2/24` | `10.10.15.3/24` |
| 영상 MAC | `02:00:00:00:00:02` | `02:00:00:00:00:03` |
| 영상 UDP | `5602` | `5602` |
| packet | AAD 16 B + ciphertext 1440 B + TAG 16 B | 같은 1472 B record 수신 |

RX HDMI carrier는 1280×720p60이고 인증된 영상 내용은 약 29~30 fps로
갱신된다. HDMI capture의 60 fps를 암호 packet 처리율로 보고하지 않는다.

## 1. 재배선 전 확인

1. Jetson 관리 접속을 Wi-Fi 또는 별도 관리망으로 먼저 확보한다.
2. bridge에 넣을 두 전용 Ethernet NIC를 물리적으로 식별한다.
3. default route나 현재 SSH가 사용하는 NIC는 bridge member로 선택하지 않는다.
4. TX/RX `SW3`를 원하는 암호 모드로 두고 공격 기능은 끈다.
5. RX HDMI와 5-pin UART를 각각 capture board와 PC에 연결한다.

인터페이스 이름만 믿지 말고 케이블을 하나씩 연결·분리해 carrier가 변하는 포트를
확인한다. 필요하면 permanent MAC과 driver도 기록한다.

```bash
ip -br link
ip -br addr
ip -4 route show default
ethtool -P <NIC>
ethtool -i <NIC>
```

## 2. Bridge 적용

연결된 물리 Ethernet NIC가 정확히 두 개라면 자동 선택한다.

```bash
cd /home/jetson/projects/zybo-security-demo/bridge
sudo ./scripts/apply_br_video.sh
```

Ethernet NIC가 세 개 이상이면 TX 측과 RX 측을 순서대로 지정한다.

```bash
sudo ./scripts/apply_br_video.sh <NIC1-TX> <NIC2-RX>
```

bridge member에는 IPv4, DHCP 또는 gateway를 두지 않는다. NAT, masquerade,
MAC rewrite와 user-space video relay도 사용하지 않는다.

## 3. 케이블 연결

1. `br-video`가 올라온 것을 확인한다.
2. 기존 TX↔RX 직결 케이블을 제거한다.
3. `Zybo TX -> Jetson NIC1-TX`를 연결한다.
4. `Jetson NIC2-RX -> Zybo RX`를 연결한다.
5. 두 NIC가 link up, 1 Gb/s, full duplex인지 확인한다.

```bash
bridge link show
bridge fdb show br br-video
ethtool <NIC1-TX>
ethtool <NIC2-RX>
```

기대 FDB는 TX MAC이 NIC1, RX MAC이 NIC2에서 학습되는 상태다. 두 bridge
port를 같은 switch에 함께 연결해 물리 loop를 만들지 않는다.

## 4. 영상·Session gate

짧은 packet capture에서 영상이 다음 계약을 따르는지 확인한다.

```text
Ethernet 02:00:00:00:00:02 -> 02:00:00:00:00:03
IPv4     10.10.15.2 -> 10.10.15.3
UDP      destination port 5602
```

TX와 RX에서는 `aes-session-check tx`, `aes-session-check rx`를 실행해 같은
nonzero active session, `key_valid=1`, `key_ready=1`, `busy=0`, `error=0`인지
확인한다.

## 5. 실제 화면 gate

15초 고정창을 기준으로 다음을 함께 확인한다.

- RX 처리량이 최소 435 frame, 목표 443 frame 이상 증가한다.
- auth/replay/status/queue/stale와 network loss 증가가 0이다.
- Jetson 두 bridge port의 drop/error 증가가 0이다.
- PC 화면의 실제 pixel이 계속 변하고 freeze가 없다.
- PC UART 상태가 online이며 session과 5종 detector 값을 갱신한다.

USB capture만 단독 확인하려면 [`run_preview.bat`](README.md), HDMI와 RX 상태를
통합해 보려면 [PC Receiver Console](../dashboard/README.md)을 사용한다.

## 6. 문제 발생 시

1. 공격 기능을 끈 상태를 유지한다.
2. 두 Ethernet carrier와 bridge link/FDB를 확인한다.
3. TX `.2`, RX `.3` 주소와 UDP 5602 packet을 확인한다.
4. TX/RX active session과 key 상태를 확인한다.
5. RX HDMI content 변화와 PC UART 수신을 서로 분리해 점검한다.
6. 마지막에만 capture handle이나 관련 서비스를 다시 시작한다.

bridge 해제는 Jetson에서 다음을 실행한다.

```bash
sudo ./scripts/rollback_br_video.sh
```
