# AES_GCM_TX — PL 직결 암호화 경로

## 데이터 경로

```text
Pcam MIPI → PL YUYV16 → pack128 → PL AES-256-GCM
→ unpack16 → VFB Write → DDR ciphertext frame → PS UDP
```

암호화 전 카메라 평문을 DDR에 쓰는 구형 AXI DMA/ACP 왕복 경로는 제거했다. SW3 plaintext demo를 명시적으로 선택한 경우만 bypass한다.

## 자동 부팅

- USB Wi-Fi는 키 교환 전용이며 실제 인터페이스를 자동 탐색한다.
- 부팅 순서와 link 준비 시간에 무관하게 RX 발견과 키 교환을 재시도한다.
- 기본 상태는 secure session이다.
- persistent state 기본값은 `/var/lib/aes-session`이며 SD label/automount 경로에 의존하지 않는다.
- PL runtime reset 뒤에도 level-held session key를 자동으로 다시 expand한다.

## SD

SD 배포 시에는 같은 빌드에서 만든 `BOOT.BIN`, `boot.cmd`, `boot.scr`,
`image.ub`, `system.bit`, `system.dtb`, `README.md`, `SHA256SUMS` 8개를 FAT32 첫
파티션 루트에 함께 복사하고 hash를 검증한다. 이 저장소에는 재생성에 필요한
Vivado/PetaLinux source와 script가 있다.

## JTAG

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\petalinux\JTAG_RAM_BOOT\run_jtag_boot.ps1"
```

현장 기본값은 Pcam이 검출되는 TX cable `210351BE7DF5A`, COM9다. 스크립트 인자나 환경변수로 바꿀 수 있으며 소스의 PC 절대경로에는 의존하지 않는다.

## 검증값

- WNS `+0.121 ns`, WHS `+0.015 ns`, DRC error 0
- BIT `F1CC57FBE2FF1A66863D371CA41C5DF4907BC26113AF8395BE5D0C4B2DF1E588`
- XSA `8DC586999DE1EBA439184843B7CA67ADCF53A3AE93B3EC504AAE5E8D9AEB3F59`
- JTAG cold boot secure session `0x8e332bbf`, PC UART 약 30 fps, auth reject 0

packet 단위 검증과 재현 명령은 [검증 문서](../../verification/README.md), TX/RX
전체 연결은 [FPGA 설계 문서](../README.md)를 참조한다.
