#!/bin/zsh
# Builds the spike, wraps it as .build/TapDeck.app, and launches it through
# LaunchServices so macOS attributes permissions (Accessibility) to TapDeck
# itself rather than to whatever terminal started it. Output goes to
# .build/TapDeck.log, which this script follows. Ctrl-C stops following AND quits the app.
#
# Usage: scripts/run-spike-app.sh [spike flags, default --gestures]
set -euo pipefail
cd "${0:A:h}/.."

args=("${@:---gestures}")
app=.build/TapDeck.app
log=.build/TapDeck.log

swift build -q --product tapdeck-spike

pkill -f "$app/Contents/MacOS/TapDeck" 2>/dev/null || true
mkdir -p "$app/Contents/MacOS"
cp .build/debug/tapdeck-spike "$app/Contents/MacOS/TapDeck"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.saba-burduli.tapdeck.spike</string>
  <key>CFBundleName</key><string>TapDeck</string>
  <key>CFBundleExecutable</key><string>TapDeck</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
# Sign with the local "TapDeck Dev" certificate when present, so macOS keeps the
# Accessibility permission across rebuilds. Ad-hoc signatures change every build.
identities=$(security find-identity -p codesigning)   # not piped: grep -q + pipefail = SIGPIPE
if [[ "$identities" == *'"TapDeck Dev"'* ]]; then
  identity="TapDeck Dev"
else
  identity="-"
  echo "note: no 'TapDeck Dev' certificate; ad-hoc signing (Accessibility resets each rebuild)" >&2
fi
codesign --force --sign "$identity" --identifier com.saba-burduli.tapdeck.spike "$app"

: > "$log"
open -n "$app" --stdout "$log" --stderr "$log" --args "${args[@]}"
trap 'pkill -f "$app/Contents/MacOS/TapDeck" 2>/dev/null; exit 0' INT TERM HUP EXIT
tail -f "$log"
