# Verification

AES-256 블록 코어의 표준 벡터부터 TX 패킷 생성, RX 인증·복호화, 실제 TX 출력의 RX handoff까지 검증 계층을 분리해 보관합니다.

![AES 코어·TX·RX 단계별 검증 구성](../assets/verification_overview.png)

## 검증 계층

| 디렉터리 | DUT / 범위 | 입력과 판정 |
|---|---|---|
| [`nist_kat`](nist_kat/README.md) | AES-256 ECB core와 key expansion | NIST AESAVS 405 vectors, 405/405 PASS |
| [`aes256_c_vs_fpga`](aes256_c_vs_fpga/README.md) | 순수 C AES-256과 FPGA RTL core | OpenSSL golden, 10,000/10,000 양쪽 일치 |
| [`tx_uvm`](tx_uvm/README.md) | `video_aes_gcm_tx_top` | 1280 packets의 AAD/ciphertext/TAG와 stall 안정성 |
| [`rx_uvm`](rx_uvm/) | RX authentication/decryption과 5종 detector | 정상·tamper·replay·sequence·session·timeout·backpressure |
| [`tx_rx_loopback`](tx_rx_loopback/) | TX record에서 RX plaintext까지 | 8/16/1280-packet handoff vectors |

NIST KAT 소스는 기존 `tar.gz`에서 `uvm_verification/`만 풀어 넣었습니다. VCS/xsim 실행 바이너리, coverage DB와 로그는 제외했고, 표준 벡터·RTL·TB·filelist·실행 스크립트만 보존했습니다.

## 실행

### NIST AES-256 KAT

Synopsys VCS:

```bash
cd AES/verification/nist_kat/uvm_verification
make sim
```

Vivado xsim:

```powershell
cd AES\verification\nist_kat\uvm_verification
.\sim\run_aes_core_kat.ps1
```

두 실행 경로 모두 로그 안의 `RESULT : PASS`를 확인합니다. 일부 xsim 버전은 `$fatal`이 발생해도 종료 코드 0을 반환할 수 있기 때문에 종료 코드만으로 성공을 판단하지 않습니다.

### C/OpenSSL ↔ RTL 비교

GCC, OpenSSL, objdump와 Vivado Simulator 2025.2가 필요합니다.

```powershell
cd AES\verification\aes256_c_vs_fpga
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_all.ps1
```

이 플로우는 OpenSSL로 정답 벡터를 만들고, AES-NI·VAES·PCLMUL·자동 벡터화를 끈 순수 C 구현과 150 MHz RTL cycle model의 결과 및 시간을 비교합니다.

### TX UVM

`tx_uvm/rtl`과 `tx_uvm/tb`가 UVM 환경이며, `tx_uvm/vectors`에는 RX handoff용 1280-packet 결과가 있습니다.

```text
AAD 16 B | Ciphertext 1440 B | TAG 16 B = Record 1472 B
```

### RX UVM / TX-RX loopback

각 폴더의 `sim/rtl.f`, `compile_rtl.sh`, `run_uvm.sh` 또는 `run_regression.sh`를 사용합니다. UVM은 정상 packet 외에도 TAG/Cipher tamper, replay, sequence, session, timeout, backpressure와 recovery를 검사합니다.

## 소프트웨어 검사

Jetson backend:

```bash
cd AES/jetson/dashboard
python3 -m unittest discover -s tests -p 'test_*.py'
```

Jetson UI:

```bash
cd AES/jetson/dashboard/dashboard-source
npm ci
npm test
```

PC backend와 UI:

```powershell
cd AES\pc\dashboard
py -3 .\server.py --self-test
node --test .\web\tests\*.test.js
```

## 기준 소스

운영 FPGA 정본은 `../fpga/tx/vivado/rtl`과 `../fpga/rx/vivado/rtl`입니다. 검증 폴더의 RTL 복사본은 각 테스트의 기존 filelist와 handoff를 그대로 재현하기 위해 유지하며, 새 기능을 수정할 때는 운영 정본을 먼저 바꾸고 검증 복사본의 동일성도 함께 확인해야 합니다.
