import AppKit
import SwiftUI

/// The Settings window's look: a milky white base with yellow and honey liquid.
enum Theme {
    static let milk = Color(hex: 0xFBF8F1)
    static let cream = Color(hex: 0xF3EBDD)
    static let butter = Color(hex: 0xFFD84D)
    static let honey = Color(hex: 0xF5B301)
    static let warmWhite = Color(hex: 0xFFFDF8)
    static let ink = Color(hex: 0x2A251E)
    static let inkMuted = Color(hex: 0x2A251E, opacity: 0.55)
    static let inkFaint = Color(hex: 0x2A251E, opacity: 0.1)
    static let success = Color(hex: 0x3E9B5B)
    static let warning = Color(hex: 0xE07A12)

    static let radiusS: CGFloat = 14
    static let radiusM: CGFloat = 20
    static let radiusL: CGFloat = 28

    /// Quick, settled motion for state changes.
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.78)
    /// Liquid-feeling motion that overshoots a little.
    static let wobble = Animation.spring(response: 0.45, dampingFraction: 0.6)

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func label(_ size: CGFloat = 13, weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight) }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Light trackpad taps that make toggles and sliders feel physical.
enum Haptics {
    static func tap() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    static func tick() { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
}
