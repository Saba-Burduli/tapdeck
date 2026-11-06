import Actions
import Foundation
import Recognizer
import Testing
@testable import Config

@Suite struct ConfigTests {
    func tempStore() -> ConfigStore {
        ConfigStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("tapdeck-tests-\(UUID().uuidString)/config.json"))
    }

    @Test func missingFileGivesStarter() {
        #expect(tempStore().load() == .starter)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = tempStore()
        var c = AppConfig.starter
        c.recognizer.holdDuration = 2.0
        c.bindings.append(Binding(gesture: .tap(fingers: 2, count: 3), action: .keystroke(.screenshot), enabled: false))
        try store.save(c)
        #expect(store.load() == c)
    }

    @Test func corruptFileFallsBackAndKeepsBackup() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: store.url)
        #expect(store.load() == .starter)
        let files = try FileManager.default.contentsOfDirectory(atPath: store.url.deletingLastPathComponent().path)
        #expect(files.contains { $0.hasPrefix("config.corrupt-") })
    }

    @Test func activeBindingsSkipDisabledAndRespectMasterSwitch() {
        var c = AppConfig(bindings: [
            Binding(gesture: .tap(fingers: 3, count: 1), action: .media(.mute)),
            Binding(gesture: .tap(fingers: 4, count: 1), action: .media(.next), enabled: false),
        ])
        #expect(c.activeBindings == [.tap(fingers: 3, count: 1): .media(.mute)])
        c.isEnabled = false
        #expect(c.activeBindings.isEmpty)
    }

    @Test func duplicateGesturesAreReportedAndFirstWins() {
        let g = Gesture.tap(fingers: 3, count: 2)
        let c = AppConfig(bindings: [
            Binding(gesture: g, action: .media(.mute)),
            Binding(gesture: g, action: .media(.next)),
        ])
        #expect(c.conflicts == [g])
        #expect(c.activeBindings[g] == .media(.mute))
    }

    @Test func starterHasNoConflicts() {
        #expect(AppConfig.starter.conflicts.isEmpty)
    }
}
