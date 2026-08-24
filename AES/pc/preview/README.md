# ZYBO RX HDMI PC 미리보기

`run_preview.bat`을 실행하면 `USB3. 0 capture`의 1280×720 MJPG 영상을 실제 Windows 창으로 표시한다.

## 최초 설치

Python 3가 설치된 Windows PC에서 다음 중 하나를 실행한다.

```bat
setup_venv.bat
```

또는 바로 `run_preview.bat`을 실행한다. `.venv`가 없으면 실행기가 자동으로 가상환경을 만들고 `requirements.txt`의 고정 버전을 설치한다.

```text
numpy==2.2.6
opencv-python==4.12.0.88
```

`.venv`는 PC별 생성물이므로 source tree 밖에서 다시 만들 수 있다.

## 사용

- 종료: `Q` 또는 `Esc`
- 필요할 때만 수동 원본 프레임 저장: `S`
- 실시간 수치: `live_metrics.json`

창의 `capture fps`는 HDMI 720p60 carrier 수신률이다. Zybo RX의 authenticated/display content rate 약 30fps와 혼동하지 않는다. `PIXELS CHANGING`과 `change events`는 decoded PC 프레임의 실제 픽셀 변화이며, carrier가 살아 있어도 같은 화면만 반복되면 `PIXELS STATIC`으로 표시된다.

사진 찌꺼기가 쌓이지 않도록 자동 PNG 저장은 하지 않는다. `S`를 누른 경우에만 `manual_날짜_시간.png` 한 장을 저장한다.

TX/RX 사이에 Jetson 2-NIC Linux bridge를 연결할 때는
[`JETSON_2NIC_중간삽입_재배선_운용README.md`](JETSON_2NIC_중간삽입_재배선_운용README.md)를
따른다. 영상과 RX 보안 상태를 한 화면에서 보려면
[PC Receiver Console](../dashboard/README.md)을 사용한다.
