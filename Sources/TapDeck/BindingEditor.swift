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
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New Shortcut" : "Edit Shortcut").font(.title2.bold())

            GroupBox("When I…") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(recording ? "Do the gesture on your trackpad now…" : draft.gesture.displayName)
                            .font(.headline)
                            .foregroundStyle(recording ? .orange : .primary)
                        Spacer()
                        Button(recording ? "Cancel" : "Record Gesture") { toggleRecording() }
                    }
                    GesturePicker(gesture: $draft.gesture).disabled(recording)
                    if model.config.bindings.contains(where: { $0.id != draft.id && $0.enabled && $0.gesture == draft.gesture }) {
                        Label("Another shortcut already uses this gesture.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.callout)
                    }
                }
                .padding(6)
            }

            GroupBox("…TapDeck will") {
                ActionPicker(action: $draft.action).padding(6)
            }

            HStack {
                Toggle("Enabled", isOn: $draft.enabled)
                Spacer()
                Button("Cancel", role: .cancel) { stopRecording(); done(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { stopRecording(); done(draft) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onDisappear { stopRecording() }
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
