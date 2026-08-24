# Nucleo-F411RE 통신 검증 자료

빌드는 `arm-none-eabi-gcc` 등이 `PATH`에 있으면 `baremetal_uart_echo`에서 `make`를 실행하면 된다. 툴체인을 `PATH`에 넣지 않은 Windows 환경은 다음처럼 해당 PC의 설치 폴더만 환경변수로 지정한다.

```powershell
$env:ARM_GNU_TOOLCHAIN_DIR = '<Arm GNU Toolchain 설치 폴더>'
mingw32-make
```

Makefile에는 공유한 PC의 절대경로나 특정 GCC 버전을 저장하지 않는다. GCC driver가 현재 툴체인과 맞는 include/multilib를 자동 선택한다.

`baremetal_uart_echo`에는 실기 테스트에 사용한 최소 베어메탈 소스와 ST-LINK drag-and-drop용 `known_1203.hex`만 있다. `.o`, `.elf`, `.map`, dump 같은 재생성 찌꺼기는 제외했다.

TX Zybo의 외부전원 USB 허브에 Nucleo를 연결하면 PetaLinux에서 ST-LINK와 `/dev/ttyACM0`가 함께 나타났다. `known_1203.hex`를 ST-LINK에 기록하고 보드 RESET 후 Zybo에서 문자 `Q`를 보냈을 때 Nucleo 응답 `Data = Q`를 받아 양방향 통신을 확인했다.

현재 펌웨어는 통신 확인용이다. 실제 데모에서는 다음처럼 확장한다.

- Zybo → Nucleo: `SESSION_START`, `KEY_OK`, `AUTH_FAIL`, frame/drop 통계
- Nucleo → Zybo: 세션 시작 버튼 또는 로그 dump 요청
- 절대 전송하지 않을 값: AES 세션 키, RX RSA 개인키

Nucleo는 RSA를 깨는 장치로 가정하지 않는다. 재전송/변조된 제어 메시지를 주입하고 Zybo가 거부하는 과정을 보여주는 보조 제어·로그 장치가 적절하다.
