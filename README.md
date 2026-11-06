# TapDeck

Turn your Mac's trackpad into a shortcut panel.

Tap with three fingers twice to open Claude. Tap four fingers to snap a window. TapDeck reads multi-finger taps, multi-taps, corner taps, and tap-and-hold anywhere in macOS, and runs the action you bound to each one, with as little delay as possible.

> **Status:** early development. Builds and runs from source; no signed release yet.

## Planned for v1

- **Gestures:** 1–5 finger taps, single/double/triple taps, tap-and-hold, corner taps, optional modifier keys
- **Actions:** open or focus an app, send a keyboard shortcut, snap windows, media controls
- **Speed:** a gesture fires as soon as it's unambiguous; sensitivity is adjustable
- Lives in the menu bar, with a live trackpad visualizer for tuning

## Install

Download the latest `TapDeck-<version>.dmg` from [Releases](https://github.com/Saba-Burduli/tapdeck/releases), open it, and drag TapDeck to Applications.

Until releases are notarized by Apple, macOS blocks TapDeck the first time you open it. Go to **System Settings → Privacy & Security** and click **Open Anyway**.

On first launch, TapDeck asks for **Accessibility** permission, which it needs to send keystrokes, snap windows and use media keys. Opening apps works without it.

## Build and run

Requires macOS 14+ and Xcode (Swift 6).

```bash
scripts/build-app.sh --run
```

This builds `dist/TapDeck.app` and launches it in the menu bar. On first launch, TapDeck asks for Accessibility permission, which it needs to send keystrokes, snap windows and use media keys. Opening apps works without it.

To keep the permission across rebuilds, sign with a stable local certificate named `TapDeck Dev`. The script uses it automatically when it's in your keychain; otherwise it signs ad-hoc, and macOS asks again after each rebuild.

Run the tests with `swift test`.

## Releasing

Push a version tag, for example `git tag v0.1.0 && git push origin v0.1.0`. The release workflow then tests and builds the DMG and creates a **draft** GitHub release for you to review and publish. To package locally, run `scripts/package-release.sh`.

To sign and notarize releases, add these repository secrets. Without them, releases are ad-hoc signed:
- `DEVELOPER_ID_P12`: your Developer ID Application certificate, exported as `.p12` and base64-encoded
- `DEVELOPER_ID_P12_PASSWORD`: the password for that `.p12`
- `SIGN_IDENTITY`: the certificate name, `Developer ID Application: Your Name (TEAMID)`
- `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`: your Apple ID, team ID and an app-specific password

A Homebrew cask template is in `packaging/homebrew/tapdeck.rb`.

## How it works

TapDeck reads raw finger contacts from Apple's private `MultitouchSupport` framework, the same approach as BetterTouchTool and Jitouch. That's why it ships outside the Mac App Store. Sending keystrokes and moving windows needs Accessibility permission.

## Requirements

macOS 14 Sonoma or later, with a built-in trackpad or Magic Trackpad.

## License

MIT
