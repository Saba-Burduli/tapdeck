// TapDeck spike: a terminal harness for the touch pipeline.
//   (default)    raw mode: finger-count changes + per-touch duration/travel
//   --debug      also print a per-second frame/state heartbeat
//   --gestures   run the GestureRecognizer and perform a demo set of real actions
//   --record     like --gestures, but every gesture counts as bound (multi-taps always wait)
//   --calibrate  measure your taps and holds, fit thresholds, then run --gestures with them
import Actions
import Foundation
import Recognizer
import TouchInput

setvbuf(stdout, nil, _IOLBF, 0)

let args = CommandLine.arguments
let debug = args.contains("--debug")
let calibrate = args.contains("--calibrate")
let recordMode = args.contains("--record")
let gestureMode = recordMode || calibrate || args.contains("--gestures")

/// Demo bindings: every one of these really runs.
let demoBindings: [Gesture: Action] = [
    .tap(fingers: 3, count: 2): .openApp(bundleID: "com.apple.calculator"),
    .tap(fingers: 4, count: 1): .window(.leftHalf),
    .tap(fingers: 4, count: 2): .window(.rightHalf),
    .tap(fingers: 5, count: 1): .media(.playPause),
    .hold(fingers: 3): .keystroke(.missionControl),
    .cornerTap(.topRight): .keystroke(.spotlight),
]
let runner = ActionRunner()

/// All mutable state; touched from the multitouch thread and the main run loop.
final class State: @unchecked Sendable {
    let lock = NSLock()
    // Raw per-device contact tracking.
    var lastCount: [Int: Int] = [:]
    var start: [Int: Double] = [:]
    var peak: [Int: Int] = [:]
    var origin: [Int: [Int32: SIMD2<Float>]] = [:]
    var travel: [Int: Float] = [:]      // worst single finger
    var medTravel: [Int: Float] = [:]   // median finger (what the recognizer uses)
    var clicked: [Int: Bool] = [:]
    var clickAt: [Int: Double] = [:]   // ms after the contact started
    var lastEnd: [Int: Double] = [:]   // frame time the previous contact ended
    var lastGap: [Int: Double] = [:]   // gap before the current contact
    // Debug heartbeat.
    var frames = 0
    var states: [Int32: Int] = [:]
    // Gestures.
    var config = RecognizerConfig()
    var recognizers: [Int: GestureRecognizer] = [:]
    /// systemUptime - frame clock, so timers and clicks can be expressed in frame time.
    var clockOffset: Double?
    // Calibration.
    enum Phase { case taps, done }
    var phase: Phase = calibrate ? .taps : .done
    var tapSamples: [Calibration.Sample] = []

    var frameNow: Double { ProcessInfo.processInfo.systemUptime - (clockOffset ?? 0) }

    func recognizer(for device: Int) -> GestureRecognizer {
        recognizers[device] ?? GestureRecognizer(config: config, bound: recordMode ? nil : Set(demoBindings.keys))
    }

    func report(_ events: [GestureEvent]) {
        for e in events {
            let lag = (frameNow - e.time) * 1000
            let action = demoBindings[e.gesture].map { "-> \($0)" } ?? "(unbound)"
            print(String(format: "  %@  %@   [%.1f ms]", e.gesture.description, action, lag))
            guard let a = demoBindings[e.gesture] else { continue }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    do { try runner.run(a) } catch { print("      ! \(error)") }
                }
            }
        }
    }

    /// Called with the lock held when every finger has left the pad.
    func contactEnded(device d: Int, duration: Double) {
        let fingers = peak[d] ?? 0, moved = travel[d] ?? 0, didClick = clicked[d] ?? false
        let clickNote = didClick ? String(format: ", clicked at %.0f ms", clickAt[d] ?? -1) : ""
        let gapNote = lastGap[d].map { String(format: ", %.0f ms after previous touch", $0 * 1000) } ?? ""
        print(String(format: "    · touch: %.0f ms, %d fingers, travel %.3f (worst finger %.3f)%@%@",
                     duration * 1000, fingers, medTravel[d] ?? 0, moved, clickNote, gapNote))
        guard phase == .taps, fingers >= 2 else { return }
        guard !didClick, duration < 1.0 else {
            print("      (skipped: \(didClick ? "it clicked" : "too long for a tap"); tap lightly)")
            return
        }
        tapSamples.append(.init(duration: duration, travel: moved))
        print("      tap \(tapSamples.count)/5 recorded")
        guard tapSamples.count == 5 else { return }
        // Taps only: the hold threshold is derived from the taps (never overlaps them).
        config = Calibration.fit(taps: tapSamples, holds: [])
        recognizers = [:]
        phase = .done
        print(String(format: "\nCalibrated: taps up to %.0f ms, holds from %.0f ms, max travel %.3f. Gestures are live.",
                      config.maxTapDuration * 1000, config.holdDuration * 1000, config.maxTravel))
        printBindings()
    }

    func printBindings() {
        print(recordMode ? "Record mode: every gesture is treated as bound." : "Demo bindings:")
        if !recordMode {
            for (g, a) in demoBindings.sorted(by: { $0.key.description < $1.key.description }) { print("  \(g) -> \(a)") }
        }
    }
}
let s = State()
let t0 = Date().timeIntervalSinceReferenceDate

let source = MultitouchSource()
do {
    try source.start { frame in
        s.lock.lock(); defer { s.lock.unlock() }
        s.frames += 1
        for t in frame.touches { s.states[t.state.rawValue, default: 0] += 1 }
        s.clockOffset = ProcessInfo.processInfo.systemUptime - frame.timestamp

        if gestureMode, s.phase == .done {
            var r = s.recognizer(for: frame.device)
            let events = r.process(frame)
            s.recognizers[frame.device] = r
            s.report(events)
        }

        let d = frame.device
        let down = frame.touches.filter(\.state.isDown)
        let prev = s.lastCount[d] ?? 0
        if prev == 0, !down.isEmpty {
            s.start[d] = frame.timestamp; s.peak[d] = 0; s.travel[d] = 0; s.medTravel[d] = 0; s.origin[d] = [:]; s.clicked[d] = false
            s.lastGap[d] = s.lastEnd[d].map { frame.timestamp - $0 }
        }
        var dists: [Float] = []
        for t in down {
            let p = SIMD2(t.x, t.y)
            if let o = s.origin[d]?[t.id] {
                let v = p - o
                let dist = (v * v).sum().squareRoot()
                dists.append(dist)
                s.travel[d] = max(s.travel[d] ?? 0, dist)
            } else {
                s.origin[d, default: [:]][t.id] = p
                dists.append(0)
            }
        }
        dists.sort()
        if !dists.isEmpty {
            let m = dists.count / 2
            let med = dists.count.isMultiple(of: 2) ? (dists[m - 1] + dists[m]) / 2 : dists[m]
            s.medTravel[d] = max(s.medTravel[d] ?? 0, med)
        }
        guard down.count != prev else { return }
        s.lastCount[d] = down.count
        s.peak[d] = max(s.peak[d] ?? 0, down.count)

        if !gestureMode {
            let pts = down.map { String(format: "(%.2f,%.2f)", $0.x, $0.y) }.joined(separator: " ")
            print(String(format: "[%7.3fs] pad %d: %d -> %d fingers %@",
                         Date().timeIntervalSinceReferenceDate - t0, d, prev, down.count, pts))
        }
        if down.isEmpty, let st = s.start[d] {
            s.contactEnded(device: d, duration: frame.timestamp - st)
            s.lastEnd[d] = frame.timestamp
        }
    }
    print("TapDeck spike: capturing from \(source.deviceCount) trackpad(s). Ctrl-C to quit.")
} catch {
    print("TapDeck spike failed: \(error)")
    exit(1)
}

let clicks = ClickSource()
if gestureMode {
    do {
        try clicks.start {
            s.lock.lock(); defer { s.lock.unlock() }
            for d in s.lastCount.keys where (s.lastCount[d] ?? 0) > 0 && s.clicked[d] != true {
                s.clicked[d] = true
                s.clickAt[d] = (s.frameNow - (s.start[d] ?? s.frameNow)) * 1000
            }
            guard s.phase == .done else { return }
            let now = s.frameNow
            for (d, var r) in s.recognizers {
                let events = r.click(at: now)
                s.recognizers[d] = r
                s.report(events)
            }
        }
    } catch {
        print("Warning: \(error). Click gestures disabled.")
    }
    // Only show the system prompt when asked (--prompt); otherwise it pops up on every launch.
    let trusted = args.contains("--prompt") ? Permissions.requestAccessibility() : Permissions.isAccessibilityTrusted
    if !trusted {
        print("""

        ⚠️  Keystrokes, window moves and media keys need Accessibility permission.
            macOS should now show a prompt; or open System Settings > Privacy & Security >
            Accessibility and turn on TapDeck (or the app running this terminal), then restart.
            (Opening apps works without it.)

        """)
    }
    if calibrate {
        print("\nCalibration: TAP lightly with 3 fingers, 5 times. Don't press until it clicks.")
    } else {
        s.printBindings()
    }
}

// Debug heartbeat: proves whether frames arrive at all, and which states we see.
let heartbeat = DispatchSource.makeTimerSource(queue: .main)
heartbeat.schedule(deadline: .now() + 1, repeating: 1)
nonisolated(unsafe) var lastTrusted: Bool?
heartbeat.setEventHandler {
    // Live permission status, so granting it in System Settings shows up here.
    let trusted = Permissions.isAccessibilityTrusted
    if gestureMode, trusted != lastTrusted {
        print(trusted ? "✅ Accessibility: ON — keystrokes, windows and media keys will work."
                      : "⛔️ Accessibility: OFF for this build of TapDeck.")
        lastTrusted = trusted
    }
    guard debug else { return }
    s.lock.lock(); defer { s.lock.unlock() }
    if s.frames > 0 { print("  [debug] frames=\(s.frames) states=\(s.states.sorted { $0.key < $1.key })") }
    s.frames = 0; s.states = [:]
}
heartbeat.resume()

// Resolves pending multi-taps once fingers are off the pad (no frames arrive then).
let ticker = DispatchSource.makeTimerSource(queue: .main)
ticker.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
ticker.setEventHandler {
    guard gestureMode else { return }
    s.lock.lock(); defer { s.lock.unlock() }
    guard s.clockOffset != nil else { return }
    let now = s.frameNow
    for (d, var r) in s.recognizers where r.nextDeadline.map({ now >= $0 }) == true {
        let events = r.tick(now: now)
        s.recognizers[d] = r
        s.report(events)
    }
}
ticker.resume()
CFRunLoopRun()
