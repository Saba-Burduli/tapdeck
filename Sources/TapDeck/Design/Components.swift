import SwiftUI

// MARK: - Glass card

/// A frosted milk panel the fluid shows through. Lifts on hover, with a highlight that follows the pointer.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    var radius: CGFloat = Theme.radiusM
    var tint: Color = .clear
    @ViewBuilder var content: Content

    @State private var hover: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Theme.warmWhite.opacity(0.72))
                    shape.fill(tint)
                    if let hover, !reduceMotion {
                        shape.fill(RadialGradient(colors: [.white.opacity(0.75), .clear],
                                                  center: .init(x: 0, y: 0), startRadius: 0, endRadius: 220))
                            .offset(x: hover.x, y: hover.y)
                            .clipShape(shape)
                            .blendMode(.plusLighter)
                    }
                    shape.strokeBorder(.white.opacity(0.9), lineWidth: 1)
                    shape.strokeBorder(Theme.inkFaint, lineWidth: 0.5)
                }
                .shadow(color: Theme.honey.opacity(hover == nil ? 0.08 : 0.18), radius: hover == nil ? 14 : 22, y: hover == nil ? 6 : 10)
            }
            .scaleEffect(hover != nil && !reduceMotion ? 1.008 : 1)
            .onContinuousHover { phase in
                withAnimation(Theme.snappy) {
                    if case let .active(point) = phase { hover = point } else { hover = nil }
                }
            }
    }
}

// MARK: - Liquid toggle

/// A switch whose track fills with sloshing butter liquid.
struct LiquidToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            LiquidSwitch(isOn: configuration.$isOn)
        }
    }
}

struct LiquidSwitch: View {
    @SwiftUI.Binding var isOn: Bool
    @State private var pressed = false
    @State private var slosh: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let width: CGFloat = 46, height: CGFloat = 26

    var body: some View {
        let level: CGFloat = isOn ? 1 : 0
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(Theme.cream)
            WaveFill(level: level, amplitude: reduceMotion ? 0 : 3 * slosh, phase: slosh * 6)
                .fill(LinearGradient(colors: [Theme.butter, Theme.honey], startPoint: .top, endPoint: .bottom))
                .clipShape(Capsule())
            Capsule().strokeBorder(Theme.inkFaint, lineWidth: 0.5)
            Capsule()
                .fill(.white)
                .frame(width: pressed ? 27 : 21, height: 21)
                .shadow(color: Theme.ink.opacity(0.2), radius: 2, y: 1)
                .padding(2.5)
        }
        .frame(width: width, height: height)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { withAnimation(Theme.snappy) { pressed = true } } }
                .onEnded { _ in
                    Haptics.tap()
                    withAnimation(Theme.wobble) { pressed = false; isOn.toggle() }
                    slosh = 1
                    withAnimation(.spring(response: 0.9, dampingFraction: 0.35)) { slosh = 0 }
                })
        .accessibilityRepresentation { Toggle("", isOn: $isOn) }
    }
}

/// A container filled from the left up to `level`, with a wavy leading edge.
struct WaveFill: Shape {
    var level: CGFloat
    var amplitude: CGFloat
    var phase: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(level, .init(amplitude, phase)) }
        set { level = newValue.first; amplitude = newValue.second.first; phase = newValue.second.second }
    }

    func path(in rect: CGRect) -> Path {
        let edge = rect.minX + rect.width * level
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: edge, y: rect.minY))
        let steps = 16
        for i in 0...steps {
            let y = rect.minY + rect.height * CGFloat(i) / CGFloat(steps)
            let x = edge + amplitude * sin(phase + CGFloat(i) / CGFloat(steps) * .pi * 2)
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Liquid slider

/// A slider whose fill is a liquid surface that wobbles while you drag it.
struct LiquidSlider: View {
    @SwiftUI.Binding var value: Double
    var range: ClosedRange<Double>
    var format: (Double) -> String

    @State private var dragging = false
    @State private var wobble: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: CGFloat { CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = fraction * w
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.cream).frame(height: 10)
                WaveFill(level: fraction, amplitude: reduceMotion ? 0 : 2.5 * wobble, phase: CGFloat(value) * 40)
                    .fill(LinearGradient(colors: [Theme.butter, Theme.honey], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 10)
                    .clipShape(Capsule())
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(Theme.honey, lineWidth: dragging ? 4 : 2.5))
                    .frame(width: 22, height: 22)
                    .shadow(color: Theme.honey.opacity(0.35), radius: dragging ? 8 : 3, y: 2)
                    .scaleEffect(dragging ? 1.15 : 1)
                    .offset(x: x - 11)
                if dragging {
                    Text(format(value))
                        .font(Theme.label(11, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.butter))
                        .fixedSize()
                        .offset(x: min(max(x - 24, 0), w - 48), y: -28)
                        .transition(.scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
                }
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !dragging { withAnimation(Theme.wobble) { dragging = true } }
                        let f = min(max(g.location.x / w, 0), 1)
                        let new = range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)
                        if (new == range.lowerBound || new == range.upperBound) && new != value { Haptics.tick() }
                        wobble = min(1, abs(CGFloat(g.velocity.width)) / 600)
                        value = new
                    }
                    .onEnded { _ in
                        withAnimation(Theme.wobble) { dragging = false }
                        withAnimation(.spring(response: 0.8, dampingFraction: 0.3)) { wobble = 0 }
                    })
        }
        .frame(height: 28)
        .accessibilityRepresentation { Slider(value: $value, in: range) }
    }
}

// MARK: - Chips, dots and buttons

struct Chip: View {
    var text: String
    var systemImage: String?
    var tint: Color = Theme.inkFaint
    var foreground: Color = Theme.inkMuted

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .bold)) }
            Text(text)
        }
        .font(Theme.label(11, weight: .semibold))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(tint))
        .foregroundStyle(foreground)
    }
}

/// A dot that breathes, for "live" states.
struct PulseDot: View {
    var color: Color = Theme.honey
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
            .background(Circle().fill(color.opacity(0.35)).scaleEffect(on ? 2.4 : 1).opacity(on ? 0 : 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { on = true }
            }
    }
}

/// An SF Symbol on a butter squircle that bounces when its value changes.
struct SymbolTile: View {
    var symbol: String
    var active = true
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(active ? Theme.ink : Theme.inkMuted)
            .symbolEffect(.bounce, value: active)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(active ? AnyShapeStyle(LinearGradient(colors: [Theme.butter, Theme.honey], startPoint: .topLeading, endPoint: .bottomTrailing))
                                 : AnyShapeStyle(Theme.cream)))
            .animation(Theme.wobble, value: active)
    }
}

/// Primary: a butter pill. Plain: a quiet glass pill.
struct PillButtonStyle: ButtonStyle {
    var primary = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(13, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(Theme.ink)
            .background(
                Capsule().fill(primary ? AnyShapeStyle(LinearGradient(colors: [Theme.butter, Theme.honey], startPoint: .top, endPoint: .bottom))
                                       : AnyShapeStyle(Theme.warmWhite.opacity(0.85))))
            .overlay(Capsule().strokeBorder(primary ? Theme.honey.opacity(0.4) : Theme.inkFaint, lineWidth: 0.5))
            .shadow(color: Theme.honey.opacity(primary ? 0.3 : 0), radius: 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}

/// Section heading used at the top of each tab.
struct TabHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.title(26)).foregroundStyle(Theme.ink)
            Text(subtitle).font(Theme.label(13, weight: .regular)).foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
