import Actions
import Foundation
import Recognizer

/// One gesture -> action mapping, from the user or from a pack.
public struct Binding: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var gesture: Gesture
    public var action: Action
    public var enabled: Bool
    /// Bundle IDs of the apps this works in, while one of them is in front.
    /// Empty means everywhere.
    public var apps: [String]

    public init(id: UUID = UUID(), gesture: Gesture, action: Action, enabled: Bool = true, apps: [String] = []) {
        self.id = id
        self.gesture = gesture
        self.action = action
        self.enabled = enabled
        self.apps = apps
    }

    public var isGlobal: Bool { apps.isEmpty }

    /// Whether this binding is in effect while `frontApp` is the frontmost app.
    public func applies(to frontApp: String?) -> Bool {
        isGlobal || frontApp.map(apps.contains) == true
    }

    // Older config files have no `apps`: those bindings work everywhere.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        gesture = try c.decode(Gesture.self, forKey: .gesture)
        action = try c.decode(Action.self, forKey: .action)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        apps = try c.decodeIfPresent([String].self, forKey: .apps) ?? []
    }
}

/// Where a resolved action came from (shown in the UI and logs).
public enum BindingSource: Equatable, Sendable {
    case mine
    case pack(id: String, name: String)
}

/// Everything TapDeck persists.
public struct AppConfig: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version = AppConfig.currentVersion
    /// Master switch from the menu bar.
    public var isEnabled = true
    /// The user's own shortcuts ("My Shortcuts").
    public var bindings: [Binding]
    /// IDs of the turned-on packs from `PackCatalog`.
    public var enabledPacks: [String]
    public var recognizer: RecognizerConfig

    public init(isEnabled: Bool = true, bindings: [Binding] = [], enabledPacks: [String] = [],
                recognizer: RecognizerConfig = .init()) {
        self.isEnabled = isEnabled
        self.bindings = bindings
        self.enabledPacks = enabledPacks
        self.recognizer = recognizer
    }

    // Version 1 files have no `enabledPacks`: keep them exactly as they were (no packs).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        bindings = try c.decodeIfPresent([Binding].self, forKey: .bindings) ?? []
        enabledPacks = try c.decodeIfPresent([String].self, forKey: .enabledPacks) ?? []
        recognizer = try c.decodeIfPresent(RecognizerConfig.self, forKey: .recognizer) ?? .init()
        version = AppConfig.currentVersion
    }

    /// First run: the Everyday Mac and Claude packs, which together match the
    /// gestures verified on real hardware during development.
    public static let starter = AppConfig(enabledPacks: ["everyday-mac", "claude"])

    public func isPackEnabled(_ id: String) -> Bool { enabledPacks.contains(id) }

    public mutating func setPack(_ id: String, enabled: Bool) {
        enabledPacks.removeAll { $0 == id }
        if enabled { enabledPacks.append(id) }
    }

    /// The action each gesture runs while `frontApp` is in front, and where it came from.
    ///
    /// Priority: my app-specific shortcuts, then packs' app-specific ones, then my
    /// shortcuts that work everywhere, then packs' everywhere ones. So a Claude-only
    /// gesture wins inside Claude, and my own choice wins over a pack's. Within a
    /// tier the first enabled binding wins (packs in the order they were turned on).
    public func resolved(frontApp: String?, catalog: [Pack] = PackCatalog.all) -> [Gesture: (action: Action, source: BindingSource)] {
        guard isEnabled else { return [:] }
        let packs = enabledPacks.compactMap { id in catalog.first { $0.id == id } }
        let mine = bindings.filter { $0.enabled && $0.applies(to: frontApp) }.map { ($0, BindingSource.mine) }
        let fromPacks = packs.flatMap { p in
            p.bindings.filter { $0.enabled && $0.applies(to: frontApp) }.map { ($0, BindingSource.pack(id: p.id, name: p.name)) }
        }
        let tiers = [
            mine.filter { !$0.0.isGlobal }, fromPacks.filter { !$0.0.isGlobal },
            mine.filter { $0.0.isGlobal }, fromPacks.filter { $0.0.isGlobal },
        ]
        var out: [Gesture: (action: Action, source: BindingSource)] = [:]
        for tier in tiers {
            for (b, source) in tier where out[b.gesture] == nil { out[b.gesture] = (b.action, source) }
        }
        return out
    }

    /// Just the actions, for the engine.
    public func activeBindings(frontApp: String?, catalog: [Pack] = PackCatalog.all) -> [Gesture: Action] {
        resolved(frontApp: frontApp, catalog: catalog).mapValues(\.action)
    }

    /// My shortcuts that clash with another of mine: same gesture, overlapping apps.
    /// Only the first one runs, so Settings warns about the rest.
    public var conflicts: Set<UUID> {
        var dupes = Set<UUID>()
        let enabled = bindings.filter(\.enabled)
        for (i, a) in enabled.enumerated() {
            for b in enabled[..<i] where b.gesture == a.gesture && Self.overlap(a.apps, b.apps) {
                dupes.insert(a.id)
            }
        }
        return dupes
    }

    /// Two scopes clash when both are "everywhere" or they share an app.
    public static func scopesOverlap(_ a: [String], _ b: [String]) -> Bool { overlap(a, b) }

    static func overlap(_ a: [String], _ b: [String]) -> Bool {
        a.isEmpty || b.isEmpty ? a.isEmpty == b.isEmpty : !Set(a).isDisjoint(with: b)
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
