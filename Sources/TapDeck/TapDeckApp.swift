import Actions
import AppKit
import Config
import Engine
import Observation
import ServiceManagement
import SwiftUI
import TouchInput

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

enum SettingsTab: Hashable { case packs, shortcuts, sensitivity, trackpad, general }

/// App-wide state: the engine, persistence, and the Settings window.
@MainActor @Observable
final class AppModel {
    let engine: Engine
    private let store = ConfigStore.standard
    var saveError: String?
    var selectedTab: SettingsTab = .packs

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
        #if DEBUG
        startFakeTouchesIfRequested()
        #endif
    }

    // MARK: Settings window (AppKit-managed so it can open from anywhere, e.g. at launch)

    func showSettings(_ tab: SettingsTab? = nil) {
        if let tab { selectedTab = tab }
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = "TapDeck Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.contentMinSize = NSSize(width: 720, height: 520)
            window.contentViewController = NSHostingController(rootView: SettingsView(model: self))
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("TapDeckSettingsWindow")
            observeVisibility(of: window)
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
        engine.showsLiveTouches = true
    }

    /// The fluid behind every tab follows the fingers, so stream touches only while the window is on screen.
    private func observeVisibility(of window: NSWindow) {
        let center = NotificationCenter.default
        let hidden: [Notification.Name] = [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification]
        for name in hidden {
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.engine.showsLiveTouches = false }
            }
        }
        center.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.engine.showsLiveTouches = true }
        }
    }

    #if DEBUG
    @ObservationIgnored private var fakeTouchTimer: Timer?

    /// `TAPDECK_FAKE_TOUCHES=1` opens Settings and moves two synthetic fingers around the pad,
    /// so the animations can be checked without a hand on the trackpad. `TAPDECK_TAB` picks the tab.
    private func startFakeTouchesIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard env["TAPDECK_FAKE_TOUCHES"] == "1" else { return }
        let tabs: [String: SettingsTab] = ["packs": .packs, "shortcuts": .shortcuts, "sensitivity": .sensitivity, "trackpad": .trackpad, "general": .general]
        DispatchQueue.main.async { self.showSettings(tabs[env["TAPDECK_TAB"] ?? ""] ?? .packs) }
        let start = Date()
        fakeTouchTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.engine.showsLiveTouches else { return }
                let t = Float(Date().timeIntervalSince(start))
                // Fingers lift for 1s every 5s, to show splashes and ripples.
                guard t.truncatingRemainder(dividingBy: 5) < 4 else { return self.engine.injectLiveTouches([]) }
                let fingers = (0..<2).map { i -> Touch in
                    let phase = t * 0.9 + Float(i) * 0.6
                    return Touch(id: Int32(i), state: .touching,
                                 x: 0.5 + 0.32 * sin(phase), y: 0.5 + 0.28 * sin(phase * 1.7 + Float(i)),
                                 vx: 0.29 * cos(phase), vy: 0.43 * cos(phase * 1.7 + Float(i)), size: 1)
                }
                self.engine.injectLiveTouches(fingers)
            }
        }
    }
    #endif

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
            if let source = f.source { Text("   from \(source)") }
        }

        Divider()
        Button("Shortcut Packs…") { model.showSettings(.packs) }
        Button("Settings…") { model.showSettings() }
            .keyboardShortcut(",")
        Button("Quit TapDeck") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
