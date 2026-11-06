import Actions
import AppKit
import Config
import Engine
import Observation
import ServiceManagement
import SwiftUI

@main
struct TapDeckApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.config.isEnabled ? "hand.tap.fill" : "hand.tap")
        }
        .menuBarExtraStyle(.menu)
    }
}

enum SettingsTab: Hashable { case shortcuts, sensitivity, trackpad, general }

/// App-wide state: the engine, persistence, and the Settings window.
@MainActor @Observable
final class AppModel {
    let engine: Engine
    private let store = ConfigStore.standard
    var saveError: String?
    var selectedTab: SettingsTab = .shortcuts

    @ObservationIgnored private var settingsWindow: NSWindow?

    /// Every change is saved immediately (the file is tiny).
    var config: AppConfig {
        get { engine.config }
        set {
            engine.config = newValue
            do { try store.save(newValue); saveError = nil } catch { saveError = "Couldn't save settings: \(error.localizedDescription)" }
        }
    }

    init() {
        engine = Engine(config: store.load())
        engine.start()
        // First run or missing permission: open Settings on the onboarding tab.
        if !Permissions.isAccessibilityTrusted {
            DispatchQueue.main.async { self.showSettings(.general) }
        }
    }

    // MARK: Settings window (AppKit-managed so it can open from anywhere, e.g. at launch)

    func showSettings(_ tab: SettingsTab? = nil) {
        if let tab { selectedTab = tab }
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "TapDeck Settings"
            window.contentViewController = NSHostingController(rootView: SettingsView(model: self))
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("TapDeckSettings")
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                saveError = nil
            } catch {
                saveError = "Launch at login: \(error.localizedDescription)"
            }
        }
    }
}

struct MenuContent: View {
    @Bindable var model: AppModel

    var body: some View {
        Toggle("TapDeck Enabled", isOn: $model.config.isEnabled)
            .keyboardShortcut("e")

        if !model.engine.accessibilityTrusted {
            Button("⚠️ Grant Accessibility…") { model.showSettings(.general) }
        }
        if let error = model.engine.startError {
            Text("Trackpad unavailable: \(error)")
        }
        if let f = model.engine.lastFired {
            Text("Last: \(f.gesture.displayName) → \(f.action?.displayName ?? "–")\(f.error == nil ? "" : " (failed)")")
        }

        Divider()
        Button("Settings…") { model.showSettings() }
            .keyboardShortcut(",")
        Button("Quit TapDeck") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
