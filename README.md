# Rheinluft

FPGA 기반 광통신과 암호화 영상 전송을 한곳에 모은 팀 통합 저장소입니다. 하드웨어에 합성되는 RTL부터 Jetson 중간 노드, PC 모니터링 화면, 재현 가능한 검증 코드까지 소스 중심으로 정리했습니다.

## 프로젝트

| 프로젝트 | 핵심 내용 | 주요 장비 | 상세 문서 |
|---|---|---|---|
| Rolling-Shutter OCC | LED의 시간축 변조를 카메라 행 밝기로 복조하고 자격증명·CRC를 판정 | Basys3, OV7670, LED 송신부 | [Rolling_Shutter_OCC](Rolling_Shutter_OCC/README.md) |
| AES-256-GCM Secure Video | 카메라 영상을 FPGA에서 암호화하고 중간 공격·수신 인증·오류 탐지를 시연 | Pcam, Zybo Z7-20 TX/RX, Jetson Orin Nano, PC | [AES](AES/README.md) |

## 전체 구성

```text
Rolling-Shutter OCC
  Basys3 Tag + LED  ──광 신호──>  OV7670 + Basys3 Reader
                                      └─ credential / CRC / UART

AES-256-GCM Secure Video
  Pcam ─> Zybo TX ──암호화 UDP──> Jetson 2-NIC ──공격/관찰──> Zybo RX
           │                           │                         │
           └─ AES-256-GCM              ├─ Tamper / Replay       ├─ 인증·복호화
              Session key             └─ Weak-key / VLM        └─ HDMI + UART
                                                                    │
                                                                    v
                                                               PC Console
```

AES 데모의 FPGA·네트워크·대시보드 관계는 다음과 같습니다.

![AES-256-GCM 영상 보안 데모 전체 구성](AES/assets/system_overview.png)

## 데모

### Rolling-Shutter OCC

![Rolling-shutter 행 밝기에서 OCC 패킷을 복원하는 데모](Rolling_Shutter_OCC/assets/rolling_shutter_occ_demo.gif)

밝고 어두운 수평 밴드를 행 단위로 분석해 동기워드, 16비트 자격증명과 CRC를 복원합니다. RTL, 보드 제약, 카메라 수신 도구와 실제 하드웨어 사진은 [OCC 문서](Rolling_Shutter_OCC/README.md)에 정리돼 있습니다.

### AES 보안 영상 수신

![RX HDMI 영상과 보안 상태를 함께 표시하는 PC 수신 콘솔](AES/assets/pc_receiver.png)

PC 콘솔은 RX HDMI 영상, Jetson 공격 상태, RX의 인증·재전송·순서·세션·타임아웃 탐지 결과를 한 화면에 모읍니다. 변조·재전송·약한 키 탐색과 VLM 분석 화면은 [AES 문서](AES/README.md#데모-화면)에서 볼 수 있습니다.

## 저장소 구조

```text
Rheinluft/
├── Rolling_Shutter_OCC/   Rolling-shutter 광통신 RTL과 도구
├── AES/
│   ├── fpga/              Zybo TX/RX RTL, PetaLinux, 세션 제어, STM32
│   ├── jetson/            2-NIC bridge, 보안 대시보드, 공격·분석 엔진
│   ├── pc/                수신 콘솔과 HDMI 미리보기
│   ├── verification/      NIST KAT, C/FPGA 비교, TX/RX UVM, loopback
│   └── assets/            README용 구조도·장비·데모 화면
└── README.md
```

## 정리 기준

- 합성·빌드·실행에 필요한 소스와 설정, 테스트벤치와 골든 벡터를 우선 보존했습니다.
- PPT에서는 전체 구조와 검증 요약 슬라이드만 PNG로 추출했고, 실제 데모 캡처는 주제별 대표 화면만 사용했습니다.
- DOC/DOCX/PPTX, 압축본, Vivado·VCS 생성물, 실행 바이너리, 로컬 VLM 모델과 런타임은 저장소에서 제외했습니다.
- PC별 환경 값은 실제 설정 파일 대신 예시 파일만 포함합니다.
- 하위 구성요소의 기존 문서에는 개발 당시 장비 경로가 남아 있을 수 있으며, 현재 저장소의 기준 경로는 이 README와 각 프로젝트 최상위 README입니다.
