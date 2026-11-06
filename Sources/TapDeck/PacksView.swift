import Actions
import Config
import SwiftUI

/// Settings › Packs: turn ready-made shortcut packs on and off.
struct PacksTab: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TabHeader(title: "Shortcut packs",
                          subtitle: "Ready-made gestures for an app or a job. App packs only work while their app is in front, so one gesture can do different things in different apps.")
                if !model.engine.accessibilityTrusted {
                    PermissionBanner(model: model)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(PackCatalog.all) { pack in
                        PackCard(pack: pack, enabled: enabledBinding(pack.id), frontApp: model.engine.frontApp)
                    }
                }
                Label("Your own shortcuts beat packs, and shortcuts for the app in front beat ones that work everywhere.",
                      systemImage: "arrow.up.arrow.down")
                    .font(Theme.label(11.5, weight: .regular))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.never)
    }

    private func enabledBinding(_ id: String) -> SwiftUI.Binding<Bool> {
        .init(get: { model.config.isPackEnabled(id) },
              set: { model.config.setPack(id, enabled: $0) })
    }
}

struct PackCard: View {
    let pack: Pack
    @SwiftUI.Binding var enabled: Bool
    let frontApp: String?
    @State private var expanded = false

    var body: some View {
        GlassCard(flood: enabled) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    SymbolTile(symbol: pack.symbol, active: enabled, size: 44)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(pack.name).font(Theme.title(16))
                            if isActiveHere {
                                HStack(spacing: 5) {
                                    PulseDot(color: Theme.success)
                                    Text("Active now").font(Theme.label(11, weight: .semibold)).foregroundStyle(Theme.success)
                                }
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        ScopeLabel(apps: pack.apps)
                    }
                    Spacer(minLength: 8)
                    LiquidSwitch(isOn: $enabled)
                }
                Text(pack.summary)
                    .font(Theme.label(12.5, weight: .regular))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    withAnimation(Theme.wobble) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                        Text("\(pack.bindings.count) shortcuts")
                    }
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(pack.bindings.enumerated()), id: \.element.id) { index, b in
                            HStack(spacing: 8) {
                                Image(systemName: b.gesture.symbol)
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(Theme.butter.opacity(0.35)))
                                Text(b.gesture.displayName).font(Theme.label(12, weight: .medium))
                                Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.honey)
                                Text(b.action.displayName).font(Theme.label(12, weight: .regular)).foregroundStyle(Theme.inkMuted)
                                Spacer(minLength: 4)
                                if b.isGlobal && !pack.apps.isEmpty {
                                    Chip(text: "everywhere", tint: Theme.butter.opacity(0.3))
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -6)).animation(Theme.snappy.delay(Double(index) * 0.03)),
                                removal: .opacity.animation(.easeOut(duration: 0.1))))
                        }
                    }
                }
            }
        }
        .animation(Theme.snappy, value: isActiveHere)
    }

    /// The pack is on and the frontmost app is one it targets.
    private var isActiveHere: Bool {
        enabled && !pack.apps.isEmpty && frontApp.map(pack.apps.contains) == true
    }
}

/// "Everywhere" or "Only in Chrome, Safari +2".
struct ScopeLabel: View {
    let apps: [String]

    var body: some View {
        Chip(text: text, systemImage: apps.isEmpty ? "globe" : "app.dashed",
             tint: apps.isEmpty ? Theme.butter.opacity(0.3) : Theme.inkFaint)
            .help(apps.isEmpty ? "Works in every app" : apps.map(AppInfo.name(for:)).joined(separator: ", "))
    }

    private var text: String {
        guard !apps.isEmpty else { return "Everywhere" }
        let names = apps.map(AppInfo.name(for:))
        return names.count <= 2 ? "Only in " + names.joined(separator: ", ") : "Only in \(names[0]), \(names[1]) +\(names.count - 2)"
    }
}
