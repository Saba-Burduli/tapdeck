import SwiftUI

extension SettingsTab: CaseIterable {
    static var allCases: [SettingsTab] { [.packs, .shortcuts, .sensitivity, .trackpad, .general] }

    var title: String {
        switch self {
        case .packs: "Packs"
        case .shortcuts: "My Shortcuts"
        case .sensitivity: "Sensitivity"
        case .trackpad: "Trackpad"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .packs: "square.stack.3d.up.fill"
        case .shortcuts: "hand.tap.fill"
        case .sensitivity: "slider.horizontal.3"
        case .trackpad: "rectangle.and.hand.point.up.left.fill"
        case .general: "gearshape.fill"
        }
    }
}

/// Floating glass pill of tabs. A butter blob slides to the selected tab. ⌘1–⌘5 switch tabs.
struct TabBar: View {
    @SwiftUI.Binding var selection: SettingsTab
    @Namespace private var blob

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(SettingsTab.allCases.enumerated()), id: \.element) { index, tab in
                let selected = selection == tab
                Button {
                    guard !selected else { return }
                    Haptics.tap()
                    withAnimation(Theme.wobble) { selection = tab }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                            .symbolEffect(.bounce, value: selected)
                        Text(tab.title)
                    }
                    .font(Theme.label(12.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.ink : Theme.inkMuted)
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background {
                        if selected {
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.butter, Theme.honey], startPoint: .top, endPoint: .bottom))
                                .shadow(color: Theme.honey.opacity(0.45), radius: 8, y: 3)
                                .matchedGeometryEffect(id: "blob", in: blob)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .help("\(tab.title) (⌘\(index + 1))")
            }
        }
        .padding(4)
        .background {
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(Theme.warmWhite.opacity(0.7))
            Capsule().strokeBorder(.white, lineWidth: 1)
        }
        .shadow(color: Theme.honey.opacity(0.15), radius: 16, y: 6)
    }
}

/// Tab content enters from slightly below, sharpening out of a blur.
struct BlurTransition: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: active ? 8 : 0)
            .opacity(active ? 0 : 1)
            .offset(y: active ? 10 : 0)
            .scaleEffect(active ? 0.985 : 1)
    }
}

extension AnyTransition {
    static var liquidTab: AnyTransition {
        .asymmetric(insertion: .modifier(active: BlurTransition(active: true), identity: BlurTransition(active: false)),
                    removal: .modifier(active: BlurTransition(active: true), identity: BlurTransition(active: false)).animation(.easeOut(duration: 0.12)))
    }
}
