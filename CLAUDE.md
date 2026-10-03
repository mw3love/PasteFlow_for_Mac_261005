# CLAUDE.md

## 프로젝트 개요

윈도우용 PasteFlow(https://github.com/mw3love/Paste_flow)의 사용감을 맥에서 잇는 개인용 맥 앱. Swift 네이티브로 처음부터 만든다.
목표·범위·제약·만드는 순서는 `PLAN.md`가 기준이다. 결정이 바뀌면 `PLAN.md`부터 고친다.

## 작업 규칙

- 윈도우판 코드는 동작 규칙(특히 순차 큐 규칙)을 확인하는 참고용이다. 파이썬 코드를 그대로 옮기지 않는다.
- 큐·DB 같은 로직은 테스트 먼저, UI·권한·키 주입은 직접 빌드·실행해 확인한다.
- 빌드 결과는 항상 같은 자체 서명 인증서로 서명한다(권한 유지).

## 명령어

```bash
swift test                 # 로직 테스트 (PasteFlowCore)
scripts/build.sh           # 빌드 → ~/Applications/PasteFlow.app 조립·서명 → 실행
scripts/build.sh --no-run  # 실행 없이 설치만
```

- 구조: `Sources/PasteFlowCore`(로직·테스트 대상) / `Sources/PasteFlow`(AppKit 앱) / `Resources/Info.plist`(LSUIElement — Dock 없이 메뉴바만).
- 서명 인증서: 로그인 키체인의 자체 서명 `PasteFlow Local Signing`(codeSigning, 2026-10-03 생성, 10년). 신뢰 설정 없이도 서명된다. 지정 요구사항 = `identifier "com.minwoo.pasteflow" and certificate leaf = H"53a1…"` → 재빌드해도 같은 앱으로 인식. **인증서를 지우거나 새로 만들면 권한을 다시 줘야 한다.**
- 실행 기록: `~/Library/Logs/PasteFlow/status.log` — 실행마다 권한 상태와 메뉴바 아이콘 위치를 남긴다. 2026-10-03 재빌드 3회 이상에서 두 권한 모두 유지 확인.

## 이 맥의 환경 함정

- **Hidden Bar**가 설치돼 있어 새 메뉴바 아이콘이 구분선 왼쪽(화면 밖, x≈-4262)으로 숨는다. 아이콘이 "안 뜬다"는 보고는 먼저 `status.log`의 `statusItem frame`을 볼 것.
- macOS 26에서는 메뉴바 아이콘 창 소유자가 모두 "제어 센터"로 잡혀 `CGWindowList`로 앱별 아이콘을 구분할 수 없다.
- **Karabiner-Elements** 실행 중 — 키 감시·주입 작업 때 키 재매핑과 겹치는지 확인할 것.
- 터미널에 화면 기록 권한이 있어 `screencapture`로 자체 확인 가능(2026-10-03 부여).
