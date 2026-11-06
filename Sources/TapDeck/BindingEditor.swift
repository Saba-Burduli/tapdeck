import Actions
import AppKit
import Config
import Recognizer
import SwiftUI

/// Sheet for creating or editing one shortcut: pick (or record) a gesture, pick an action.
struct BindingEditor: View {
    let model: AppModel
    let isNew: Bool
    let done: (Binding?) -> Void
    @State private var draft: Binding
    @State private var recording = false

    init(model: AppModel, original: Binding, isNew: Bool, done: @escaping (Binding?) -> Void) {
        self.model = model
        self.isNew = isNew
        self.done = done
        _draft = State(initialValue: original)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SymbolTile(symbol: draft.gesture.symbol, active: true, size: 40)
                Text(isNew ? "New shortcut" : "Edit shortcut").font(Theme.title(22))
            }

            section("When I…", step: 1) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        if recording { ListeningRing() }
                        Text(recording ? "Do the gesture on your trackpad now…" : draft.gesture.displayName)
                            .font(Theme.label(15, weight: .semibold))
                            .foregroundStyle(recording ? Theme.warning : Theme.ink)
                            .contentTransition(.opacity)
                        Spacer()
                        Button(recording ? "Cancel" : "Record Gesture") { toggleRecording() }
                            .buttonStyle(PillButtonStyle(primary: !recording))
                    }
                    .animation(Theme.snappy, value: recording)
                    GesturePicker(gesture: $draft.gesture).disabled(recording)
                    if model.config.bindings.contains(where: { $0.id != draft.id && $0.enabled && $0.gesture == draft.gesture && AppConfig.scopesOverlap($0.apps, draft.apps) }) {
                        Label("Another of your shortcuts already uses this gesture in the same apps.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warning).font(Theme.label(12))
                    }
                }
            }

            section("…TapDeck will", step: 2) {
                ActionPicker(action: $draft.action)
            }

            section("Works in", step: 3) {
                AppScopePicker(apps: $draft.apps)
            }

            HStack {
                Toggle(isOn: $draft.enabled) { Text("Enabled").font(Theme.label(13, weight: .semibold)) }
                    .toggleStyle(LiquidToggleStyle())
                    .fixedSize()
                Spacer()
                Button("Cancel", role: .cancel) { stopRecording(); done(nil) }
                    .buttonStyle(PillButtonStyle(primary: false))
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { stopRecording(); done(draft) }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 540)
        .background(Theme.milk)
        .tint(Theme.honey)
        .foregroundStyle(Theme.ink)
        .preferredColorScheme(.light)
        .onDisappear { stopRecording() }
    }

    private func section<Content: View>(_ title: String, step: Int, @ViewBuilder content: () -> Content) -> some View {
        GlassCard(padding: 14, radius: Theme.radiusS) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("\(step)")
                        .font(Theme.label(11, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Theme.butter))
                    Text(title).font(Theme.label(13, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                }
                content()
            }
        }
    }

    private func toggleRecording() {
        if recording { stopRecording(); return }
        recording = true
        model.engine.recordNextGesture { g in
            draft.gesture = g
            recording = false
        }
    }

    private func stopRecording() {
        if recording { model.engine.cancelRecording() }
        recording = false
    }
}

struct GesturePicker: View {
    @SwiftUI.Binding var gesture: Gesture

    private enum Kind: String, CaseIterable { case tap = "Tap", hold = "Hold", corner = "Corner tap" }

    var body: some View {
        HStack {
            Picker("", selection: kind) {
                ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) }
            }
            .labelsHidden().frame(width: 130)

            switch gesture {
            case let .tap(f, c):
                Picker("", selection: .init(get: { f }, set: { gesture = .tap(fingers: $0, count: c) })) {
                    ForEach(1...5, id: \.self) { Text("\($0) finger\($0 == 1 ? "" : "s")") }
                }.labelsHidden().frame(width: 110)
                Picker("", selection: .init(get: { c }, set: { gesture = .tap(fingers: f, count: $0) })) {
                    Text("once").tag(1); Text("twice").tag(2); Text("three times").tag(3)
                }.labelsHidden().frame(width: 130)
            case let .hold(f):
                Picker("", selection: .init(get: { f }, set: { gesture = .hold(fingers: $0) })) {
                    ForEach(1...5, id: \.self) { Text("\($0) finger\($0 == 1 ? "" : "s")") }
                }.labelsHidden().frame(width: 110)
            case let .cornerTap(corner):
                Picker("", selection: .init(get: { corner }, set: { gesture = .cornerTap($0) })) {
                    ForEach(Gesture.Corner.allCases, id: \.self) { Text($0.displayName.capitalized) }
                }.labelsHidden().frame(width: 150)
            }
            Spacer()
        }
    }

    private var kind: SwiftUI.Binding<Kind> {
        .init(
            get: {
                switch gesture {
                case .tap: .tap
                case .hold: .hold
                case .cornerTap: .corner
                }
            },
            set: { k in
                switch k {
                case .tap: gesture = .tap(fingers: 3, count: 1)
                case .hold: gesture = .hold(fingers: 3)
                case .corner: gesture = .cornerTap(.topRight)
                }
            })
    }
}

struct ActionPicker: View {
    @SwiftUI.Binding var action: Action

    private enum Kind: String, CaseIterable { case app = "Open app", keys = "Keyboard shortcut", window = "Move window", media = "Media" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: kind) {
                ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented).labelsHidden()

            switch action {
            case let .openApp(id, toggle):
                HStack {
                    if let icon = AppInfo.icon(for: id) { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
                    Text(id.isEmpty ? "No app chosen" : AppInfo.name(for: id)).font(.headline)
                    Spacer()
                    Button("Choose App…") { chooseApp(toggle: toggle) }
                }
                Toggle("Hide it if it's already in front", isOn: .init(get: { toggle }, set: { action = .openApp(bundleID: id, toggle: $0) }))
            case let .keystroke(combo):
                HStack {
                    KeyRecorder(combo: .init(get: { combo }, set: { action = .keystroke($0) }))
                    Menu("Presets") {
                        Button("Mission Control (⌃↑)") { action = .keystroke(.missionControl) }
                        Button("App windows (⌃↓)") { action = .keystroke(.appExpose) }
                        Button("Spotlight (⌘Space)") { action = .keystroke(.spotlight) }
                        Button("Screenshot area (⇧⌘4)") { action = .keystroke(.screenshot) }
                    }
                    .fixedSize()
                }
            case let .window(cmd):
                Picker("", selection: .init(get: { cmd }, set: { action = .window($0) })) {
                    ForEach(WindowCommand.allCases, id: \.self) { Text($0.displayName) }
                }.labelsHidden()
            case let .media(key):
                Picker("", selection: .init(get: { key }, set: { action = .media($0) })) {
                    ForEach(MediaKey.allCases, id: \.self) { Text($0.displayName) }
                }.labelsHidden()
            }
        }
    }

    private var kind: SwiftUI.Binding<Kind> {
        .init(
            get: {
                switch action {
                case .openApp: .app
                case .keystroke: .keys
                case .window: .window
                case .media: .media
                }
            },
            set: { k in
                switch k {
                case .app: action = .openApp(bundleID: "", toggle: true)
                case .keys: action = .keystroke(.spotlight)
                case .window: action = .window(.leftHalf)
                case .media: action = .media(.playPause)
                }
            })
    }

    private func chooseApp(toggle: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        action = .openApp(bundleID: id, toggle: toggle)
    }
}

/// Honey rings pulsing outwards while TapDeck waits for a gesture.
struct ListeningRing: View {
    @State private var on = false

    var body: some View {
        ZStack {
            ForEach(0..<2) { i in
                Circle().stroke(Theme.honey, lineWidth: 2)
                    .scaleEffect(on ? 1.8 : 0.6)
                    .opacity(on ? 0 : 0.9)
                    .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false).delay(Double(i) * 0.6), value: on)
            }
            Circle().fill(Theme.honey).frame(width: 8, height: 8)
        }
        .frame(width: 22, height: 22)
        .onAppear { on = true }
    }
}

/// Click, then press a key combination to capture it.
struct KeyRecorder: View {
    @SwiftUI.Binding var combo: KeyCombo
    @State private var listening = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            listening ? stop() : start()
        } label: {
            Text(listening ? "Press keys… (Esc cancels)" : combo.description)
                .frame(minWidth: 180)
                .monospaced()
        }
        .onDisappear { stop() }
    }

    private func start() {
        listening = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                stop()   // bare Esc cancels
                return nil
            }
            combo = KeyCombo(keyCode: event.keyCode, modifiers: Self.modifiers(event.modifierFlags))
            stop()
            return nil   // swallow it so it doesn't trigger anything in Settings
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        listening = false
    }

    static func modifiers(_ f: NSEvent.ModifierFlags) -> KeyCombo.Modifiers {
        var m: KeyCombo.Modifiers = []
        if f.contains(.command) { m.insert(.command) }
        if f.contains(.shift) { m.insert(.shift) }
        if f.contains(.option) { m.insert(.option) }
        if f.contains(.control) { m.insert(.control) }
        return m
    }
}

/// Everywhere, or only while one of the chosen apps is in front.
struct AppScopePicker: View {
    @SwiftUI.Binding var apps: [String]
    @State private var onlySome = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $onlySome) {
                Text("Every app").tag(false)
                Text("Only these apps").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden()
            .onChange(of: onlySome) { _, some in if !some { apps = [] } }

            if onlySome {
                ForEach(apps, id: \.self) { id in
                    HStack {
                        if let icon = AppInfo.icon(for: id) { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                        Text(AppInfo.name(for: id))
                        Spacer()
                        Button { apps.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add App…") { addApp() }
                if apps.isEmpty {
                    Text("Add at least one app, or choose Every app.").font(.callout).foregroundStyle(.orange)
                }
            }
        }
        .onAppear { onlySome = !apps.isEmpty }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !apps.contains(id) { apps.append(id) }
        }
    }
}
