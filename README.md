# TapDeck

Turn your Mac's trackpad into a shortcut panel.

Tap with three fingers twice to open Claude. Tap four fingers to snap a window. TapDeck reads multi-finger taps, multi-taps, corner taps, and tap-and-hold anywhere in macOS, and runs the action you bound to each one, with as little delay as possible.

> **Status:** early development. Not usable yet.

## Planned for v1

- **Gestures:** 1–5 finger taps, single/double/triple taps, tap-and-hold, corner taps, optional modifier keys
- **Actions:** open or focus an app, send a keyboard shortcut, snap windows, media controls
- **Speed:** a gesture fires as soon as it's unambiguous; sensitivity is adjustable
- Lives in the menu bar, with a live trackpad visualizer for tuning

## How it works

TapDeck reads raw finger contacts from Apple's private `MultitouchSupport` framework, the same approach as BetterTouchTool and Jitouch. That's why it ships outside the Mac App Store. Sending keystrokes and moving windows needs Accessibility permission.

## Requirements

macOS 14 Sonoma or later, with a built-in trackpad or Magic Trackpad.

## License

MIT
