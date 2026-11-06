import Actions
import Foundation
import Recognizer

/// A ready-made set of shortcuts for one app or one job, turned on or off as a unit.
public struct Pack: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    /// SF Symbol shown in Settings.
    public var symbol: String
    /// The apps this pack is for (empty = everywhere). Shown in Settings; each
    /// binding carries its own scope, so a pack can also hold a few global ones.
    public var apps: [String]
    public var bindings: [Binding]
}

/// The packs that ship with TapDeck. Every shortcut here uses an action TapDeck
/// can already perform (apps, keystrokes, windows, media keys).
public enum PackCatalog {
    public static let all: [Pack] = [everydayMac, claude, browser, codeEditors, xcode, terminal]

    public static func pack(_ id: String) -> Pack? { all.first { $0.id == id } }

    // MARK: Apps (bundle IDs)

    enum App {
        static let claude = "com.anthropic.claudefordesktop"
        static let browsers = ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser",
                               "com.brave.Browser", "com.microsoft.edgemac"]
        static let editors = ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92" /* Cursor */,
                              "dev.zed.Zed", "com.exafunction.windsurf"]
        static let xcode = "com.apple.dt.Xcode"
        static let simulator = "com.apple.iphonesimulator"
        static let terminals = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable"]
    }

    // MARK: Keys (macOS virtual key codes, ANSI)

    enum Key {
        static let b: UInt16 = 11, c: UInt16 = 8, i: UInt16 = 34, k: UInt16 = 40, n: UInt16 = 45
        static let o: UInt16 = 31, p: UInt16 = 35, q: UInt16 = 12, r: UInt16 = 15, s: UInt16 = 1
        static let t: UInt16 = 17, w: UInt16 = 13, four: UInt16 = 21
        static let tab: UInt16 = 48, escape: UInt16 = 53, period: UInt16 = 47, slash: UInt16 = 44, grave: UInt16 = 50
    }

    static func keys(_ code: UInt16, _ mods: KeyCombo.Modifiers = []) -> Action { .keystroke(KeyCombo(keyCode: code, modifiers: mods)) }

    /// Stable IDs per pack binding, so the UI and tests can refer to them.
    static func b(_ pack: String, _ n: Int, _ g: Gesture, _ a: Action, apps: [String] = []) -> Binding {
        let hex = String(format: "%012x", (abs(pack.hashValueStable) &* 31 &+ n) & 0xFFFF_FFFF_FFFF)
        return Binding(id: UUID(uuidString: "7A9D0000-0000-4000-8000-\(hex)")!, gesture: g, action: a, apps: apps)
    }

    // MARK: The packs

    static let everydayMac = Pack(
        id: "everyday-mac", name: "Everyday Mac",
        summary: "Windows, Mission Control, Spotlight, media and lock screen, in every app.",
        symbol: "macbook", apps: [],
        bindings: [
            b("everyday-mac", 1, .tap(fingers: 4, count: 1), .window(.leftHalf)),
            b("everyday-mac", 2, .tap(fingers: 4, count: 2), .window(.rightHalf)),
            b("everyday-mac", 3, .tap(fingers: 4, count: 3), .window(.maximize)),
            b("everyday-mac", 4, .tap(fingers: 5, count: 1), .media(.playPause)),
            b("everyday-mac", 5, .hold(fingers: 3), .keystroke(.missionControl)),
            b("everyday-mac", 6, .cornerTap(.topRight), .keystroke(.spotlight)),
            b("everyday-mac", 7, .cornerTap(.topLeft), keys(Key.four, [.command, .shift, .control])),   // area screenshot to clipboard
            b("everyday-mac", 8, .hold(fingers: 5), keys(Key.q, [.command, .control])),                 // lock screen
        ])

    static let claude = Pack(
        id: "claude", name: "Claude",
        summary: "Open Claude from anywhere; new chat and stop while you're in it.",
        symbol: "sparkles", apps: [App.claude],
        bindings: [
            b("claude", 1, .tap(fingers: 3, count: 2), .openApp(bundleID: App.claude, toggle: true)),   // everywhere
            b("claude", 2, .tap(fingers: 3, count: 1), keys(Key.n, .command), apps: [App.claude]),      // new chat
            b("claude", 3, .tap(fingers: 4, count: 1), keys(Key.escape), apps: [App.claude]),           // stop the response
        ])

    static let browser = Pack(
        id: "browser", name: "Browser",
        summary: "Tabs, private windows, refresh and DevTools in Chrome, Safari, Arc, Brave and Edge.",
        symbol: "safari", apps: App.browsers,
        bindings: [
            b("browser", 1, .tap(fingers: 3, count: 1), keys(Key.t, .command), apps: App.browsers),             // new tab
            b("browser", 2, .tap(fingers: 3, count: 3), keys(Key.n, [.command, .shift]), apps: App.browsers),   // incognito / private window
            b("browser", 3, .tap(fingers: 4, count: 1), keys(Key.t, [.command, .shift]), apps: App.browsers),   // reopen closed tab
            b("browser", 4, .tap(fingers: 4, count: 2), keys(Key.w, .command), apps: App.browsers),             // close tab
            b("browser", 5, .hold(fingers: 3), keys(Key.r, .command), apps: App.browsers),                      // refresh
            b("browser", 6, .tap(fingers: 5, count: 1), keys(Key.i, [.command, .option]), apps: App.browsers),  // developer tools
        ])

    static let codeEditors = Pack(
        id: "code-editors", name: "Code Editors",
        summary: "Command palette, quick open, AI suggestions and the terminal in VS Code, Cursor, Zed and Windsurf.",
        symbol: "chevron.left.forwardslash.chevron.right", apps: App.editors,
        bindings: [
            b("code-editors", 1, .tap(fingers: 3, count: 1), keys(Key.p, [.command, .shift]), apps: App.editors),  // command palette
            b("code-editors", 2, .tap(fingers: 3, count: 3), keys(Key.p, .command), apps: App.editors),            // quick open
            b("code-editors", 3, .tap(fingers: 4, count: 1), keys(Key.tab), apps: App.editors),                    // accept AI suggestion
            b("code-editors", 4, .tap(fingers: 4, count: 2), keys(Key.slash, .command), apps: App.editors),        // toggle comment
            b("code-editors", 5, .hold(fingers: 3), keys(Key.grave, .control), apps: App.editors),                 // toggle terminal
            b("code-editors", 6, .tap(fingers: 5, count: 1), keys(Key.s, .command), apps: App.editors),            // save
        ])

    static let xcode = Pack(
        id: "xcode", name: "Xcode & Simulator",
        summary: "Run, stop, build and open quickly in Xcode; bring up the iOS Simulator from anywhere.",
        symbol: "hammer", apps: [App.xcode],
        bindings: [
            b("xcode", 1, .hold(fingers: 4), .openApp(bundleID: App.simulator, toggle: true)),                   // everywhere
            b("xcode", 2, .tap(fingers: 3, count: 1), keys(Key.o, [.command, .shift]), apps: [App.xcode]),      // open quickly
            b("xcode", 3, .tap(fingers: 3, count: 3), keys(Key.r, .command), apps: [App.xcode]),                // run
            b("xcode", 4, .tap(fingers: 4, count: 1), keys(Key.period, .command), apps: [App.xcode]),           // stop
            b("xcode", 5, .tap(fingers: 4, count: 2), keys(Key.b, .command), apps: [App.xcode]),                // build
        ])

    static let terminal = Pack(
        id: "terminal", name: "Terminal",
        summary: "New tab, interrupt and clear in Terminal, iTerm2, Ghostty and Warp.",
        symbol: "terminal", apps: App.terminals,
        bindings: [
            b("terminal", 1, .tap(fingers: 3, count: 1), keys(Key.t, .command), apps: App.terminals),    // new tab
            b("terminal", 2, .tap(fingers: 4, count: 1), keys(Key.c, .control), apps: App.terminals),    // interrupt (⌃C)
            b("terminal", 3, .hold(fingers: 3), keys(Key.k, .command), apps: App.terminals),             // clear
        ])
}

private extension String {
    /// Deterministic across launches (unlike `hashValue`), for stable binding IDs.
    var hashValueStable: Int {
        var h: UInt64 = 1469598103934665603
        for byte in utf8 { h = (h ^ UInt64(byte)) &* 1099511628211 }
        return Int(truncatingIfNeeded: h >> 1)
    }
}
