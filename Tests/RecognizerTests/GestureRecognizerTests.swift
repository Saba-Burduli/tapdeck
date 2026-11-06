import Testing
import TouchInput
@testable import Recognizer

/// Builds synthetic frame streams that mimic what the milestone 1 spike saw on
/// real hardware: ~100 Hz frames, fingers landing/lifting 10-20 ms apart, and
/// an occasional one-frame dropout of a finger.
struct Pad {
    var now: Double = 100
    var frames: [TouchFrame] = []
    /// Times at which the pad physically clicked (mouse button down).
    var clicks: [Double] = []

    /// One contact of `fingers` lasting `duration` (first finger down -> last up).
    mutating func touch(
        fingers n: Int, duration: Double, at origin: SIMD2<Float> = [0.3, 0.3],
        stagger: Double = 0.01, move: SIMD2<Float> = .zero, flicker: Bool = false,
        clickAfter: Double? = nil
    ) {
        let start = now, end = now + duration
        if let c = clickAfter { clicks.append(start + c) }
        var t = start
        var flickered = false
        while t < end - 1e-9 {
            var touches: [Touch] = []
            for i in 0..<n {
                let down = start + Double(i) * stagger
                let up = end - Double(i) * stagger
                guard t >= down, t < up else { continue }
                if flicker, !flickered, i == 1, t > start + duration / 2 { flickered = true; continue }
                let progress = Float((t - start) / duration)
                let p = origin + SIMD2(Float(i) * 0.15, 0) + move * progress
                touches.append(Touch(id: Int32(i + 1), state: .touching, x: p.x, y: p.y, vx: 0, vy: 0, size: 1))
            }
            frames.append(TouchFrame(device: 0, timestamp: t, touches: touches))
            t += 0.01
        }
        // Final frame: every finger lifting.
        let lifting = (0..<n).map { Touch(id: Int32($0 + 1), state: .breakTouch, x: 0, y: 0, vx: 0, vy: 0, size: 0) }
        frames.append(TouchFrame(device: 0, timestamp: end, touches: lifting))
        now = end
    }

    mutating func wait(_ s: Double) { now += s }

    /// Feeds frames like the real driver would, firing `tick` at each deadline.
    func run(_ r: inout GestureRecognizer, until end: Double? = nil) -> [GestureEvent] {
        var out: [GestureEvent] = []
        var clicks = clicks[...]
        for f in frames {
            while let c = clicks.first, c <= f.timestamp { out += r.click(at: c); clicks = clicks.dropFirst() }
            if let d = r.nextDeadline, d <= f.timestamp { out += r.tick(now: d) }
            out += r.process(f)
        }
        if let d = r.nextDeadline, d <= (end ?? now + 1) { out += r.tick(now: d) }
        return out
    }
}

func gestures(_ events: [GestureEvent]) -> [Gesture] { events.map(\.gesture) }

@Suite struct TapTests {
    @Test func singleTapFiresImmediatelyWhenNothingLongerIsBound() {
        var r = GestureRecognizer(bound: [.tap(fingers: 3, count: 1)])
        var pad = Pad()
        pad.touch(fingers: 3, duration: 0.12)
        let events = pad.run(&r, until: pad.now)  // no extra time allowed
        #expect(gestures(events) == [.tap(fingers: 3, count: 1)])
        #expect(events.first?.time == pad.now)   // fired on the release frame
        #expect(r.nextDeadline == nil)
    }

    @Test func singleTapWaitsWhenALongerSequenceIsBound() {
        var r = GestureRecognizer(bound: [.tap(fingers: 3, count: 1), .tap(fingers: 3, count: 2)])
        var pad = Pad()
        pad.touch(fingers: 3, duration: 0.12)
        for f in pad.frames { #expect(r.process(f).isEmpty) }
        let deadline = try! #require(r.nextDeadline)
        #expect(r.tick(now: deadline - 0.01).isEmpty)
        #expect(gestures(r.tick(now: deadline)) == [.tap(fingers: 3, count: 1)])
    }

    @Test func doubleTapFiresOnSecondReleaseWhenItIsTheLongestBound() {
        var r = GestureRecognizer(bound: [.tap(fingers: 3, count: 2)])
        var pad = Pad()
        pad.touch(fingers: 3, duration: 0.12)
        pad.wait(0.15)
        pad.touch(fingers: 3, duration: 0.12)
        let events = pad.run(&r, until: pad.now)
        #expect(gestures(events) == [.tap(fingers: 3, count: 2)])
        #expect(events.first?.time == pad.now)
    }

    @Test func doubleTapWaitsWhenTripleIsAlsoBound() {
        var r = GestureRecognizer(bound: [.tap(fingers: 3, count: 2), .tap(fingers: 3, count: 3)])
        var pad = Pad()
        pad.touch(fingers: 3, duration: 0.12)
        pad.wait(0.15)
        pad.touch(fingers: 3, duration: 0.12)
        #expect(gestures(pad.run(&r)) == [.tap(fingers: 3, count: 2)])
    }

    @Test func tripleTapFiresImmediately() {
        var r = GestureRecognizer(bound: nil)
        var pad = Pad()
        for _ in 0..<3 { pad.touch(fingers: 2, duration: 0.1); pad.wait(0.12) }
        #expect(gestures(pad.run(&r, until: pad.now - 0.12)) == [.tap(fingers: 2, count: 3)])
    }

    @Test(arguments: 1...5)
    func countsPeakFingersDespiteStaggerAndFlicker(fingers: Int) {
        var r = GestureRecognizer(bound: [])
        var pad = Pad()
        pad.touch(fingers: fingers, duration: 0.2, at: [0.2, 0.4], stagger: 0.02, flicker: true)
        #expect(gestures(pad.run(&r)) == [.tap(fingers: fingers, count: 1)])
    }

    @Test func slowGapSplitsIntoTwoSingleTaps() {
        var r = GestureRecognizer(bound: nil)
        var pad = Pad()
        pad.touch(fingers: 3, duration: 0.1)
        pad.wait(0.4)
        pad.touch(fingers: 3, duration: 0.1)
        #expect(gestures(pad.run(&r)) == [.tap(fingers: 3, count: 1), .tap(fingers: 3, count: 1)])
    }

    @Test func differentFingerCountEndsTheSequence() {
        var r = GestureRecognizer(bound: nil)
        var pad = Pad()
        pad.touch(fingers: 2, duration: 0.1)
        pad.wait(0.1)
        pad.touch(fingers: 3, duration: 0.1)
        #expect(gestures(pad.run(&r)) == [.tap(fingers: 2, count: 1), .tap(fingers: 3, count: 1)])
    }
}

@Suite struct NonTapTests {
    @Test func dragIsIgnored() {
        var r = GestureRecognizer(bound: nil)
        var pad = Pad()
        pad.touch(fingers: 3, duration: 0.2, move: [0.1, 0])
        #expect(pad.run(&r).isEmpty)
    }

    @Test func dragAfterATapStillReportsTheTap() {
        var r = GestureRecognizer(bound: nil)
        var pad = Pad()
        pad.touch(fingers: 3, duration: 0.1)
        pad.wait(0.1)
        pad.touch(fingers: 3, duration: 0.3, move: [0.2, 0])
        #expect(gestures(pad.run(&r)) == [.tap(fingers: 3, count: 1)])
    }

    @Test func holdFiresOnceWhileFingersStayDown() {
        var r = GestureRecognizer(bound: nil)
        var pad = Pad()
        pad.touch(fingers: 2, duration: 2.0)
        let events = pad.run(&r)
        #expect(gestures(events) == [.hold(fingers: 2)])
        #expect(events[0].time < pad.now)          // before release
        #expect(events[0].time >= 100 + 1.5)       // not before holdDuration
    }

    @Test func pressBetweenTapAndHoldDoesNothing() {
        var r = GestureRecognizer(bound: nil)
        var pad = Pad()
        pad.touch(fingers: 3, duration: 0.4)
        #expect(pad.run(&r).isEmpty)
    }

    @Test func tinyJitterStillCountsAsTap() {
        var r = GestureRecognizer(bound: [])
        var pad = Pad()
        pad.touch(fingers: 3, duration: 0.15, move: [0.015, 0.01])   // like real taps (<= 0.017)
        #expect(gestures(pad.run(&r)) == [.tap(fingers: 3, count: 1)])
    }
}

@Suite struct CornerTests {
    @Test(arguments: [
        (SIMD2<Float>(0.05, 0.95), Gesture.Corner.topLeft),
        (SIMD2<Float>(0.95, 0.95), .topRight),
        (SIMD2<Float>(0.05, 0.05), .bottomLeft),
        (SIMD2<Float>(0.95, 0.05), .bottomRight),
    ])
    func oneFingerTapInCorner(at: SIMD2<Float>, corner: Gesture.Corner) {
        var r = GestureRecognizer(bound: nil)
        var pad = Pad()
        pad.touch(fingers: 1, duration: 0.08, at: at)
        #expect(gestures(pad.run(&r, until: pad.now)) == [.cornerTap(corner)])
    }

    @Test func centerOneFingerTapIsNotACorner() {
        var r = GestureRecognizer(bound: [])
        var pad = Pad()
        pad.touch(fingers: 1, duration: 0.08, at: [0.5, 0.5])
        #expect(gestures(pad.run(&r)) == [.tap(fingers: 1, count: 1)])
    }
}

/// Pressing until the pad clicks counts as a tap, however long the press lasts.
/// Durations match the user's hardware: presses of 700-3300 ms clicking at 70-400 ms.
@Suite struct ClickTests {
    @Test func pressThatClicksIsATapFiredAtTheClick() {
        var r = GestureRecognizer(bound: [.tap(fingers: 3, count: 1)])
        var pad = Pad()
        pad.touch(fingers: 3, duration: 1.4, stagger: 0.02, clickAfter: 0.4)
        let events = pad.run(&r)
        #expect(gestures(events) == [.tap(fingers: 3, count: 1)])   // no hold afterwards
        #expect(abs(events[0].time - 100.4) < 1e-6)
    }

    @Test func slowDoubleClickIsADoubleTap() {
        var r = GestureRecognizer(bound: [.tap(fingers: 3, count: 2)])
        var pad = Pad()
        pad.touch(fingers: 3, duration: 0.45, stagger: 0.02, clickAfter: 0.15)
        pad.wait(0.2)
        pad.touch(fingers: 3, duration: 0.45, stagger: 0.02, clickAfter: 0.15)
        let events = pad.run(&r)
        #expect(gestures(events) == [.tap(fingers: 3, count: 2)])
        #expect(abs(events[0].time - 100.8) < 1e-6)   // at the second click, before release
    }

    @Test func lightTapThenClickIsADoubleTap() {
        var r = GestureRecognizer(bound: [.tap(fingers: 3, count: 2)])
        var pad = Pad()
        pad.touch(fingers: 3, duration: 0.08)
        pad.wait(0.15)
        pad.touch(fingers: 3, duration: 0.6, clickAfter: 0.1)
        #expect(gestures(pad.run(&r)) == [.tap(fingers: 3, count: 2)])
    }

    @Test func tapToClickOnALightTapFiresOnce() {
        // macOS tap-to-click sends a click right as a light tap lifts.
        var r = GestureRecognizer(bound: [])
        var pad = Pad()
        pad.touch(fingers: 3, duration: 0.072, clickAfter: 0.069)
        #expect(gestures(pad.run(&r)) == [.tap(fingers: 3, count: 1)])
    }

    @Test func oneFingerClickIsANormalClick() {
        var r = GestureRecognizer(bound: nil)
        var pad = Pad()
        pad.touch(fingers: 1, duration: 0.3, at: [0.5, 0.5], clickAfter: 0.1)
        #expect(pad.run(&r).isEmpty)
    }

    @Test func clickAfterAHoldFiredAddsNothing() {
        var r = GestureRecognizer(bound: nil)
        var pad = Pad()
        pad.touch(fingers: 3, duration: 2.0, clickAfter: 1.7)
        #expect(gestures(pad.run(&r)) == [.hold(fingers: 3)])
    }

    @Test func slowPressClickingAfterASecondIsATapNotAHold() {
        // Real press from the user's log: 2768 ms touch that clicked at 1144 ms.
        var r = GestureRecognizer(bound: [.tap(fingers: 3, count: 1), .hold(fingers: 3)])
        var pad = Pad()
        pad.touch(fingers: 3, duration: 2.768, stagger: 0.02, clickAfter: 1.144)
        #expect(gestures(pad.run(&r)) == [.tap(fingers: 3, count: 1)])
    }

    @Test func usersSlowDoubleClickIsADoubleTap() {
        // First press clicked at 474 ms of 1032 ms; second at 1144 ms.
        var r = GestureRecognizer(bound: [.tap(fingers: 3, count: 2), .hold(fingers: 3)])
        var pad = Pad()
        pad.touch(fingers: 3, duration: 1.032, stagger: 0.02, clickAfter: 0.474)
        pad.wait(0.2)
        pad.touch(fingers: 3, duration: 2.768, stagger: 0.02, clickAfter: 1.144)
        #expect(gestures(pad.run(&r)) == [.tap(fingers: 3, count: 2)])
    }

    @Test func longTouchWithoutClickEndsASequence() {
        var r = GestureRecognizer(bound: nil)
        var pad = Pad()
        pad.touch(fingers: 3, duration: 0.08)
        pad.wait(0.1)
        pad.touch(fingers: 3, duration: 0.4)   // between tap and hold, never clicked
        #expect(gestures(pad.run(&r)) == [.tap(fingers: 3, count: 1)])
    }
}
