#!/bin/zsh
# Builds dist/TapDeck.app and packages it as dist/TapDeck-<version>.dmg.
#
# Notarizes automatically when all of these are set (otherwise the DMG is
# unsigned/ad-hoc and users must approve it in System Settings on first open):
#   SIGN_IDENTITY       "Developer ID Application: Your Name (TEAMID)"
#   APPLE_ID            Apple ID email
#   APPLE_TEAM_ID       10-character team ID
#   APPLE_APP_PASSWORD  app-specific password from appleid.apple.com
#
# Prints the DMG path and its SHA-256 (for the Homebrew cask).
set -euo pipefail
cd "${0:A:h}/.."

version=${VERSION:-$(git describe --tags --always 2>/dev/null || echo 0.1.0)}
version=${version#v}
app=dist/TapDeck.app
dmg=dist/TapDeck-$version.dmg

scripts/build-app.sh

notarize=false
if [[ -n "${SIGN_IDENTITY:-}" && -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  notarize=true
fi

submit() {   # notarize a file and wait for Apple's verdict
  xcrun notarytool submit "$1" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" --wait
}

if $notarize; then
  echo "Notarizing app…"
  ditto -c -k --keepParent "$app" dist/TapDeck-notarize.zip
  submit dist/TapDeck-notarize.zip
  rm dist/TapDeck-notarize.zip
  xcrun stapler staple "$app"
fi

# DMG with the app and an Applications shortcut for drag-to-install.
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -volname "TapDeck" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null

if $notarize; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$dmg"
  echo "Notarizing DMG…"
  submit "$dmg"
  xcrun stapler staple "$dmg"
fi

echo "DMG: $dmg"
echo "Notarized: $notarize"
echo "SHA-256: $(shasum -a 256 "$dmg" | cut -d' ' -f1)"
