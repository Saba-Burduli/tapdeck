import Actions
import Foundation
import Recognizer
import Testing
@testable import Config

let chrome = "com.google.Chrome", claudeApp = "com.anthropic.claudefordesktop", finder = "com.apple.finder"

@Suite struct ResolutionTests {
    let threeTap = Gesture.tap(fingers: 3, count: 1)
    let fourTap = Gesture.tap(fingers: 4, count: 1)

    @Test func appPackBeatsEverywherePackOnlyInsideItsApp() {
        let c = AppConfig(enabledPacks: ["everyday-mac", "browser"])
        // 4-finger tap: snap left everywhere, but reopen closed tab in Chrome.
        #expect(c.activeBindings(frontApp: finder)[fourTap] == .window(.leftHalf))
        #expect(c.activeBindings(frontApp: chrome)[fourTap] == .keystroke(KeyCombo(keyCode: 17, modifiers: [.command, .shift])))
    }

    @Test func sameGestureDoesDifferentThingsPerApp() {
        let c = AppConfig(enabledPacks: ["claude", "browser"])
        #expect(c.activeBindings(frontApp: claudeApp)[threeTap] == .keystroke(KeyCombo(keyCode: 45, modifiers: .command)))  // new chat
        #expect(c.activeBindings(frontApp: chrome)[threeTap] == .keystroke(KeyCombo(keyCode: 17, modifiers: .command)))     // new tab
        #expect(c.activeBindings(frontApp: finder)[threeTap] == nil)
    }

    @Test func myShortcutBeatsAPackAtTheSameScope() {
        let mine = Binding(gesture: fourTap, action: .media(.mute))
        let c = AppConfig(bindings: [mine], enabledPacks: ["everyday-mac"])
        let r = c.resolved(frontApp: finder)[fourTap]
        #expect(r?.action == .media(.mute))
        #expect(r?.source == .mine)
    }

    @Test func packAppShortcutBeatsMyEverywhereShortcut() {
        // Specific beats general, even across sources: inside Chrome the browser pack wins.
        let c = AppConfig(bindings: [Binding(gesture: fourTap, action: .media(.mute))], enabledPacks: ["browser"])
        #expect(c.resolved(frontApp: chrome)[fourTap]?.source == .pack(id: "browser", name: "Browser"))
        #expect(c.resolved(frontApp: finder)[fourTap]?.source == .mine)
    }

    @Test func myAppSpecificShortcutBeatsEverything() {
        let mine = Binding(gesture: fourTap, action: .media(.next), apps: [chrome])
        let c = AppConfig(bindings: [mine], enabledPacks: ["browser", "everyday-mac"])
        #expect(c.activeBindings(frontApp: chrome)[fourTap] == .media(.next))
    }

    @Test func turningAPackOffRemovesItsShortcuts() {
        var c = AppConfig(enabledPacks: ["browser"])
        #expect(c.activeBindings(frontApp: chrome)[threeTap] != nil)
        c.setPack("browser", enabled: false)
        #expect(c.activeBindings(frontApp: chrome).isEmpty)
        #expect(!c.isPackEnabled("browser"))
    }

    @Test func claudeLauncherWorksFromEveryApp() {
        let c = AppConfig.starter
        let open = Action.openApp(bundleID: claudeApp, toggle: true)
        for app in [finder, chrome, claudeApp, nil] {
            #expect(c.activeBindings(frontApp: app)[.tap(fingers: 3, count: 2)] == open)
        }
    }

    @Test func appScopedConflictsOnlyWhenScopesOverlap() {
        let g = threeTap
        let everywhere = Binding(gesture: g, action: .media(.mute))
        let inChrome = Binding(gesture: g, action: .media(.next), apps: [chrome])
        let alsoChrome = Binding(gesture: g, action: .media(.previous), apps: [chrome, finder])
        let c = AppConfig(bindings: [everywhere, inChrome, alsoChrome])
        #expect(c.conflicts == [alsoChrome.id])
    }
}

@Suite struct MigrationTests {
    @Test func versionOneFileLoadsWithNoPacksAndEverywhereScopes() throws {
        let json = """
        {"version":1,"isEnabled":true,"recognizer":{"maxTapDuration":0.3,"holdDuration":1.5,"maxTravel":0.03,"multiTapInterval":0.25,"cornerSize":0.15},
         "bindings":[{"id":"\(UUID().uuidString)","enabled":true,"gesture":{"tap":{"fingers":3,"count":2}},
                      "action":{"media":{"_0":"playPause"}}}]}
        """
        let c = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(c.version == AppConfig.currentVersion)
        #expect(c.enabledPacks.isEmpty)
        #expect(c.bindings.count == 1 && c.bindings[0].isGlobal)
        #expect(c.activeBindings(frontApp: chrome)[.tap(fingers: 3, count: 2)] == .media(.playPause))
    }

    @Test func roundTripKeepsPacksAndScopes() throws {
        let c = AppConfig(bindings: [Binding(gesture: .hold(fingers: 2), action: .media(.mute), apps: [chrome])],
                          enabledPacks: ["terminal", "claude"])
        let back = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(c))
        #expect(back == c)
    }
}

@Suite struct CatalogTests {
    @Test func packIDsAndBindingIDsAreUnique() {
        let ids = PackCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        let bindingIDs = PackCatalog.all.flatMap { $0.bindings.map(\.id) }
        #expect(Set(bindingIDs).count == bindingIDs.count)
    }

    @Test(arguments: PackCatalog.all.map(\.id))
    func noPackClashesWithItself(id: String) {
        let pack = PackCatalog.pack(id)!
        for (i, a) in pack.bindings.enumerated() {
            for b in pack.bindings[..<i] {
                #expect(!(a.gesture == b.gesture && AppConfig.scopesOverlap(a.apps, b.apps)),
                        "\(pack.name): \(a.gesture) used twice")
            }
        }
    }

    @Test func appPacksNeverShadowTheGlobalLaunchers() {
        // The everywhere launchers (Claude, Simulator) must keep working inside every app pack.
        let launchers = PackCatalog.all.flatMap(\.bindings).filter { $0.isGlobal && $0.action.isOpenApp }
        let scoped = PackCatalog.all.flatMap(\.bindings).filter { !$0.isGlobal }
        for l in launchers {
            #expect(!scoped.contains { $0.gesture == l.gesture }, "\(l.gesture) is taken inside an app pack")
        }
    }

    @Test func starterPacksExist() {
        for id in AppConfig.starter.enabledPacks { #expect(PackCatalog.pack(id) != nil) }
    }
}

extension Action {
    var isOpenApp: Bool { if case .openApp = self { return true } else { return false } }
}
