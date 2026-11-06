import Actions
import AppKit
import Recognizer

extension Gesture {
    var displayName: String {
        switch self {
        case let .tap(f, c):
            return "\(f)-finger " + ["tap", "tap", "double tap", "triple tap"][min(c, 3)]
        case let .hold(f): return "\(f)-finger hold"
        case let .cornerTap(c): return "Corner tap: \(c.displayName)"
        }
    }

    var symbol: String {
        switch self {
        case .tap: "hand.tap"
        case .hold: "hand.raised"
        case .cornerTap: "arrow.up.left.and.arrow.down.right"
        }
    }
}

extension Gesture.Corner {
    var displayName: String {
        switch self {
        case .topLeft: "top left"
        case .topRight: "top right"
        case .bottomLeft: "bottom left"
        case .bottomRight: "bottom right"
        }
    }
}

extension Action {
    var displayName: String {
        switch self {
        case let .openApp(id, toggle): return "\(toggle ? "Toggle" : "Open") \(AppInfo.name(for: id))"
        case let .keystroke(k): return "Press \(k)"
        case let .window(w): return w.displayName
        case let .media(m): return m.displayName
        }
    }
}

extension WindowCommand {
    var displayName: String {
        switch self {
        case .leftHalf: "Window → left half"
        case .rightHalf: "Window → right half"
        case .topHalf: "Window → top half"
        case .bottomHalf: "Window → bottom half"
        case .maximize: "Window → fill screen"
        case .center: "Window → center"
        case .nextDisplay: "Window → next display"
        }
    }
}

extension MediaKey {
    var displayName: String {
        switch self {
        case .playPause: "Play / Pause"
        case .next: "Next track"
        case .previous: "Previous track"
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .mute: "Mute"
        }
    }
}

enum AppInfo {
    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func name(for bundleID: String) -> String {
        guard let url = url(for: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(for bundleID: String) -> NSImage? {
        url(for: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
