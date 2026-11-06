# TapDeck

Turn your Mac's trackpad into a shortcut panel.

Tap with three fingers twice to open Claude. Tap four fingers to snap a window. TapDeck reads multi-finger taps, multi-taps, corner taps, and tap-and-hold anywhere in macOS, and runs the action you bound to each one, with as little delay as possible.

> **Status:** early development. Builds and runs from source; no signed release yet.

## Planned for v1

- **Gestures:** 1–5 finger taps, single/double/triple taps, tap-and-hold, corner taps, optional modifier keys
- **Actions:** open or focus an app, send a keyboard shortcut, snap windows, media controls
- **Speed:** a gesture fires as soon as it's unambiguous; sensitivity is adjustable
- Lives in the menu bar, with a live trackpad visualizer for tuning

## Build and run

Requires macOS 14+ and Xcode (Swift 6).

```bash
scripts/build-app.sh --run
```

This builds `dist/TapDeck.app` and launches it in the menu bar. On first launch, TapDeck asks for Accessibility permission, which it needs to send keystrokes, snap windows and use media keys. Opening apps works without it.

To keep the permission across rebuilds, sign with a stable local certificate named `TapDeck Dev`. The script uses it automatically when it's in your keychain; otherwise it signs ad-hoc, and macOS asks again after each rebuild.

Run the tests with `swift test`.

## How it works

TapDeck reads raw finger contacts from Apple's private `MultitouchSupport` framework, the same approach as BetterTouchTool and Jitouch. That's why it ships outside the Mac App Store. Sending keystrokes and moving windows needs Accessibility permission.

## Requirements

macOS 14 Sonoma or later, with a built-in trackpad or Magic Trackpad.

## License

MIT
