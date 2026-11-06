import Actions
import Config
import SwiftUI

/// Settings › Packs: turn ready-made shortcut packs on and off.
struct PacksTab: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.engine.accessibilityTrusted {
                PermissionBanner(model: model)
            }
            Text("Packs are ready-made shortcuts for an app or a job. App packs only work while their app is in front, so the same gesture can do different things in different apps.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(PackCatalog.all) { pack in
                        PackRow(pack: pack, enabled: enabledBinding(pack.id), frontApp: model.engine.frontApp)
                    }
                }
                .padding(.vertical, 4)
            }
            Text("Priority: your own shortcuts beat packs, and shortcuts for the app in front beat ones that work everywhere.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func enabledBinding(_ id: String) -> SwiftUI.Binding<Bool> {
        .init(get: { model.config.isPackEnabled(id) },
              set: { model.config.setPack(id, enabled: $0) })
    }
}

struct PackRow: View {
    let pack: Pack
    @SwiftUI.Binding var enabled: Bool
    let frontApp: String?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: pack.symbol)
                    .font(.title2)
                    .frame(width: 36, height: 36)
                    .foregroundStyle(enabled ? Color.orange : .secondary)
                    .background((enabled ? Color.yellow.opacity(0.18) : Color.secondary.opacity(0.08)), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(pack.name).font(.headline)
                        ScopeLabel(apps: pack.apps)
                        if isActiveHere {
                            Text("Active now").font(.caption2.bold()).foregroundStyle(.green)
                        }
                    }
                    Text(pack.summary).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $enabled).labelsHidden().toggleStyle(.switch)
            }
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(pack.bindings) { b in
                        HStack(spacing: 10) {
                            Image(systemName: b.gesture.symbol).frame(width: 18)
                            Text(b.gesture.displayName).frame(width: 170, alignment: .leading)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            Text(b.action.displayName)
                            Spacer()
                            if b.isGlobal && !pack.apps.isEmpty {
                                Text("works everywhere").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .font(.callout)
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("\(pack.bindings.count) shortcuts").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .opacity(enabled ? 1 : 0.75)
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
        Text(text)
            .font(.caption)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.secondary)
            .help(apps.isEmpty ? "Works in every app" : apps.map(AppInfo.name(for:)).joined(separator: ", "))
    }

    private var text: String {
        guard !apps.isEmpty else { return "Everywhere" }
        let names = apps.map(AppInfo.name(for:))
        return names.count <= 2 ? "Only in " + names.joined(separator: ", ") : "Only in \(names[0]), \(names[1]) +\(names.count - 2)"
    }
}
