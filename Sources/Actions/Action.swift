/// Something TapDeck does when a gesture fires. Codable so bindings can be saved.
public enum Action: Hashable, Codable, Sendable, CustomStringConvertible {
    /// Open (or focus) an app. With `toggle`, hide it instead when it's already in front.
    case openApp(bundleID: String, toggle: Bool = true)
    /// Send a keyboard shortcut to the frontmost app.
    case keystroke(KeyCombo)
    /// Move or resize the focused window.
    case window(WindowCommand)
    /// Media and volume keys.
    case media(MediaKey)

    public var description: String {
        switch self {
        case let .openApp(id, toggle): return "\(toggle ? "Toggle" : "Open") \(id)"
        case let .keystroke(k): return "Press \(k)"
        case let .window(w): return "Window: \(w.rawValue)"
        case let .media(m): return "Media: \(m.rawValue)"
        }
    }
}

/// A key plus modifiers, stored as a macOS virtual key code (layout-independent).
public struct KeyCombo: Hashable, Codable, Sendable, CustomStringConvertible {
    public var keyCode: UInt16
    public var modifiers: Modifiers

    public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
        public static let function = Modifiers(rawValue: 1 << 4)
    }

    public init(keyCode: UInt16, modifiers: Modifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var description: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        if modifiers.contains(.function) { s += "fn " }
        return s + (KeyCombo.names[keyCode] ?? "key \(keyCode)")
    }

    /// Display names for common virtual key codes (ANSI layout).
    static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P",
        37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
    ]

    // Handy presets.
    public static let missionControl = KeyCombo(keyCode: 126, modifiers: .control)     // ⌃↑
    public static let appExpose = KeyCombo(keyCode: 125, modifiers: .control)          // ⌃↓
    public static let spotlight = KeyCombo(keyCode: 49, modifiers: .command)           // ⌘Space
    public static let screenshot = KeyCombo(keyCode: 21, modifiers: [.command, .shift]) // ⌘⇧4
}

public enum WindowCommand: String, Codable, Sendable, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf, maximize, center, nextDisplay
}

public enum MediaKey: String, Codable, Sendable, CaseIterable {
    case playPause, next, previous, volumeUp, volumeDown, mute

    /// NX_KEYTYPE_* constants from IOKit's ev_keymap.h.
    public var nxKeyType: Int32 {
        switch self {
        case .volumeUp: 0
        case .volumeDown: 1
        case .mute: 7
        case .playPause: 16
        case .next: 17
        case .previous: 18
        }
    }

    /// `data1` of the NSEvent.systemDefined (subtype 8) event for a key down/up.
    public func eventData(down: Bool) -> Int {
        Int((nxKeyType << 16) | ((down ? 0xA : 0xB) << 8))
    }
}
