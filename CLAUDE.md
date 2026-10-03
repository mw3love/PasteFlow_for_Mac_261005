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
- 로직(Core, 테스트 있음): `PasteQueue`(순차 큐 — 윈도우판 규칙 그대로), `ClipDatabase`(SQLite, 시스템 `SQLite3` 모듈 — 외부 패키지 없음), `ClipItem`(원본 형식을 type→Data로 전부 보존), `ClipClassifier`(종류·미리보기·비밀번호 관리자 표시 형식 건너뛰기).
- 앱: `ClipboardMonitor`는 `NSPasteboard.changeCount`를 0.25초마다 확인(맥은 변경 알림이 없음). 실측 CPU 0.0%. 앱이 직접 쓴 클립보드는 `noteSelfChange()`로 표시해 다시 기록하지 않는다.
- 붙여넣기: `KeyInterceptor`(CGEventTap, 키 코드 V=9로 판정 → 한글 입력 중에도 동작, `tapDisabledByTimeout` 시 다시 켬) → `PasteController`(큐에서 꺼내 클립보드에 원본 형식 그대로 쓰고 50ms 뒤 ⌘V 주입, 전체 자동은 300ms 간격, 경로 붙여넣기는 `$TMPDIR/PasteFlow/*.png` — 24시간 지난 파일은 시작 시 정리) → `PasteHUD`(포커스 안 뺏는 NSPanel, 전체 화면 앱 위에도 뜸, 소진 1.2초 뒤 fade).
  - **주입한 ⌘V 구분**: 주입 이벤트의 `eventSourceUserData`에 표식(`KeyInterceptor.injectedMarker`)을 붙이고, 탭에서 표식 없는 ⌘V만 "사용자가 누른 일반 ⌘V"로 보고 큐를 비운다. 주입 ⌘V는 플래그를 ⌘만으로 고정해 사용자가 ⇧·⌥·⌃를 누르고 있어도 앱에는 ⌘V로 보인다.
  - 큐 비우기 공통 경로: 일반 ⌘V·HUD ✕·소진 완료 모두 `PasteController`에서 처리.
  - 2026-10-03 실조건검증(사용자가 TextEdit·터미널에서 직접): 순차 순서, 일반 ⌘V로 큐 비움, `⌃⌘V` 이미지 경로 모두 정상. Karabiner(선택 프로필에 재매핑 규칙 없음)와 충돌 없음.
- 패널(`ClipPanel.swift`, AppKit — `⌥` 드래그 판정·키 처리를 직접 다루려고 SwiftUI 대신 선택): `⌥Space` 토글, 다른 앱을 활성화하지 않는 NSPanel이지만 키 입력은 받음(그래서 Enter 붙여넣기가 원래 앱으로 감). 키: ↑↓ 선택, Enter 붙여넣기(⌥Enter=경로), Space/더블클릭 미리보기, P 고정, ⌫ 삭제(큐 동기화), ⌘C 복사, Esc 닫기. 목록은 `withFormats: false`로 원본 없이 읽고, 필요할 때만 `db.item(id:)`.
  - 함정 1: 목록을 다시 그린 직후 `scrollToVisible`을 부르면 배치 전 위치로 계산돼 맨 아래로 튄다 → `layoutSubtreeIfNeeded()` 후 스크롤, 다시 그릴 때 원래 스크롤 위치 복원.
  - 함정 2: `isMovableByWindowBackground` 창에서 글자 칸(NSTextField)을 누르면 창 이동으로 처리된다 → 항목 뷰가 `hitTest`로 클릭을 직접 받고 `mouseDownCanMoveWindow = false`.
  - 2026-10-03 사용자 실조건검증: 선택·고정·삭제·미리보기·Enter 붙여넣기·우클릭·끌어다 놓기(글자·이미지, ⌥ 경로) 모두 정상.
  - 윈도우판에 있는데 아직 없는 것: 큐에 추가/해제(C), 고정 항목 드래그로 순서 바꾸기, 히스토리→고정 영역 드롭, 고정 글자 수정, 파일 위치 열기(캡처 항목 — 저장 경로를 DB `saved_image_path`에 아직 안 넣음).
- 캡처·핀(`ScreenController`): `⌘⇧2` → `ScreenSnapshot`(ScreenCaptureKit으로 모니터별 "얼린" 화면 + `CGWindowListCopyWindowInfo` 창 사각형, 실측 44~122ms) → `CaptureOverlay`(모니터마다 NSPanel, 창 하이라이트 클릭 / 4pt 이상 끌면 자유 사각형 / 우클릭·Esc 취소 / Space 실제 커서 포함) → PNG(144dpi 기록)를 클립보드에 올려 **감시기가 일반 복사처럼** 히스토리·큐에 넣게 하고, `~/Pictures/PasteFlow/clip_YYYYMMDD_HHMMSS.png` 저장(설정 키 `capture_save_folder`로 바꿀 수 있음) + `Toast`. `⌘⇧1` → 큐에 다음이 있으면 그것(포인터 공유), 없으면 클립보드 이미지/글자(글자는 M1 카드 이미지로, 경로 붙여넣기 PNG 경로면 원본 복원). 마지막 캡처와 같은 이미지는 캡처한 자리에 핀.
  - `CGWindowListCreateImage`는 이 SDK(macOS 26)에서 **사용 불가**(컴파일 오류) → ScreenCaptureKit 필수.
  - 첫 캡처 때 맥이 "시스템 개인정보 보호 윈도우 선택기를 우회하여 화면에 직접 접근" 허용 창을 따로 띄운다(화면 기록 권한과 별개). 사용자가 허용함(2026-10-03). 다시 묻는 주기는 확인 필요.
  - 한계: 자유 드래그 선택은 시작한 모니터 안으로 한정(여러 모니터 걸침 합성 없음). 요소 단위 스냅 없음(PLAN.md v1 마지막 단계).
  - 2026-10-03 사용자 실조건검증: 창 클릭·자유 드래그 캡처, 패널·`⌃⌘V` 연동, 캡처 3장 순차 핀, 글자 핀 모두 정상.
- 자체 시험 함정: 이 맥의 사용자는 Chrome 전체 화면을 자주 띄워 두므로, 자동 키 입력 시험 중 맨 앞 창이 바뀌어 주입한 ⌘V가 엉뚱한 앱으로 갈 수 있다. 실제 붙는 결과는 사용자 직접 확인이 확실하다.
- 데이터: `~/Library/Application Support/PasteFlow/pasteflow.db` (히스토리 50개, 고정 제외).
- 알려진 한계: 클립보드에 항목이 여러 개면(Finder에서 파일 여러 개 복사 등) 첫 항목만 보존한다. 32MB 넘는 형식 하나는 건너뛴다.
- 실행 기록: `~/Library/Logs/PasteFlow/status.log` — 복사마다 `copy id=… kind=… queue=p/total` 한 줄도 남는다. — 실행마다 권한 상태와 메뉴바 아이콘 위치를 남긴다. 2026-10-03 재빌드 3회 이상에서 두 권한 모두 유지 확인.

## 이 맥의 환경 함정

- **Hidden Bar**가 설치돼 있어 새 메뉴바 아이콘이 구분선 왼쪽(화면 밖, x≈-4262)으로 숨는다. 아이콘이 "안 뜬다"는 보고는 먼저 `status.log`의 `statusItem frame`을 볼 것.
- macOS 26에서는 메뉴바 아이콘 창 소유자가 모두 "제어 센터"로 잡혀 `CGWindowList`로 앱별 아이콘을 구분할 수 없다.
- **Karabiner-Elements** 실행 중 — 키 감시·주입 작업 때 키 재매핑과 겹치는지 확인할 것.
- 터미널에 화면 기록 권한이 있어 `screencapture`로 자체 확인 가능(2026-10-03 부여).
