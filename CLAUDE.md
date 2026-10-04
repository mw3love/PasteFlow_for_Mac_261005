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
- 붙여넣기: `KeyInterceptor`(CGEventTap, 글자가 아니라 키 코드로 판정 → 한글 입력 중에도 동작, `tapDisabledByTimeout` 시 다시 켬) → `PasteController`(큐에서 꺼내 클립보드에 원본 형식 그대로 쓰고 50ms 뒤 ⌘V 주입, 전체 자동은 300ms 간격, 경로 붙여넣기는 `$TMPDIR/PasteFlow/*.png` — 24시간 지난 파일은 시작 시 정리) → `PasteHUD`(포커스 안 뺏는 NSPanel, 전체 화면 앱 위에도 뜸, 소진 1.2초 뒤 fade).
  - **주입한 ⌘V 구분**: 주입 이벤트의 `eventSourceUserData`에 표식(`KeyInterceptor.injectedMarker`)을 붙이고, 탭에서 표식 없는 ⌘V만 "사용자가 누른 일반 ⌘V"로 보고 큐를 비운다. 주입 ⌘V는 플래그를 ⌘만으로 고정해 사용자가 ⇧·⌥·⌃를 누르고 있어도 앱에는 ⌘V로 보인다.
  - 큐 비우기 공통 경로: 일반 ⌘V·HUD ✕·소진 완료 모두 `PasteController`에서 처리.
  - 2026-10-03 실조건검증(사용자가 TextEdit·터미널에서 직접): 순차 순서, 일반 ⌘V로 큐 비움, `⌃⌘V` 이미지 경로 모두 정상. Karabiner(선택 프로필에 재매핑 규칙 없음)와 충돌 없음.
- 패널(`ClipPanel.swift`, AppKit — `⌥` 드래그 판정·키 처리를 직접 다루려고 SwiftUI 대신 선택): `⌥Space` 토글, 다른 앱을 활성화하지 않는 NSPanel이지만 키 입력은 받음(그래서 Enter 붙여넣기가 원래 앱으로 감). 키: ↑↓ 선택, Enter 붙여넣기(⌥Enter=경로), Space/더블클릭 미리보기, P 고정, C 큐 지정/해제, O 파일 위치 열기, ⌫ 삭제(큐 동기화), ⌘C 복사, Esc 닫기. 우클릭에 "수정"(글자 항목, `TextEditWindow` — ⌘Enter 저장, 닫으면 원래 앞 앱으로 돌려줌). 목록은 `withFormats: false`로 원본 없이 읽고, 필요할 때만 `db.item(id:)`.
  - 함정 1: 목록을 다시 그린 직후 `scrollToVisible`을 부르면 배치 전 위치로 계산돼 맨 아래로 튄다 → `layoutSubtreeIfNeeded()` 후 스크롤, 다시 그릴 때 원래 스크롤 위치 복원.
  - 함정 2: `isMovableByWindowBackground` 창에서 글자 칸(NSTextField)을 누르면 창 이동으로 처리된다 → 항목 뷰가 `hitTest`로 클릭을 직접 받고 `mouseDownCanMoveWindow = false`.
  - 2026-10-03 사용자 실조건검증: 선택·고정·삭제·미리보기·Enter 붙여넣기·우클릭·끌어다 놓기(글자·이미지, ⌥ 경로) 모두 정상.
  - 큐 지정(C, Core `QueueSelection` — 윈도우판 `_on_queue_select`): 히스토리는 고른 것→최신, 고정은 고른 것→첫 고정(역순). 큐 맨 앞 항목에서 다시 C = 해제. 윈도우판과 달리 지정 뒤 선택 표시를 지우지 않음(같은 항목에서 C로 바로 해제하려고).
  - 파일 위치 열기(O): 이미지 = 캡처 저장 파일(`saved_image_path` — `ScreenController`가 저장 후 `ClipboardMonitor.attachSavedPath`로 그 changeCount 항목에 붙임), Finder 복사 = 그 파일, 글자 = 경로 글자일 때. 이 기능 전 캡처는 경로가 없어 비활성.
  - 글자 수정(`ClipDatabase.updateText`): 원본 형식(HTML·RTF)을 버리고 평문 하나로(윈도우판과 같음).
  - 끌기: 끌기 항목에 내부 형식(`.pasteFlowItem` = id)을 같이 실어, 패널 안 고정 영역(`PanelListView`, 구분선 위)에 놓으면 고정 순서 바꾸기(Core `PinOrder` + `setPinOrder`)·히스토리는 그 자리에 고정. 히스토리 순서 바꾸기는 없음(윈도우판엔 있음). 윈도우판의 "히스토리→고정 드롭"은 코드만 있고 실제 끌기 방식에선 안 걸리는 것으로 보여(추정) 맥판은 위처럼 정함.
  - 함정 3: 키 창이 아닌 패널의 첫 클릭은 창 깨우기로만 쓰여 항목이 mouseDown을 못 받는다 → 끌기가 안 시작됨. `ClipItemView.acceptsFirstMouse = true`.
  - 함정 4: 다른 앱에 놓아도 키보드는 패널에 남는다(앱을 앞으로 안 부르는 창) → `draggingSession(_:endedAt:operation:)`에서 놓은 지점의 맨 앞 창(layer 0) 앱을 `activate()`, 그 앱이 이미 맨 앞이면 이것만으론 안 돌아오므로 패널을 `orderOut` → `orderFrontRegardless`(키 없이)로 키보드를 놓아 줌. 패널은 안 닫음.
  - 2026-10-04 사용자 실조건검증: C 큐 지정·해제, O 파일 위치, 글자 수정, 고정 순서 끌기, 히스토리→고정 끌기, 비활성 패널에서 바로 끌기, 다른 앱에 놓은 뒤 바로 타자 모두 정상.
- 캡처·핀(`ScreenController`): `⌘⇧2` → `ScreenSnapshot`(ScreenCaptureKit으로 모니터별 "얼린" 화면 + `CGWindowListCopyWindowInfo` 창 사각형·앱 pid, 실측 44~122ms) → `CaptureOverlay`(모니터마다 NSPanel, 요소·창 하이라이트 클릭 / 4pt 이상 끌면 자유 사각형 / 우클릭·Esc 취소 / Space 실제 커서 포함) → PNG(144dpi 기록)를 클립보드에 올려 **감시기가 일반 복사처럼** 히스토리·큐에 넣게 하고, `~/Pictures/PasteFlow/clip_YYYYMMDD_HHMMSS.png` 저장(설정 키 `capture_save_folder`로 바꿀 수 있음) + `Toast`. `⌘⇧1` → 큐에 다음이 있으면 그것(포인터 공유), 없으면 클립보드 이미지/글자(글자는 M1 카드 이미지로, 경로 붙여넣기 PNG 경로면 원본 복원). 마지막 캡처와 같은 이미지는 캡처한 자리에 핀.
  - `CGWindowListCreateImage`는 이 SDK(macOS 26)에서 **사용 불가**(컴파일 오류) → ScreenCaptureKit 필수.
  - 첫 캡처 때 맥이 "시스템 개인정보 보호 윈도우 선택기를 우회하여 화면에 직접 접근" 허용 창을 따로 띄운다(화면 기록 권한과 별개). 사용자가 허용함(2026-10-03). 다시 묻는 주기는 확인 필요.
  - 한계: 자유 드래그 선택은 시작한 모니터 안으로 한정(여러 모니터 걸침 합성 없음).
  - 요소 스냅(`ElementSnapper` + Core `ElementSnap`): 커서가 움직일 때마다 얼려 둔 창의 앱(pid)에 `AXUIElementCopyElementAtPosition`으로 묻고 부모 쪽 최대 8단계만 본다(1회 1~2ms). 규칙(윈도우판과 같은 뜻): 창 위 28pt(제목 막대)·`AXWindow`/`AXToolbar` = 창 전체, 8pt 미만은 부모, 버튼·링크 안 글자·그림은 바깥 요소, 창 넓이 90% 이상 = 창 전체, 요소는 창 안으로 자름.
  - 크롬 계열은 웹페이지 안 접근성 정보를 꺼 둔다 → 앱 시작·새 앱 실행 3초 뒤 `AXEnhancedUserInterface`를 설정해 깨운다(실측: 오류 -25208을 돌려주지만 약 1.5초 뒤 켜지고 유지. `AXManualAccessibility`는 크롬이 거부 -25205). 일렉트론은 `AXManualAccessibility`(미측정 — VS Code를 뒤에서 열면 창이 안 떠서 못 잼). 다른 앱은 건드리지 않음. 크롬 성능 영향은 확인 필요.
  - 2026-10-04 사용자 실조건검증: 요소 하이라이트·클릭 캡처 정상.
  - 2026-10-03 사용자 실조건검증: 창 클릭·자유 드래그 캡처, 패널·`⌃⌘V` 연동, 캡처 3장 순차 핀, 글자 핀 모두 정상.
- OCR(`⌘⇧E`, `GatewayOCR` in Core + `ScreenController.recognize`): 캡처 오버레이를 OCR 모드로 재사용 → jbnu 게이트웨이(`/chat/completions`, 브라우저형 UA — Cloudflare 1010 회피, `max_tokens` 16384 — 생각 토큰 때문에 작으면 잘림) → 글자를 클립보드에 올려 감시기가 히스토리·큐에 넣음 → 성공 시 크레딧 캐시 갱신. 설정창 OCR 탭 `OCRSettingsPane`([저장] 버튼 — 키 입력이 있어서): 모델 콤보 + 새로고침(`/models` 전체, 거르지 않음 → DB `ocr_models_cache`), 연결 테스트(앱 안 한글 샘플, **폴백 없이** 고른 모델만), 크레딧(`/credits/` → DB `ocr_credits_text`).
  - API 키: `SecretStore` 파일(`~/Library/Application Support/PasteFlow/secrets/ocr_api_key`, 600/700). **키체인 쓰지 말 것** — 팀 ID 없는 자체 서명 앱은 빌드마다 비밀번호 창이 뜸(추정: 키체인이 앱 지문 cdhash로 기억). 터미널 `security`로 읽어도 매번 창이 뜸.
  - **메뉴를 열 때 네트워크·비밀값을 건드리지 말 것** — 메뉴가 키보드를 잡고 있어 그때 뜬 시스템 창에 입력이 안 된다(실사례). 메뉴는 캐시 값만.
  - 키를 붙여넣으려고 복사하면 히스토리에 기록된다 → 저장 시 `ClipDatabase.deleteItems(withPlainText:)`로 같은 내용 삭제. 빈 클립보드는 기록 안 함(`ClipClassifier.isEmpty`).
  - 이 맥에는 `~/.claude/.secrets/`(kairos 키 파일)가 없다 — git 동기화에서 빠지는 파일.
  - 2026-10-03 실측(한글 샘플): 3.5-flash-lite 2.1~2.9초, 3.1-flash-lite 1.6~2.0초, 3.8-flash 2.8~3.5초, 모두 정확. 호출당 크레딧 약 1. 사용자 실조건검증: 새로고침·연결 테스트·실제 OCR 정상.
- 주석 편집기(`AnnotationCanvas`·`AnnotationToolbar` + Core `Annotation`/`AnnotationDocument`/`AnnotationDefaults`): 핀에서 Space(미리보기 창의 Space는 그 자리에 핀으로 바꿔 바로 편집) → 이미지 아래에 도구 막대가 붙고 창이 그만큼 아래로 늘어난다(이미지 자리 그대로).
  - 도구·숫자키는 윈도우판 순서: 1 선택 · 2 네모 · 3 텍스트 · 4 화살표 · 5 원 · 6 선 · 7 펜 · 8 번호(⌥+숫자도 같음, 키 코드로 판정). 범위는 "기본 먼저"(2026-10-03 사용자 결정) — 회전·곡선 화살표·테두리 스냅·스포이드·텍스트 배경은 실사용 뒤 필요하면.
  - 규칙: 4pt 미만으로 끈 도형은 버림, 그린 뒤 자동 선택(펜 제외), 그리기 도구에선 네모·원 획 위만 잡힘(안쪽에서 새로 그리기 가능), ⇧ = 정사각·정원·45°. 손잡이: 네모·원·펜·텍스트·번호는 오른쪽 아래, 선·화살표는 양 끝.
  - 키: Enter·⌘C 복사, ⌘Z/⌘⇧Z, ⌫ 삭제, 방향키 이동(⇧=1pt), `[` `]` 크기, Esc 선택 해제→편집 끝. 텍스트는 Enter 줄바꿈, ⌘Enter·Esc·바깥 클릭으로 끝.
  - 색·크기는 도구마다 따로 기억(DB `annot_tool_defaults` JSON). 선택된 주석이 있으면 막대의 색·크기가 그 주석에 적용된다.
  - 복사 = 원본 픽셀 해상도로 다시 그린 PNG를 클립보드에 → 감시기가 히스토리·큐에 넣음(캡처와 같은 경로). 주석은 핀에 벡터로 남아 다시 편집 가능.
  - 2026-10-03 프록시검증(자동 입력): 8도구 그리기·번호 자동 증가·글자·복사(800×600 결과, 히스토리 기록)·되돌리기. 같은 날 사용자 실조건검증: 캡처→핀→편집→복사→다른 앱 붙여넣기, 끌기·손잡이, 한글 글자 입력 모두 정상.
- 설정창(`SettingsWindow`, 메뉴바 "설정…"·패널 빈 곳 우클릭·실행 중인 앱을 다시 열 때): 탭 일반 / 단축키 / OCR. 일반·단축키는 바꾸는 즉시 저장·적용.
  - 단축키: Core `HotkeyMap`(기본값 위에 바꾼 것만 DB `hotkeys` JSON) → `KeyInterceptor.map`을 갈아 끼워 재시작 없이 적용. 일반 `⌘V`는 큐 비우기 신호라 `Hotkeys.isPlainPaste`로 고정. 검사: ⌘·⌃·⌥ 하나는 필수, 예약 키(⌘V/C/X/Z/A/Q/W, ⌘Tab, ⌘Space, ⌃Space, ⌘⇧3/4/5) 거부, 다른 동작과 중복 거부, 알려진 겹침은 경고만. 녹화 중엔 `KeyInterceptor.isRecording`으로 전역 단축키가 키를 삼키지 않게 한다.
  - 일반: 자동 시작(`SMAppService.mainApp` — 한 번도 등록 안 한 상태도 `.notFound`로 나옴), 큐 새 묶음 시간(DB `queue_idle_reset_sec`), 캡처 저장 폴더(`capture_save_folder`), 확인 알림 켜기/끄기(`toast_enabled`).
  - 2026-10-03: 사용자 실조건검증 — 단축키를 바꾸면 재시작 없이 새 키로 동작. 자동 시작은 자체 서명 앱에서도 등록 성공(status=enabled), 실제 로그인 후 실행은 미확인(맥을 거의 안 꺼서 나중에 — 안 켜지면 그때 수정).
  - macOS 14+는 활성화가 양보식이라 `NSApp.activate`만으로는 설정창이 다른 앱 창 뒤에 남는다 → `orderFrontRegardless()`.
- 알림(`Toast`): 주 모니터 오른쪽 아래에 최신이 맨 아래로 최대 5개 쌓임. `key`가 같으면 그 자리에서 바뀜(OCR 진행→결과). 알림을 꺼도 `always: true`(실패·OCR)는 뜬다.
- 한 번만 실행: 이미 떠 있으면 새 쪽이 분산 알림으로 설정창을 열게 하고 끝남. Finder에서 다시 열기(`applicationShouldHandleReopen`)도 설정창.
- 자체 시험 함정: 이 맥의 사용자는 Chrome 전체 화면을 자주 띄워 두므로, 자동 키 입력 시험 중 맨 앞 창이 바뀌어 주입한 ⌘V가 엉뚱한 앱으로 갈 수 있다. 실제 붙는 결과는 사용자 직접 확인이 확실하다.
- 데이터: `~/Library/Application Support/PasteFlow/pasteflow.db` (히스토리 50개, 고정 제외).
- 알려진 한계: 클립보드에 항목이 여러 개면(Finder에서 파일 여러 개 복사 등) 첫 항목만 보존한다. 32MB 넘는 형식 하나는 건너뛴다.
- 실행 기록: `~/Library/Logs/PasteFlow/status.log` — 복사마다 `copy id=… kind=… queue=p/total` 한 줄도 남는다. — 실행마다 권한 상태와 메뉴바 아이콘 위치를 남긴다. 2026-10-03 재빌드 3회 이상에서 두 권한 모두 유지 확인.

## 이 맥의 환경 함정

- **Hidden Bar**가 설치돼 있어 새 메뉴바 아이콘이 구분선 왼쪽(화면 밖, x≈-4262)으로 숨는다. 아이콘이 "안 뜬다"는 보고는 먼저 `status.log`의 `statusItem frame`을 볼 것.
- macOS 26에서는 메뉴바 아이콘 창 소유자가 모두 "제어 센터"로 잡혀 `CGWindowList`로 앱별 아이콘을 구분할 수 없다.
- **Karabiner-Elements** 실행 중 — 키 감시·주입 작업 때 키 재매핑과 겹치는지 확인할 것.
- 터미널에 화면 기록 권한이 있어 `screencapture`로 자체 확인 가능(2026-10-03 부여).
