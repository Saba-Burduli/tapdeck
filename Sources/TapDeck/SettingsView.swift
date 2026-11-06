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
            WindowFluid(model: model)
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

/// Reads the live touches in its own body, so 60 updates a second redraw only the liquid, not the tabs.
struct WindowFluid: View {
    let model: AppModel

    var body: some View {
        // On the Trackpad tab the pad shows the fingers; the window keeps only its ambient colour.
        let onPad = model.selectedTab == .trackpad
        FluidLayer(touches: onPad ? [] : model.engine.liveTouches, fired: onPad ? nil : model.engine.lastFired?.date)
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
    @State private var focus: SensitivityPreview.Focus?

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TabHeader(title: "Sensitivity", subtitle: "How TapDeck tells taps, holds and corners apart. The preview shows each setting as you drag it.")
                    GlassCard {
                        VStack(spacing: 20) {
                            row("Longest tap", .tap, value: $model.config.recognizer.maxTapDuration, range: 0.1...1.0, ms: true,
                                help: "Touches shorter than this count as taps. Presses that click always count.")
                            row("Time between taps", .gap, value: $model.config.recognizer.multiTapInterval, range: 0.1...0.6, ms: true,
                                help: "Max gap for double and triple taps. Shorter = single taps fire sooner.")
                            row("Hold after", .hold, value: $model.config.recognizer.holdDuration, range: 0.5...3.0, ms: true,
                                help: "Keep fingers still this long for a hold.")
                            row("Allowed movement", .travel, value: Double.binding($model.config.recognizer.maxTravel), range: 0.01...0.08, ms: false,
                                help: "How far fingers may move (fraction of the pad) before it's a swipe, not a tap.")
                            row("Corner size", .corner, value: Double.binding($model.config.recognizer.cornerSize), range: 0.05...0.3, ms: false,
                                help: "Size of each corner zone for corner taps.")
                        }
                    }
                    HStack {
                        Spacer()
                        Button {
                            Haptics.tap()
                            withAnimation(Theme.wobble) { model.config.recognizer = RecognizerConfig() }
                        } label: { Label("Reset to Defaults", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(PillButtonStyle(primary: false))
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            SensitivityPreview(config: model.config.recognizer, focus: focus)
                .frame(width: 250)
        }
    }

    private func row(_ title: String, _ id: SensitivityPreview.Focus, value: SwiftUI.Binding<Double>, range: ClosedRange<Double>,
                     ms: Bool, help: String) -> some View {
        let format: (Double) -> String = { ms ? "\(Int($0 * 1000)) ms" : String(format: "%.0f%%", $0 * 100) }
        let tracked = SwiftUI.Binding<Double>(get: { value.wrappedValue },
                                              set: { value.wrappedValue = $0; if focus != id { withAnimation(Theme.snappy) { focus = id } } })
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(Theme.label(13, weight: .semibold))
                Spacer()
                Text(format(value.wrappedValue))
                    .font(Theme.label(12, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(focus == id ? Theme.ink : Theme.inkMuted)
                    .contentTransition(.numericText())
            }
            LiquidSlider(value: tracked, range: range, format: format)
            Text(help).font(Theme.label(11.5, weight: .regular)).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A small pad and timeline that draw the current recognizer settings to scale.
struct SensitivityPreview: View {
    enum Focus { case tap, gap, hold, travel, corner }

    var config: RecognizerConfig
    var focus: Focus?

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Preview").font(Theme.label(12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                pad
                VStack(alignment: .leading, spacing: 9) {
                    bar("Tap", seconds: config.maxTapDuration, highlighted: focus == .tap)
                    bar("Gap", seconds: config.multiTapInterval, highlighted: focus == .gap)
                    bar("Hold", seconds: config.holdDuration, highlighted: focus == .hold)
                    HStack {
                        Text("0s"); Spacer(); Text("1.5s"); Spacer(); Text("3s")
                    }
                    .font(Theme.label(9.5, weight: .medium)).foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .animation(Theme.wobble, value: config)
    }

    private var pad: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let cw = w * CGFloat(config.cornerSize), ch = h * CGFloat(config.cornerSize)
            let travel = max(3, w * CGFloat(config.maxTravel))
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cream)
                ForEach(0..<4) { i in
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.butter.opacity(focus == .corner ? 0.85 : 0.45))
                        .frame(width: cw, height: ch)
                        .position(x: i % 2 == 0 ? cw / 2 : w - cw / 2, y: i < 2 ? ch / 2 : h - ch / 2)
                }
                Circle()
                    .fill(Theme.honey.opacity(focus == .travel ? 0.3 : 0.15))
                    .overlay(Circle().strokeBorder(Theme.honey, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                    .frame(width: travel * 2 + 14, height: travel * 2 + 14)
                Circle().fill(.white).frame(width: 14, height: 14)
                    .shadow(color: Theme.honey.opacity(0.6), radius: 6)
            }
        }
        .aspectRatio(1.6, contentMode: .fit)
    }

    private func bar(_ label: String, seconds: Double, highlighted: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label).font(Theme.label(10.5, weight: .semibold)).frame(width: 30, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.cream)
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.butter, Theme.honey], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geo.size.width * CGFloat(seconds / 3)))
                        .opacity(highlighted ? 1 : 0.6)
                }
            }
            .frame(height: highlighted ? 10 : 7)
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
        VStack(spacing: 16) {
            TabHeader(title: "Trackpad", subtitle: "Touch the trackpad: the liquid follows your fingers. Use it to tune Sensitivity.")
            PadStage(model: model)

            ZStack {
                if let f = model.engine.lastFired {
                    GlassCard(padding: 12, radius: Theme.radiusS) {
                        HStack(spacing: 12) {
                            SymbolTile(symbol: f.gesture.symbol, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(f.gesture.displayName).font(Theme.label(14, weight: .semibold))
                                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.honey)
                                    Text(f.action?.displayName ?? "no action").font(Theme.label(14, weight: .regular))
                                }
                                if let source = f.source { Text("from \(source)").font(Theme.label(11.5, weight: .regular)).foregroundStyle(Theme.inkMuted) }
                                if let e = f.error { Text(e).font(Theme.label(11.5)).foregroundStyle(Theme.warning) }
                            }
                        }
                    }
                    .frame(maxWidth: 560)
                    .id(f.date)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else {
                    Text("No gesture yet. Try a three-finger tap.").font(Theme.label(13, weight: .regular)).foregroundStyle(Theme.inkMuted)
                }
            }
            .animation(Theme.wobble, value: model.engine.lastFired?.date)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The big pad with its own liquid. Reads the live touches itself, like ``WindowFluid``.
struct PadStage: View {
    let model: AppModel

    var body: some View {
        let touches = model.engine.liveTouches
        let shape = RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(.ultraThinMaterial)
            shape.fill(Theme.warmWhite.opacity(0.85))
            CornerZones(size: CGFloat(model.config.recognizer.cornerSize))
            FluidLayer(touches: touches, fired: model.engine.lastFired?.date)
                .clipShape(shape)
            shape.strokeBorder(.white, lineWidth: 1.5)
            Chip(text: "\(touches.count) finger\(touches.count == 1 ? "" : "s")", systemImage: "hand.raised.fingers.spread.fill",
                 tint: touches.isEmpty ? Theme.inkFaint : Theme.butter, foreground: Theme.ink)
                .padding(14)
                .animation(Theme.snappy, value: touches.count)
        }
        .aspectRatio(1.6, contentMode: .fit)
        .frame(maxWidth: 560)
        .shadow(color: Theme.honey.opacity(0.2), radius: 24, y: 10)
    }
}

/// The four corner-tap zones, drawn faintly on the pad.
struct CornerZones: View {
    var size: CGFloat

    var body: some View {
        GeometryReader { geo in
            let cw = geo.size.width * size, ch = geo.size.height * size
            ForEach(0..<4) { i in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.honey.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.butter.opacity(0.12)))
                    .frame(width: cw, height: ch)
                    .position(x: i % 2 == 0 ? cw / 2 + 8 : geo.size.width - cw / 2 - 8,
                              y: i < 2 ? ch / 2 + 8 : geo.size.height - ch / 2 - 8)
            }
        }
    }
}

// MARK: - General (permissions, launch at login)

struct GeneralTab: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TabHeader(title: "General", subtitle: "Permissions, startup and what TapDeck is doing right now.")

                if model.engine.accessibilityTrusted {
                    card("Accessibility", symbol: "checkmark.shield.fill") {
                        Label("Granted. Keystrokes, window moves and media keys work.", systemImage: "checkmark.circle.fill")
                            .font(Theme.label(13, weight: .medium))
                            .foregroundStyle(Theme.success)
                    }
                } else {
                    PermissionBanner(model: model)
                    card("Still not working?", symbol: "questionmark.circle.fill") {
                        DisclosureGroup("TapDeck is switched on in System Settings but keystrokes still don't work") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("That entry belongs to an older build. Remove it by running this in Terminal, then click Request Access again:")
                                    .font(Theme.label(12, weight: .regular)).foregroundStyle(Theme.inkMuted)
                                HStack {
                                    Text(Self.resetCommand)
                                        .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cream))
                                    Button("Copy") {
                                        Haptics.tap()
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(Self.resetCommand, forType: .string)
                                    }
                                    .buttonStyle(PillButtonStyle(primary: false))
                                }
                            }
                            .padding(.top, 6)
                        }
                        .font(Theme.label(12.5, weight: .medium))
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    card("Startup", symbol: "power") {
                        Toggle(isOn: $model.launchAtLogin) { Text("Launch TapDeck at login").font(Theme.label(13)) }
                            .toggleStyle(LiquidToggleStyle())
                    }
                    card("Trackpad", symbol: "rectangle.and.hand.point.up.left.fill") {
                        HStack(spacing: 8) {
                            if model.engine.isRunning {
                                PulseDot(color: Theme.success)
                                Text("Listening").font(Theme.label(13, weight: .semibold)).foregroundStyle(Theme.success)
                            } else {
                                Circle().fill(Theme.warning).frame(width: 7, height: 7)
                                Text(model.engine.startError ?? "Stopped").font(Theme.label(13, weight: .semibold)).foregroundStyle(Theme.warning)
                            }
                        }
                    }
                }

                card("About", symbol: "info.circle.fill") {
                    HStack {
                        Text("TapDeck \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                            .font(Theme.label(13, weight: .semibold))
                        Spacer()
                        Link(destination: URL(string: "https://github.com/Saba-Burduli/tapdeck")!) {
                            Label("GitHub", systemImage: "arrow.up.right")
                        }
                        .buttonStyle(PillButtonStyle(primary: false))
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.never)
    }

    private func card<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol)
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
                content()
            }
        }
    }

    static var resetCommand: String {
        "tccutil reset Accessibility \(Bundle.main.bundleIdentifier ?? "com.saba-burduli.tapdeck")"
    }
}

struct PermissionBanner: View {
    let model: AppModel

    var body: some View {
        GlassCard(tint: Theme.warning.opacity(0.08)) {
            HStack(alignment: .top, spacing: 12) {
                SymbolTile(symbol: "exclamationmark.triangle.fill", size: 38)
                VStack(alignment: .leading, spacing: 8) {
                    Text("TapDeck needs Accessibility permission").font(Theme.title(15))
                    Text("Opening apps works without it. Keystrokes, window snapping and media keys need it.")
                        .font(Theme.label(12.5, weight: .regular)).foregroundStyle(Theme.inkMuted)
                    HStack {
                        Button("Request Access") { Permissions.requestAccessibility(); model.engine.refreshPermissions() }
                            .buttonStyle(PillButtonStyle())
                        Button("Open System Settings") { Permissions.openAccessibilitySettings() }
                            .buttonStyle(PillButtonStyle(primary: false))
                    }
                }
            }
        }
    }
}
