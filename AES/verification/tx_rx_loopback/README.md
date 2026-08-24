# TX RTL → RX Loopback Verification

TX UVM이 만든 1,280-packet AES-256-GCM record를 RX RTL에 그대로 입력해
authenticate-before-release와 plaintext 복원을 확인한다. RX용 ciphertext를
별도로 다시 만들지 않으므로 TX와 RX 사이의 byte order, AAD, nonce와 TAG 계약을
종단으로 검사할 수 있다.

## 입력 데이터

원본 handoff는 [`../tx_uvm/vectors`](../tx_uvm/vectors)에 있다.

```text
tx_rtl_records_1280.bin
  = 1280 × (AAD[16] || ciphertext[1440] || TAG[16])

plaintext_1280.bin
  = 1280 × 1440-byte expected plaintext
```

`data/`의 8·16·1,280 packet 파일은 이 두 파일의 정확한 prefix다.
[`verify_tx_handoff.py`](tb/verify_tx_handoff.py)는 다음을 검사한다.

1. manifest의 크기와 SHA-256
2. AAD/ciphertext/TAG interleave
3. `PCAM` AAD, structured nonce, plaintext pattern
4. 8·16·1,280 packet loopback 파일의 prefix 일치
5. Python `cryptography` AESGCM을 이용한 1,280 packet TAG 인증과 평문 복원

```powershell
py -3 .\tb\verify_tx_handoff.py
```

## RX regression

VCS/UVM 환경에서:

```bash
cd AES/verification/tx_rx_loopback/sim
./run_regression.sh
FULL=1 ./run_regression.sh
```

기본 회귀는 정상, TAG tamper, ciphertext tamper, recovery, replay, sequence,
session, timeout, backpressure 9개 시나리오를 실행한다. `FULL=1`은 1,280 packet
full-frame 정상 시나리오를 추가한다.

합격 조건은 정상 packet의 1,440-byte plaintext 완전 일치, 거부 packet의
1,440-byte zero substitution, 기대 error signature 일치와 UVM error/fatal 0이다.
보존된 결과는 8/16/1,280 packet handoff가 모두 PASS했으며 상세 시나리오와
RX functional coverage는 [검증 개요](../README.md)에 정리했다.
