# AES-256 순수 C 대 FPGA 코어 검증 결과

## 결과

| 조건 | 순수 C | FPGA 150 MHz | FPGA 성능 |
|---|---:|---:|---:|
| 키 확장 포함 | 6.2024 ms | 2.799993 ms | 2.215배 빠름 |
| 키 확장 제외 | 2.3442 ms | 0.999993 ms | 2.344배 빠름 |

- 암호화 결과: C와 FPGA 모두 OpenSSL 골든 레퍼런스와 10,000/10,000건 일치
- 처리 속도: FPGA가 직접 구현한 순수 C보다 키 확장 포함 2.215배, 제외 2.344배 빠름

## 비교 조건

- 결과 정확성은 OpenSSL AES-256을 골든 레퍼런스로 삼아 C와 FPGA 출력을 비교했다.
- 처리 속도는 FPGA AES-256 코어와 직접 구현한 스칼라 C AES-256 코어를 비교했다.
- 양쪽 모두 동일한 키와 평문 10,000개를 사용했다.
- OpenSSL 실행 시간과 파일 입출력 시간은 성능 측정에서 제외했다.

## 이렇게 비교한 이유

OpenSSL은 검증된 구현이므로 정답 확인에 적합하지만, CPU의 AES 전용 가속기를 사용할 수 있어 FPGA와의 속도 비교 기준으로는 공정하지 않다. 따라서 결과 검증에만 OpenSSL을 사용하고, 속도는 AES-NI·VAES·PCLMUL 없이 직접 구현한 순수 C와 비교해 FPGA 코어 자체의 성능 차이를 확인했다.

## 한 번에 실행

PowerShell에서 다음을 실행한다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_all.ps1
```

필요 도구는 PATH의 GCC/OpenSSL/objdump와 `D:\2025.2\Vivado\bin`의 Vivado Simulator 2025.2다. 최종 결과는 `results\comparison.md`, 원시 측정값은 `results\c_results.txt`와 `results\rtl_results.txt`에 저장된다.

## 측정 조건

- 알고리즘: AES-256 ECB, 128-bit 단일 블록 10,000개
- 키 확장 포함: 매 레코드의 서로 다른 키를 확장한 뒤 한 블록 암호화
- 키 확장 제외: 첫 번째 키를 한 번만 미리 확장/적재하고 10,000개 블록 암호화
- C: 스칼라 소스 직접 구현, CPU 0 고정, warm-up 뒤 11회 중앙값
- FPGA: 원본 AES RTL, Vivado cycle-accurate 시뮬레이션, 실제 설계의 150 MHz로 환산
- 제외 시간: 파일 I/O, 벡터 생성, OpenSSL 실행, 컴파일, RTL elaboration/시뮬레이터 벽시계 시간

C 컴파일은 자동 벡터화와 AES/CLMUL/AVX/AVX2를 끈다. 빌드된 실행 파일은 objdump로 검사하며 AES-NI, VAES, PCLMUL 명령어가 하나라도 있으면 전체 실행이 실패한다.

## 폴더 구성

- `src`: 순수 C AES-256 코어와 CPU 벤치마크
- `rtl`: 원본 TX AES RTL 복사본, SHA-256 출처 명세, 비교 테스트벤치
- `tools`: OpenSSL 골든 벡터 생성기
- `vectors`: 양쪽에 공통으로 입력되는 10,000개 벡터
- `tests`: KAT, 출처, 금지 명령어, 10,000건 결과 일치 검사
- `scripts`: 전체 재현 및 Vivado 시뮬레이션 실행기
- `results`: C/RTL 원시 결과와 최종 비교표
