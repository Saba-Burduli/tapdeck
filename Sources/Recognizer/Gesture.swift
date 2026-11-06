/// A trackpad gesture TapDeck can bind to an action.
public enum Gesture: Hashable, Codable, Sendable, CustomStringConvertible {
    /// `fingers` (1-5) tapped together, `count` times in a row (1-3).
    /// A press that physically clicks the pad also counts as a tap, however long it lasts.
    case tap(fingers: Int, count: Int)
    /// `fingers` resting still on the pad past the hold threshold.
    case hold(fingers: Int)
    /// A single one-finger tap inside a corner zone.
    case cornerTap(Corner)

    public enum Corner: String, Codable, Sendable, CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    public var description: String {
        switch self {
        case let .tap(f, c):
            let times = ["", "single", "double", "triple"][min(c, 3)]
            return "\(f)-finger \(times) tap"
        case let .hold(f): return "\(f)-finger hold"
        case let .cornerTap(c): return "corner tap (\(c.rawValue))"
        }
    }
}

public struct GestureEvent: Sendable, Equatable {
    public var gesture: Gesture
    /// Frame clock time at which the gesture was recognized (seconds).
    public var time: Double
}

/// Tunable thresholds. Defaults come from the milestone 1 measurements:
/// taps moved <= 0.017 of the pad, drags 0.06-0.33; fingers land/lift 8-50 ms apart.
public struct RecognizerConfig: Sendable, Equatable, Codable {
    /// Longest touch (first finger down -> last finger up) that still counts as a tap.
    public var maxTapDuration: Double = 0.30
    /// Still touch longer than this fires a hold. Long on purpose: people who press
    /// slowly can take over 1.1 s to click, and a click must win over a hold.
    public var holdDuration: Double = 1.5
    /// Max distance any finger may move (pad units, 0...1) for a tap or hold.
    public var maxTravel: Float = 0.03
    /// Max gap between one tap's release and the next tap's start in a multi-tap.
    public var multiTapInterval: Double = 0.25
    /// Size of each corner zone, as a fraction of the pad's width and height.
    public var cornerSize: Float = 0.15
    public static let maxTapCount = 3

    public init() {}
}
