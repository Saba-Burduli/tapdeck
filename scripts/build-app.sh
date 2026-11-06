#!/bin/zsh
# Builds the TapDeck menu bar app as dist/TapDeck.app.
#
#   scripts/build-app.sh            release build
#   scripts/build-app.sh --run      build, quit any running TapDeck, launch the new one
#   scripts/build-app.sh --debug    debug build (faster to compile)
#
# Signs with the local "TapDeck Dev" certificate when present, so macOS keeps the
# Accessibility permission across rebuilds; otherwise signs ad-hoc.
set -euo pipefail
cd "${0:A:h}/.."

config=release
run=false
for arg in "$@"; do
  case $arg in
    --run) run=true ;;
    --debug) config=debug ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

version=$(git describe --tags --always 2>/dev/null || echo 0.1.0)
app=dist/TapDeck.app
bundle_id=com.saba-burduli.tapdeck

swift build -c "$config" --product TapDeck
bin=$(swift build -c "$config" --show-bin-path)/TapDeck

# Quit the running app and the dev spike so gestures don't fire twice.
pkill -x TapDeck 2>/dev/null || true
pkill -f "TapDeck.app/Contents/MacOS/TapDeck" 2>/dev/null || true

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/TapDeck"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleName</key><string>TapDeck</string>
  <key>CFBundleDisplayName</key><string>TapDeck</string>
  <key>CFBundleExecutable</key><string>TapDeck</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${version#v}</string>
  <key>CFBundleVersion</key><string>$(git rev-list --count HEAD 2>/dev/null || echo 1)</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

identities=$(security find-identity -p codesigning)   # not piped: grep -q + pipefail = SIGPIPE
if [[ "$identities" == *'"TapDeck Dev"'* ]]; then
  identity="TapDeck Dev"
else
  identity="-"
  echo "note: no 'TapDeck Dev' certificate; signing ad-hoc (Accessibility resets each rebuild)" >&2
fi
codesign --force --options runtime --sign "$identity" --identifier "$bundle_id" "$app"
echo "Built $app ($config, signed: $identity)"

if $run; then
  open "$app"
fi
