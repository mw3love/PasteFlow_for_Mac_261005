#!/bin/zsh
# 빌드 → .app 조립 → 자체 서명 → ~/Applications 설치 → 실행
# 매번 같은 인증서로 서명해야 손쉬운 사용·화면 기록 권한이 유지된다.
set -euo pipefail

ROOT="${0:A:h:h}"
IDENTITY="PasteFlow Local Signing"
APP="$HOME/Applications/PasteFlow.app"

cd "$ROOT"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/PasteFlow"

pkill -x PasteFlow 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/PasteFlow"
codesign --force --sign "$IDENTITY" --identifier com.minwoo.pasteflow "$APP"

if [[ "${1:-}" != "--no-run" ]]; then
  open "$APP"
fi
echo "설치됨: $APP"
