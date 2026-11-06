import Testing
@testable import Recognizer

@Suite struct CalibrationTests {
    typealias S = Calibration.Sample

    @Test func quickTapperKeepsFastThresholds() {
        let c = Calibration.fit(taps: [S(duration: 0.07, travel: 0.004), S(duration: 0.072, travel: 0.007), S(duration: 0.064, travel: 0.01)],
                                holds: [0.9, 1.1])
        #expect(c.maxTapDuration == Calibration.tapRange.lowerBound)   // 0.094 clamped up to 0.15
        #expect(abs(c.holdDuration - 0.675) < 1e-9)                    // 0.9 * 0.75
        #expect(c.maxTravel == 0.02)
    }

    @Test func slowTapperGetsWiderTapWindowAndLaterHold() {
        // Light taps of 250-870 ms, like the user's first spike session.
        let c = Calibration.fit(taps: [S(duration: 0.25, travel: 0.009), S(duration: 0.45, travel: 0.011), S(duration: 0.87, travel: 0.017)],
                                holds: [2.6])
        #expect(abs(c.maxTapDuration - 1.131) < 1e-9)
        #expect(abs(c.holdDuration - 1.95) < 1e-9)
        #expect(abs(c.maxTravel - 0.034) < 1e-6)
    }

    @Test func holdNeverOverlapsTheTapWindow() {
        let c = Calibration.fit(taps: [S(duration: 0.6, travel: 0.01)], holds: [0.7])
        #expect(c.holdDuration >= c.maxTapDuration + Calibration.minGap)
    }

    @Test func noSamplesKeepsDefaults() {
        #expect(Calibration.fit(taps: [], holds: []) == RecognizerConfig())
    }

    @Test func fittedConfigRecognizesTheSlowTapperAsTaps() {
        let c = Calibration.fit(taps: [S(duration: 0.87, travel: 0.017)], holds: [2.6])
        var r = GestureRecognizer(config: c, bound: [])
        var pad = Pad()
        pad.touch(fingers: 3, duration: 0.85, stagger: 0.02)
        #expect(gestures(pad.run(&r)) == [.tap(fingers: 3, count: 1)])
    }
}
