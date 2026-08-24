# RX Authentication UVM Verification

`axis_gcm_rx_frame_processor_v2`와 `video_aes_gcm_rx_top`이 인증에 성공한
plaintext만 방출하는지, 실패 packet은 전체 길이를 zero로 대체하는지, 5종 오류
detector가 원인에 맞는 signature를 내는지 검증한다.

## 기준 데이터

[`../tx_uvm/vectors`](../tx_uvm/vectors)의 1,280-packet TX RTL handoff를
RX 입력 형식으로 사용한다. packet record는 다음과 같다.

```text
AAD 16 B || ciphertext 1440 B || TAG 16 B
```

[`verify_golden_vectors.py`](tb/verify_golden_vectors.py)는 manifest SHA-256,
AAD·nonce·plaintext 규칙, Python `cryptography` AESGCM으로 재계산한 ciphertext와
TAG, `data/`의 8·16·1,280 packet prefix를 확인한다.

```powershell
py -3 .\tb\verify_golden_vectors.py
```

## Scoreboard 판정

packet마다 세 조건을 함께 검사한다.

1. 정상 packet은 출력 1,440 B가 expected plaintext와 완전히 같아야 한다.
2. 거부 packet은 출력 1,440 B 전체가 zero여야 한다.
3. TAG/REPLAY/SEQUENCE/SESSION/TIMEOUT 발생 횟수가 scenario의 기대 signature와 같아야 한다.

평문 byte 하나라도 틀리거나, 거부 packet에서 non-zero byte가 하나라도 나오거나,
오류 종류·횟수가 다르면 UVM error로 처리한다.

## Regression scenario

| # | Test | 자극과 기대 결과 |
|---:|---|---|
| 1 | normal | packet 0..7 정상 승인, plaintext 8개 일치 |
| 2 | TAG tamper | packet 1 TAG bit 반전, TAG 1회와 victim zero |
| 3 | ciphertext tamper | packet 1 payload bit 반전, TAG 1회와 victim zero |
| 4 | recovery | 두 변조 packet 차단 뒤 다음 정상 packet 복구 |
| 5 | replay | 승인된 packet 1 재입력, REPLAY+SEQUENCE와 REPLAY 우선 code |
| 6 | sequence | packet index gap, SEQUENCE 1회 |
| 7 | session | grace 이후 foreign session, SESSION 1회 |
| 8 | timeout | 45,000 clock idle, TIMEOUT 1회 |
| 9 | backpressure | 정상 입력에 25% output stall, 판정과 handshake 유지 |
| 10 | full frame | 1,280 packet plaintext 일치, error 0 |

```bash
cd AES/verification/rx_uvm/sim
./run_regression.sh
FULL=1 ./run_regression.sh
```

기본 실행은 1~9번, `FULL=1`은 10번을 추가한다. functional coverage 화면과
각 scenario의 상세 packet 수·판정은 [검증 개요](../README.md)에 수록했다.
