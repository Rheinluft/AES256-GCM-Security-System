# Jetson Local VLM

Weak-Key 검색으로 복구한 이미지 또는 사용자가 고른 이미지 한 장을 Jetson에서 분석한다.

## 구성

- Jetson Orin Nano 8GB
- NVIDIA Cosmos-Reason2-2B Q4_K_M GGUF
- F16 vision projector GGUF
- CUDA-enabled llama.cpp
- 앱/API 포트 `4188`
- model server 포트 `4190`
- cloud API 없음

## 실행

```bash
cd /home/jetson/local-vlm-test
./start.sh
```

서비스 실행:

```bash
systemctl --user enable --now zybo-local-vlm.service
```

브라우저에서 `http://<Jetson 주소>:4188/`을 열고 이미지를 선택한 뒤 분석 버튼을 누른다. 이미지 선택만으로 inference가 시작되지 않는다.

## 파일

- `app.py`: 이미지 검증, llama.cpp 요청, 결과 정규화, 웹 API
- `web/`: 독립 테스트 UI
- `start.sh`, `stop.sh`, `start_model.sh`: 수동 실행 스크립트
- `run-vlm-service.sh`, `zybo-local-vlm.service`: 부팅 후 서비스 실행
- `TEST_RESULTS.md`: 2026-08-12 cold/warm 및 Page 03 recovered-frame 분석 결과
- `samples/`: 검증에 사용한 입력 이미지

환경 변수 `VLM_TEST_PORT`, `VLM_MODEL_PORT`, `VLM_MODEL_API`, `VLM_MODEL_NAME`으로 실행값을 바꿀 수 있다.

`start_model.sh`는 장비의 `models/Cosmos-Reason2-2B-Q4_K_M.gguf`,
`models/mmproj-Cosmos-Reason2-2B-F16.gguf`와
`runtime/llama.cpp/build/bin/llama-server`를 사용한다. 모델과 CUDA llama.cpp
runtime은 용량과 장비 의존성 때문에 이 저장소에는 포함되어 있지 않으므로 Jetson의
`/home/jetson/local-vlm-test` 아래에 별도로 배치해야 한다.

## 실장비 검증 기록

- 2026-08-17 장비 시험에서 user service가 enabled/active 상태였고 API 4188과 model server 4190의 listening을 확인했다.
- 시험 장비의 Cosmos model SHA-256은 `3ed011641891e81fe654328071de251718832e7deafef579033485d33082e4fd`였다.
- 시험 장비의 vision projector SHA-256은 `8d3284c340d6a9c9237d56f2fc42f2df50d3761f539f3f01be964cefb0b73916`였다.
- 분석 입력과 결과 요약은 [`TEST_RESULTS.md`](TEST_RESULTS.md)와 `samples/`에 남겨 두었다.
