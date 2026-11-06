import Actions
import Config
import Engine
import Recognizer
import SwiftUI
import TouchInput

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            Theme.milk.ignoresSafeArea()
            FluidLayer(touches: model.engine.liveTouches, fired: model.engine.lastFired?.date)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabBar(selection: $model.selectedTab)
                    .padding(.top, 2)
                ZStack {
                    tabContent
                        .id(model.selectedTab)
                        .transition(.liquidTab)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 20)
            }
        }
        .overlay(alignment: .bottom) {
            if let e = model.saveError {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .background(Capsule().fill(Theme.butter.opacity(0.6)))
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.wobble, value: model.saveError)
        .foregroundStyle(Theme.ink)
        .tint(Theme.honey)
        .preferredColorScheme(.light)
    }

    @ViewBuilder private var tabContent: some View {
        switch model.selectedTab {
        case .packs: PacksTab(model: model)
        case .shortcuts: ShortcutsTab(model: model)
        case .sensitivity: SensitivityTab(model: model)
        case .trackpad: TrackpadTab(model: model)
        case .general: GeneralTab(model: model)
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsTab: View {
    @Bindable var model: AppModel
    @State private var editing: Binding?
    @State private var isNew = false
    @State private var plusHover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                TabHeader(title: "My shortcuts",
                          subtitle: "Your own gestures. They win over packs. Double-click to edit, drag to reorder, right-click to delete.")
                Button {
                    isNew = true
                    editing = Binding(gesture: .tap(fingers: 3, count: 1), action: .media(.playPause))
                } label: {
                    Label { Text("Add Shortcut") } icon: {
                        Image(systemName: "plus").fontWeight(.bold).rotationEffect(.degrees(plusHover ? 90 : 0))
                    }
                }
                .buttonStyle(PillButtonStyle())
                .onHover { h in withAnimation(Theme.wobble) { plusHover = h } }
                .fixedSize()
            }
            if !model.engine.accessibilityTrusted {
                PermissionBanner(model: model)
            }
            if model.config.bindings.isEmpty {
                GlassCard {
                    VStack(spacing: 8) {
                        SymbolTile(symbol: "hand.tap.fill", size: 48)
                        Text("No shortcuts yet").font(Theme.title(16))
                        Text("Add one, or switch on a pack to start with ready-made gestures.")
                            .font(Theme.label(12.5, weight: .regular)).foregroundStyle(Theme.inkMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                List {
                    ForEach($model.config.bindings) { $b in
                        BindingRow(binding: $b, conflict: model.config.conflicts.contains(b.id))
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { isNew = false; editing = b }
                            .contextMenu {
                                Button("Edit…") { isNew = false; editing = b }
                                Button("Delete", role: .destructive) { model.config.bindings.removeAll { $0.id == b.id } }
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                    .onDelete { model.config.bindings.remove(atOffsets: $0) }
                    .onMove { model.config.bindings.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
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
}

struct BindingRow: View {
    @SwiftUI.Binding var binding: Binding
    var conflict: Bool

    var body: some View {
        GlassCard(padding: 12, radius: Theme.radiusS) {
            HStack(spacing: 12) {
                LiquidSwitch(isOn: $binding.enabled)
                SymbolTile(symbol: binding.gesture.symbol, active: binding.enabled, size: 32)
                Text(binding.gesture.displayName)
                    .font(Theme.label(13, weight: .semibold))
                    .frame(width: 170, alignment: .leading)
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.honey)
                if case let .openApp(id, _) = binding.action, let icon = AppInfo.icon(for: id) {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                }
                Text(binding.action.displayName).font(Theme.label(13, weight: .regular)).lineLimit(1)
                Spacer(minLength: 6)
                ScopeLabel(apps: binding.apps)
                if conflict {
                    Chip(text: "Duplicate", systemImage: "exclamationmark.triangle.fill",
                         tint: Theme.warning.opacity(0.15), foreground: Theme.warning)
                        .modifier(Shake(trigger: conflict))
                        .help("Another of your shortcuts uses this gesture in the same apps; only the first one runs.")
                }
            }
        }
        .opacity(binding.enabled ? 1 : 0.6)
        .animation(Theme.snappy, value: binding.enabled)
    }
}

struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(animatableData * .pi * 6) * 4 * (1 - animatableData), y: 0))
    }
}

/// Shakes once when `trigger` turns on.
struct Shake: ViewModifier {
    var trigger: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(ShakeEffect(animatableData: phase))
            .onChange(of: trigger, initial: true) { _, on in
                guard on else { return }
                phase = 0
                withAnimation(.easeOut(duration: 0.5)) { phase = 1 }
            }
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
                if let source = f.source { Text("from \(source)").foregroundStyle(.secondary) }
                if let e = f.error { Text(e).foregroundStyle(.red) }
            } else {
                Text("No gesture yet").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
