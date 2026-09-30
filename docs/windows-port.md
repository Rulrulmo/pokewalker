# 윈도우 버전 — 로드맵

> 2026-09-30 결정: **Swift 공통 코어 + 플랫폼 껍데기**, 테스트는 사용자 윈도우 PC, 첫 버전은 **Mac과 거의 동일**.

## 지금 코드가 어디에 묶여 있나

- **플랫폼과 무관 (약 80%)**: `Model` · `Battle` · `Data`, LCD 그림(`FB`/`Pic`, RouteArt · MoveFX · BallFX · WalkFX · Notebook · Stroll · Anim), 버튼 흐름(Flow · Compose · BattleView).
- **Mac 전용 (약 1,400줄)**:
  - `WalkerView`: NSView, 카드·LCD 그리기, 입력
  - `SidePanel`: 패널 페이지 그리기
  - `Menu`: NSMenu
  - `Device`: 색 · UserDefaults
  - `Pixels`: NSImage 변환 · 글자 크기
  - `App/main.swift`: 창 · 상태 막대 · 알림
  - 걸음(`CGEventSource`), `Bundle.main`, `NSData` 압축 해제, osascript 알림

## 구조 (목표)

```
Sources/Core/     Foundation만: 모델 · 배틀 · 데이터 · Walker(상태+흐름, 옛 WalkerView의 몸통)
                  · Canvas 프로토콜로 그리는 카드/LCD/패널 · MenuItem 모델 · Settings · Resources · Inflate
Sources/Mac/      AppKit: NSView가 Walker를 들고 이벤트 전달 · CGCanvas · NSMenu 변환 · 상태 막대 · 알림 · 걸음
Sources/Windows/  Win32: 레이어드 창 · 소프트웨어 Canvas(픽셀 버퍼 + GDI 글자) · 트레이 · 메뉴 · Raw Input 걸음 · 토스트
Tests/            셀프테스트(코어만 사용 → 윈도우 CI에서도 돎)
```

- **Walker**: 지금 `WalkerView`의 저장 프로퍼티와 `extension WalkerView`(Flow/Compose/…)를 `final class Walker`로 옮긴다.
  - 플랫폼에 부탁할 것은 `Host` 프로토콜로 받는다: 다시 그리기(LCD만 / 전부), 카드 높이 바꾸기, 알림, 메뉴 열기.
- **Canvas**: 사각형 · 둥근 사각형 · 원 · 경로 채우기/선, 이미지(픽셀 버퍼, 최근접 확대, 투명도, 회전), 글자(크기 · 굵기 · 색 · 정렬, 폭 재기), 클립, 저장/복원, 그라데이션 하나.
  - Mac은 CoreGraphics로 지금과 **픽셀 단위로 같게** 그린다.
- **Menu**: 제목 · 켜짐/꺼짐 · 체크 · 하위 메뉴 · 동작(클로저) 트리. Mac은 NSMenu로, 윈도우는 HMENU로 바꾼다.
- **Settings**: 키-값 저장. Mac은 UserDefaults, 윈도우는 `%APPDATA%\PokeWalker\settings.json`.
- **세이브**: 같은 `state.json` 형식이다(Mac ↔ 윈도우로 옮길 수 있음). 윈도우는 `%APPDATA%\PokeWalker\`.
- **Inflate**: `anims.bin` · `walk.bin`의 raw DEFLATE를 순수 Swift로 푼다(`NSData.decompressed`는 Apple 전용).

## 윈도우 껍데기

- **창**: `WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW`. `UpdateLayeredWindow`로 픽셀 알파를 그대로 올리고(둥근 카드), 드래그로 옮긴다. 모니터 DPI에 맞춰 크기를 정한다(보통 · 크게 · 아주 크게 = ×1 · ×1.5 · ×2).
- **그리기**: 코어가 `Canvas`로 그린 것을 소프트웨어 래스터라이저가 BGRA 버퍼에 그린다. 도형은 직접 그리고, 글자는 GDI(맑은 고딕 / Galmuri)로 흰색 마스크를 뽑아 알파로 합성한다. COM(Direct2D)은 쓰지 않아서 Swift에서 다루기 쉽다.
- **트레이**: `Shell_NotifyIcon`. 좌클릭은 보이기/숨기기, 우클릭은 메뉴(`TrackPopupMenu`, 코어의 MenuItem 트리).
- **걸음**: `RegisterRawInputDevices(RIDEV_INPUTSINK)`로 키 누름·마우스 클릭 **횟수만** 센다(내용은 안 봄, 권한 불필요).
  - Mac과 달리 앱을 꺼 둔 동안의 입력은 셀 수 없다.
- **알림**: 트레이 풍선(`NIIF_INFO`)으로 보낸다. 토스트(WinRT)는 나중에.
- **타이머**: `SetTimer` 100ms(평소)와 33ms(배틀·연출 중)로 `walker.tick` / `frame`을 부른다.

## 빌드 · 배포

- `Package.swift`(SwiftPM): Core 라이브러리 + Mac 실행 파일 + Windows 실행 파일. Mac의 `./build.sh`는 지금처럼 쓴다.
- **GitHub Actions** `windows-latest`에 Swift 툴체인(`compnerd/gha-setup-swift`)을 깔고 `swift build -c release`와 셀프테스트를 돌린다. 산출물은 zip이다(exe + Swift 런타임 DLL + Resources).
  - 비공개 저장소라 Actions 무료 분(윈도우는 2배 차감)을 쓴다.
- 서명이 없으니 처음 실행할 때 SmartScreen에서 "추가 정보 → 실행"을 누른다.

## 단계

| 단계 | 내용 | 끝났다는 기준 |
|---|---|---|
| **P1 코어 분리 (Mac)** | Walker · Canvas · Menu · Settings · Resources · Inflate. Mac 껍데기가 새 구조로 돎 | 화면 60여 개 골든 렌더가 **픽셀 단위로 동일**, 셀프테스트 수 동일, 앱 정상 |
| **P2 윈도우 컴파일** | Package.swift + Actions. 코어 + 셀프테스트가 윈도우에서 빌드·통과 | CI 초록 |
| **P3 윈도우 껍데기** | 창 · 소프트웨어 Canvas · 트레이 · 메뉴 · 걸음 · 설정 · 알림 | 사용자 PC에서 홈 · 레이더 · 배틀 · 패널 페이지가 Mac과 같게 보임 |
| **P4 다듬기** | 글꼴 폭 차이, DPI, 여러 모니터, 시작 시 자동 실행(선택) | 스크린샷 비교 |

## 열린 점

- 윈도우 글꼴: Mac의 시스템 글꼴(SF) 대신 맑은 고딕을 쓴다. 폭이 달라서 줄바꿈과 잘림을 한 번 맞춰야 한다.
- 윈도우 on ARM: 우선 x64만 낸다(ARM PC에서는 에뮬레이션으로 돎).
