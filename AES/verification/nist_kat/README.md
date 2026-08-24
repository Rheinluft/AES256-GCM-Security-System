# AES-256 코어 KAT 검증

`aes256_iterative_core`(AES-256 ECB 블록 암호화)를 NIST 표준 벡터로 검증한다.
정답은 NIST가 배포한 값을 그대로 쓰므로, 이 프로젝트의 코드는 정답 생성에
전혀 관여하지 않는다.

## 보존된 검증 결과

| DUT | 시뮬레이터 | 벡터 | 결과 | 일자 | 근거 |
|---|---|---:|---:|---|---|
| `aes256_iterative_core` | Synopsys VCS W-2024.09-SP1 | 405 | **405 pass, 0 fail** | 2026-08-13 | [실행 로그](../../reference/original_aes256_gcm_core/verification/nist_aes256_kat/results/vcs_aes256_iterative_core_20260813.txt) |

Vivado xsim 실행 스크립트도 함께 제공되지만, 현재 저장소에 보존된 2026-08-13
`aes256_iterative_core` 실행 근거는 위 VCS 로그와 Verdi 화면이다. 독립형 참고
폴더에 있는 2026-08-17 xsim 405-vector 로그는 DUT가
`rtl/aes256_core.sv`인 별도 실행이므로 이 결과와 합쳐 표기하지 않는다.

## 벡터 출처

NIST CAVP(Cryptographic Algorithm Validation Program)의 AESAVS 테스트 벡터.

```
https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Algorithm-Validation-Program/documents/aes/KAT_AES.zip
```

zip 안의 72개 `.rsp` 중 이 코어(ECB, 256비트)에 해당하는 4개만 `kat_vectors/`에
둔다. 각 파일의 `[ENCRYPT]` 섹션만 사용한다 — 이 코어는 암호화 전용이다.

| 파일 | 벡터 수 | 고정 | 변화 | 노리는 것 |
|---|---|---|---|---|
| `ECBGFSbox256.rsp` | 5 | 키=0 | 평문 | S-box 기본 동작 |
| `ECBKeySbox256.rsp` | 16 | 평문=0 | 키 | 키 확장 경로 |
| `ECBVarKey256.rsp` | 256 | 평문=0 | 키 1비트씩 | 키 256비트 전부 반영되는지 |
| `ECBVarTxt256.rsp` | 128 | 키=0 | 평문 1비트씩 | 평문 128비트 전부 반영되는지 |
| **합계** | **405** | | | |

VarKey 256개 / VarTxt 128개는 각각 키 비트 수, 평문 비트 수와 일치한다. 비트를
하나씩 켜가며 출력에 영향을 주는지 전수 확인하는 구조라, 배선이 끊기거나
인덱스가 밀리면 여기서 걸린다.

## 검증 방식

```
.rsp 파싱
  KEY (256b) ──► aes256_key_expansion ──► round_keys (1920b, RK0~RK14)
                                               │
  PLAINTEXT (128b) ────────────────────────────┼──► aes256_iterative_core
                                               ▼
                                          data_out (128b)
                                               │
  CIPHERTEXT (128b) ──────► 비교 ◄─────────────┘
```

TB가 `.rsp`를 중간 변환 없이 직접 읽는다. `CIPHERTEXT` 줄을 만난 시점에
KEY/PLAINTEXT가 모두 채워져 있으므로 거기서 한 벡터를 실행하고, `done`이 뜨는
클럭에서 `data_out`을 샘플해 기대값과 비교한다.

키 확장은 별도로 검사하지 않는다. 라운드키가 하나라도 틀리면 암호문이 반드시
달라지므로, 405개 통과 자체가 `aes256_key_expansion`이 옳다는 증거다.

## 실행

### Synopsys VCS (Linux)

```bash
cd uvm_verification
make sim
```

파형까지 보려면:

```bash
make gui                  # Verdi 인터랙티브 (프롬프트에서 run)
make sim WAVE=1 MAXV=5    # FSDB 파일로 남기기
make verdi                # 남은 FSDB 열기
```

기타 타겟은 `make help`.

### Vivado xsim (Windows)

```powershell
.\sim\run_aes_core_kat.ps1
.\sim\run_aes_core_kat.ps1 -DumpWave      # 파형 기록 후 GUI로 열기
```

두 플로우는 `filelist.f` 하나를 공유하므로 동일한 소스 목록으로 다시 실행할 수 있다.

## 예상 출력

```
========================================================
 AES-256 ECB Known Answer Test (NIST AESAVS)
 DUT        : aes256_iterative_core
 Vector dir : ./kat_vectors
========================================================
  ECBGFSbox256.rsp   vectors=5    fail=0   PASS
  ECBKeySbox256.rsp  vectors=16   fail=0   PASS
  ECBVarKey256.rsp   vectors=256  fail=0   PASS
  ECBVarTxt256.rsp   vectors=128  fail=0   PASS
--------------------------------------------------------
 TOTAL      : 405 vectors, 0 fail
 key expand : 274 times
--------------------------------------------------------
 RESULT     : PASS - all 405 NIST AESAVS vectors matched
========================================================
```

시뮬레이션 시간 141,640 ns. `key expand : 274`는 키 확장이 실제로 274회
실행됐다는 뜻이다 (GFSbox/VarTxt는 키가 고정이라 매번 재확장하지 않는다).

## 검증 범위

**포함** — AES-256 ECB 블록 암호화, 키 확장.

**미포함** — GCM 조립부. GHASH 체인, CTR 카운터 시작값, AXIS 바이트 순서,
프로토콜 처리는 이 KAT의 대상이 아니다. `video_aes_gcm_tx_top` 레벨의 검증이
따로 필요하며, 그쪽은 고정 포맷(AAD 16B / 평문 1440B / 96비트 구조화 IV)이라
NIST GCM 벡터를 그대로 쓸 수 없고 골든 벡터를 별도로 생성해야 한다.

## 주의: 종료 코드를 믿으면 안 된다

xsim은 2020.2/2025.2 양쪽에서 `$fatal`로 죽으면서도 **종료 코드 0**을 반환한다.
종료 코드만 확인하면 벡터 불일치가 조용히 통과로 넘어간다. 그래서 런처와
Makefile 모두 로그의 최종 판정문(`RESULT     : PASS`)을 직접 확인한다. CI에
연결할 때도 이 방식을 유지해야 한다.

TB의 mismatch 경로는 기대 암호문 한 글자를 바꾸는 역검증으로 확인할 수 있다.
해당 벡터에서 FAIL과 KEY/PT/EXP/GOT가 출력되어야 한다.

## 파일 구성

```
uvm_verification/
├─ Makefile            VCS 플로우
├─ filelist.f          소스 목록 (VCS/xsim 공유, 패키지가 맨 앞)
├─ aes256_gcm/         RTL
├─ tb/
│  └─ tb_aes256_core_kat.sv
├─ kat_vectors/        NIST .rsp 4개
├─ sim/
│  └─ run_aes_core_kat.ps1   Vivado xsim 런처 (Windows)
└─ logs/               make sim 실행 로그 (타임스탬프)
```

`filelist.f`는 패키지(`aes_sbox_pkg`, `aes_key_rcon_pkg`)를 맨 앞에 둔다.
`aes_subbytes.sv`와 `aes_subword32.sv`가 module 선언 밖(compilation-unit
스코프)에서 import하므로 순서가 바뀌면 컴파일이 깨진다.

`novas_sim_*`, `csrc/`, `simv*`는 시뮬레이터가 만드는 임시 산출물이다.
`make clean`으로 지운다.
