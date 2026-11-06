/// Fits tap/hold thresholds to one person's touch style.
///
/// Onboarding asks the user to tap a few times and hold a few times, measures
/// each contact (first finger down -> last finger up, no click), and calls `fit`.
public enum Calibration {
    public struct Sample: Sendable, Equatable {
        public var duration: Double
        public var travel: Float
        public init(duration: Double, travel: Float) { self.duration = duration; self.travel = travel }
    }

    /// Bounds keep a sloppy calibration from producing something unusable.
    public static let tapRange = 0.15...1.2
    public static let travelRange: ClosedRange<Float> = 0.02...0.06
    /// Minimum gap between the longest tap and the shortest hold.
    public static let minGap = 0.25

    public static func fit(taps: [Sample], holds: [Double], base: RecognizerConfig = .init()) -> RecognizerConfig {
        var config = base
        guard !taps.isEmpty else { return config }

        let longestTap = taps.map(\.duration).max()!
        config.maxTapDuration = clamp(longestTap * 1.3, tapRange)

        let tapTravel = taps.map(\.travel).max()!
        config.maxTravel = clamp(tapTravel * 2, travelRange)

        // Hold starts comfortably before the user's shortest hold, but never
        // overlaps the tap window.
        let floor = config.maxTapDuration + minGap
        if let shortestHold = holds.min() {
            config.holdDuration = max(shortestHold * 0.75, floor)
        } else {
            config.holdDuration = max(base.holdDuration, floor)
        }
        return config
    }

    private static func clamp<T: Comparable>(_ v: T, _ r: ClosedRange<T>) -> T { min(max(v, r.lowerBound), r.upperBound) }
}
