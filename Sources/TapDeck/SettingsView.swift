import Actions
import Config
import Engine
import Recognizer
import SwiftUI
import TouchInput

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            ShortcutsTab(model: model)
                .tabItem { Label("Shortcuts", systemImage: "hand.tap") }.tag(SettingsTab.shortcuts)
            SensitivityTab(model: model)
                .tabItem { Label("Sensitivity", systemImage: "slider.horizontal.3") }.tag(SettingsTab.sensitivity)
            TrackpadTab(model: model)
                .tabItem { Label("Trackpad", systemImage: "rectangle.and.hand.point.up.left") }.tag(SettingsTab.trackpad)
            GeneralTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
        }
        .padding()
        .safeAreaInset(edge: .bottom) {
            if let e = model.saveError {
                Text(e).foregroundStyle(.red).font(.callout).padding(.bottom, 6)
            }
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsTab: View {
    @Bindable var model: AppModel
    @State private var editing: Binding?
    @State private var isNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.engine.accessibilityTrusted {
                PermissionBanner(model: model)
            }
            List {
                ForEach($model.config.bindings) { $b in
                    BindingRow(binding: $b, conflict: model.config.conflicts.contains(b.gesture))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { isNew = false; editing = b }
                        .contextMenu {
                            Button("Edit…") { isNew = false; editing = b }
                            Button("Delete", role: .destructive) { model.config.bindings.removeAll { $0.id == b.id } }
                        }
                }
                .onDelete { model.config.bindings.remove(atOffsets: $0) }
                .onMove { model.config.bindings.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            HStack {
                Button { isNew = true; editing = Binding(gesture: .tap(fingers: 3, count: 1), action: .media(.playPause)) } label: {
                    Label("Add Shortcut", systemImage: "plus")
                }
                Button("Edit…") { isNew = false; editing = selectedOrFirst }
                    .disabled(model.config.bindings.isEmpty)
                Spacer()
                Text("Double-click a row to edit. Right-click to delete.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editing) { b in
            BindingEditor(model: model, original: b, isNew: isNew) { saved in
                if let saved {
                    if let i = model.config.bindings.firstIndex(where: { $0.id == saved.id }) {
                        model.config.bindings[i] = saved
                    } else {
                        model.config.bindings.append(saved)
                    }
                }
                editing = nil
            }
        }
    }

    private var selectedOrFirst: Binding? { model.config.bindings.first }
}

struct BindingRow: View {
    @SwiftUI.Binding var binding: Binding
    var conflict: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $binding.enabled).labelsHidden()
            Image(systemName: binding.gesture.symbol).frame(width: 20)
            Text(binding.gesture.displayName).frame(width: 190, alignment: .leading)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            if case let .openApp(id, _) = binding.action, let icon = AppInfo.icon(for: id) {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            }
            Text(binding.action.displayName)
            Spacer()
            if conflict {
                Label("Duplicate gesture", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
                    .help("Another enabled shortcut uses this gesture; only the first one runs.")
            }
        }
        .opacity(binding.enabled ? 1 : 0.5)
        .padding(.vertical, 2)
    }
}

// MARK: - Sensitivity

struct SensitivityTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                slider("Longest tap", value: $model.config.recognizer.maxTapDuration, range: 0.1...1.0, ms: true,
                       help: "Touches shorter than this count as taps. Presses that click always count.")
                slider("Hold after", value: $model.config.recognizer.holdDuration, range: 0.5...3.0, ms: true,
                       help: "Keep fingers still this long for a hold.")
                slider("Time between taps", value: $model.config.recognizer.multiTapInterval, range: 0.1...0.6, ms: true,
                       help: "Max gap for double and triple taps. Shorter = single taps fire sooner.")
                slider("Allowed movement", value: Double.binding($model.config.recognizer.maxTravel), range: 0.01...0.08, ms: false,
                       help: "How far fingers may move (fraction of the pad) before it's a swipe, not a tap.")
                slider("Corner size", value: Double.binding($model.config.recognizer.cornerSize), range: 0.05...0.3, ms: false,
                       help: "Size of each corner zone for corner taps.")
            } footer: {
                HStack {
                    Spacer()
                    Button("Reset to Defaults") { model.config.recognizer = RecognizerConfig() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func slider(_ title: String, value: SwiftUI.Binding<Double>, range: ClosedRange<Double>, ms: Bool, help: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(ms ? "\(Int(value.wrappedValue * 1000)) ms" : String(format: "%.0f%%", value.wrappedValue * 100))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension Double {
    /// Bridges a Float setting to a Double slider.
    static func binding(_ f: SwiftUI.Binding<Float>) -> SwiftUI.Binding<Double> {
        .init(get: { Double(f.wrappedValue) }, set: { f.wrappedValue = Float($0) })
    }
}

// MARK: - Trackpad (live visualizer)

struct TrackpadTab: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Text("Touch the trackpad: dots show your fingers live. Use this to tune Sensitivity.")
                .foregroundStyle(.secondary)
            TrackpadCanvas(touches: model.engine.liveTouches, cornerSize: CGFloat(model.config.recognizer.cornerSize))
                .aspectRatio(1.6, contentMode: .fit)
                .frame(maxWidth: 520)
            if let f = model.engine.lastFired {
                Label("\(f.gesture.displayName) → \(f.action?.displayName ?? "no action")", systemImage: "checkmark.circle")
                    .font(.headline)
                if let e = f.error { Text(e).foregroundStyle(.red) }
            } else {
                Text("No gesture yet").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.engine.showsLiveTouches = true }
        .onDisappear { model.engine.showsLiveTouches = false }
    }
}

struct TrackpadCanvas: View {
    var touches: [Touch]
    var cornerSize: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let pad = CGRect(origin: .zero, size: size)
            ctx.fill(Path(roundedRect: pad, cornerRadius: 18), with: .color(.secondary.opacity(0.12)))
            ctx.stroke(Path(roundedRect: pad, cornerRadius: 18), with: .color(.secondary.opacity(0.4)), lineWidth: 1)
            // Corner zones.
            let cw = size.width * cornerSize, ch = size.height * cornerSize
            for (x, y) in [(0, 0), (size.width - cw, 0), (0, size.height - ch), (size.width - cw, size.height - ch)] {
                ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: cw, height: ch), cornerRadius: 10),
                         with: .color(.accentColor.opacity(0.08)))
            }
            for t in touches {
                // Touch y origin is bottom-left; Canvas origin is top-left.
                let c = CGPoint(x: CGFloat(t.x) * size.width, y: (1 - CGFloat(t.y)) * size.height)
                let r: CGFloat = 18
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(.accentColor.opacity(0.85)))
            }
        }
        .overlay(alignment: .topLeading) {
            Text("\(touches.count) finger\(touches.count == 1 ? "" : "s")").font(.caption).padding(10).foregroundStyle(.secondary)
        }
    }
}

// MARK: - General (permissions, launch at login)

struct GeneralTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Accessibility") {
                if model.engine.accessibilityTrusted {
                    Label("Granted. Keystrokes, window moves and media keys work.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    PermissionBanner(model: model)
                    DisclosureGroup("TapDeck is switched on in Settings but still not working?") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("That entry belongs to an older build. Remove it by running this in Terminal, then click Request Access again:")
                                .font(.callout)
                            HStack {
                                Text(Self.resetCommand).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(Self.resetCommand, forType: .string)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            Section("Startup") {
                Toggle("Launch TapDeck at login", isOn: $model.launchAtLogin)
            }
            Section("Trackpad") {
                LabeledContent("Status", value: model.engine.isRunning ? "Listening" : (model.engine.startError ?? "Stopped"))
            }
            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                Link("TapDeck on GitHub", destination: URL(string: "https://github.com/Saba-Burduli/tapdeck")!)
            }
        }
        .formStyle(.grouped)
    }

    static var resetCommand: String {
        "tccutil reset Accessibility \(Bundle.main.bundleIdentifier ?? "com.saba-burduli.tapdeck")"
    }
}

struct PermissionBanner: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("TapDeck needs Accessibility permission", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.orange)
            Text("Opening apps works without it. Keystrokes, window snapping and media keys need it.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Request Access") { Permissions.requestAccessibility(); model.engine.refreshPermissions() }
                Button("Open System Settings") { Permissions.openAccessibilitySettings() }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
