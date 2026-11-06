import Actions
import Foundation
import Recognizer

/// One gesture -> action mapping the user configured.
public struct Binding: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var gesture: Gesture
    public var action: Action
    public var enabled: Bool

    public init(id: UUID = UUID(), gesture: Gesture, action: Action, enabled: Bool = true) {
        self.id = id
        self.gesture = gesture
        self.action = action
        self.enabled = enabled
    }
}

/// Everything TapDeck persists.
public struct AppConfig: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version = AppConfig.currentVersion
    /// Master switch from the menu bar.
    public var isEnabled = true
    public var bindings: [Binding]
    public var recognizer: RecognizerConfig

    public init(isEnabled: Bool = true, bindings: [Binding], recognizer: RecognizerConfig = .init()) {
        self.isEnabled = isEnabled
        self.bindings = bindings
        self.recognizer = recognizer
    }

    /// First-run setup: the gestures verified on real hardware during development.
    public static let starter = AppConfig(bindings: [
        Binding(gesture: .tap(fingers: 3, count: 2), action: .openApp(bundleID: "com.anthropic.claudefordesktop")),
        Binding(gesture: .tap(fingers: 4, count: 1), action: .window(.leftHalf)),
        Binding(gesture: .tap(fingers: 4, count: 2), action: .window(.rightHalf)),
        Binding(gesture: .tap(fingers: 5, count: 1), action: .media(.playPause)),
        Binding(gesture: .hold(fingers: 3), action: .keystroke(.missionControl)),
        Binding(gesture: .cornerTap(.topRight), action: .keystroke(.spotlight)),
    ])

    /// Enabled bindings by gesture. If two enabled bindings share a gesture, the first wins.
    public var activeBindings: [Gesture: Action] {
        guard isEnabled else { return [:] }
        var out: [Gesture: Action] = [:]
        for b in bindings where b.enabled && out[b.gesture] == nil { out[b.gesture] = b.action }
        return out
    }

    /// Gestures used by more than one enabled binding (shown as a warning in Settings).
    public var conflicts: Set<Gesture> {
        var seen = Set<Gesture>(), dupes = Set<Gesture>()
        for b in bindings where b.enabled && !seen.insert(b.gesture).inserted { dupes.insert(b.gesture) }
        return dupes
    }
}

/// Loads and saves `config.json` in Application Support. Never throws at the
/// caller for a missing or corrupt file: it falls back to the starter config and
/// keeps a backup of the unreadable file.
public struct ConfigStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var standard: ConfigStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ConfigStore(url: base.appendingPathComponent("TapDeck/config.json"))
    }

    public func load() -> AppConfig {
        guard let data = try? Data(contentsOf: url) else { return .starter }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            let backup = url.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return .starter
        }
    }

    public func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
