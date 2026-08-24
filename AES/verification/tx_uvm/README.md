# AES-256-GCM TX 출력 기반 RX 검증 데이터 전달 문서

## 1. 검증 데이터 개요

본 데이터는 다음 TX UVM 검증을 통과한 실제 RTL 출력입니다.

```text
검증명 : C/OpenSSL Golden Model + TX Core Verification
Test   : tx_gcm_stall_test
Seed   : 1234
Result : PASS
```

검증 결과:

```text
Packet count          : 1280
Ciphertext packets    : 1280 / 1280 PASS
AAD packets           : 1280 / 1280 PASS
TAG packets           : 1280 / 1280 PASS
Ciphertext mismatch   : 0
AAD mismatch          : 0
TAG mismatch          : 0
Protocol error        : 0
AXI stall stability   : PASS
```

Ciphertext와 metadata 출력에 독립적인 AXI backpressure를 적용했으며, stall 중 데이터 안정성 오류는 발생하지 않았습니다.

---

## 2. 전달 경로

```text
/home/hedu26/CSA/0813_aes_gcm/results
```

전달 파일:

```text
results/
├── tx_rtl_records_1280.bin
├── tx_rtl_aad_1280.bin
├── tx_rtl_ciphertext_1280.bin
├── tx_rtl_tag_1280.bin
├── plaintext_1280.bin
├── key.bin
├── iv_1280.bin
├── tx_rtl_manifest.txt
├── tx_rtl_result.log
└── README.txt
```

---

## 3. 패킷 규격

```text
Algorithm             : AES-256-GCM
AES Key               : 32 bytes
Nonce                 : 12 bytes
AAD                   : 16 bytes/packet
Ciphertext            : 1440 bytes/packet
Authentication TAG    : 16 bytes/packet
Packet count          : 1280
Packet index          : 0..1279
Session ID            : 0x00000001
Initial Frame ID      : 0x00000000
```

Nonce 규칙:

```text
session_id[31:0]
|| frame_id[31:0]
|| 16'h0000
|| packet_index[15:0]
```

모든 다중 바이트 프로토콜 필드는 network/big-endian 순서입니다.

---

## 4. 통합 record 파일

RX 입력에는 다음 파일을 우선 사용하십시오.

```text
tx_rtl_records_1280.bin
```

패킷 하나의 구조:

```text
AAD         16 bytes
Ciphertext  1440 bytes
TAG         16 bytes
---------------------
Record      1472 bytes
```

전체 구조:

```text
Packet 0   : AAD[16] || Ciphertext[1440] || TAG[16]
Packet 1   : AAD[16] || Ciphertext[1440] || TAG[16]
...
Packet 1279: AAD[16] || Ciphertext[1440] || TAG[16]
```

전체 크기:

```text
1472 × 1280 = 1,884,160 bytes
```

Packet `i` 시작 offset:

```text
i × 1472
```

Packet 내부 offset:

```text
AAD        : record_offset + 0
Ciphertext : record_offset + 16
TAG        : record_offset + 1456
```

---

## 5. 분리 파일

디버깅 또는 RX interface에 맞춘 입력을 위해 다음 파일도 제공합니다.

```text
tx_rtl_aad_1280.bin
tx_rtl_ciphertext_1280.bin
tx_rtl_tag_1280.bin
```

크기:

```text
tx_rtl_aad_1280.bin          : 20,480 bytes
tx_rtl_ciphertext_1280.bin   : 1,843,200 bytes
tx_rtl_tag_1280.bin          : 20,480 bytes
```

각 파일은 packet index 0부터 1279까지 순서대로 연결되어 있습니다.

---

## 6. 복호화 기준 데이터

```text
plaintext_1280.bin
```

크기:

```text
1,843,200 bytes
```

패킷당 1440바이트이며 다음 규칙으로 구성됩니다.

```text
plaintext[packet i][byte j] = (i + j) & 0xFF
```

정상 packet 인증 성공 후 RX 출력 plaintext를 이 파일과 byte 단위로 비교하십시오.

AES key:

```text
key.bin
```

Key 값:

```text
00 01 02 03 04 05 06 07
08 09 0a 0b 0c 0d 0e 0f
10 11 12 13 14 15 16 17
18 19 1a 1b 1c 1d 1e 1f
```

`iv_1280.bin`은 nonce 확인 및 디버깅용입니다.

---

## 7. RX 필수 검증 시나리오

### 정상 패킷

입력:

```text
원본 AAD + 원본 Ciphertext + 원본 TAG
```

예상 결과:

```text
auth_ok
auth_fail 미발생
1440-byte plaintext 정상 출력
plaintext_1280.bin과 byte 단위 일치
```

### TAG 변조

원본 TAG의 특정 bit를 반전합니다.

예:

```text
tampered_tag[0] = original_tag[0] ^ 8'h01
```

예상 결과:

```text
auth_fail
auth_ok 미발생
plaintext 외부 출력 차단
해당 packet 폐기
```

원본 전달 파일을 직접 수정하지 말고 UVM transaction 또는 별도 복사본에서 변조하십시오.

### Ciphertext 변조

원본 ciphertext의 특정 bit를 반전합니다.

예:

```text
tampered_ciphertext[offset] =
    original_ciphertext[offset] ^ 8'h01
```

예상 결과:

```text
auth_fail
auth_ok 미발생
plaintext 외부 출력 차단
해당 packet 폐기
```

### 변조 후 정상 패킷

권장 입력 순서:

```text
정상 packet
→ TAG 변조 packet
→ Ciphertext 변조 packet
→ 다음 정상 packet
```

마지막 정상 packet의 예상 결과:

```text
auth_ok
원본 plaintext 정상 출력
RX 내부 상태 정상 복구
이전 실패 packet의 데이터가 섞이지 않음
```

---

## 8. RX scoreboard 검사 항목

정상 packet:

```text
auth_ok == 1
auth_fail == 0
output payload bytes == 1440
RX plaintext == plaintext_1280.bin
데이터 누락/중복 없음
TKEEP/TUSER/TLAST 정상
```

변조 packet:

```text
auth_ok == 0
auth_fail == 1
외부 plaintext handshake 수 == 0
packet 폐기 확인
```

변조 후 정상 packet:

```text
auth_ok == 1
auth_fail == 0
plaintext 정상 출력
packet/frame index 정상 진행
```

---

## 9. 중요 구현 주의사항

AES-GCM 인증 결과는 TAG 검증 후 확정됩니다.

따라서 `auth_fail` packet의 plaintext 출력 차단을 보장하려면 RX Wrapper가 복호화 데이터를 임시 저장한 뒤 다음 순서로 처리해야 합니다.

```text
Ciphertext 복호화
→ 내부 packet buffer에 임시 저장
→ TAG 인증
→ auth_ok이면 출력
→ auth_fail이면 buffer 폐기
```

인증 전에 plaintext를 외부 AXI stream으로 출력한다면 요구사항인 “인증 실패 시 평문 출력 차단”을 만족하지 못합니다.

또한 원본 TX 결과 파일은 변조하지 말고 읽기 전용 기준 데이터로 유지하십시오.

---

## 10. 파일 무결성

각 파일의 크기와 SHA-256은 다음 파일에 기록되어 있습니다.

```text
tx_rtl_manifest.txt
```

RX 검증 시작 전에 manifest와 실제 파일의 크기 및 SHA-256 일치를 확인하십시오.

TX 검증 결과는 다음 파일에서 확인할 수 있습니다.

```text
tx_rtl_result.log
```

현재 결과:

```text
TEST=tx_gcm_stall_test
SEED=1234
PACKETS=1280
CIPHERTEXT_PACKETS=1280
METADATA_PACKETS=1280
CIPHERTEXT_MISMATCHES=0
AAD_MISMATCHES=0
TAG_MISMATCHES=0
PROTOCOL_ERROR=0
RESULT=PASS
```