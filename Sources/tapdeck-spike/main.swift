// Milestone 1 spike: prove global trackpad capture works on this Mac.
// Prints a line whenever the number of fingers on a pad changes, plus
// a summary per contact session (duration, peak fingers, travel).
import Foundation
import TouchInput

setvbuf(stdout, nil, _IOLBF, 0)

final class Session: @unchecked Sendable {
    let lock = NSLock()
    var lastCount: [Int: Int] = [:]
    var start: [Int: Double] = [:]
    var peak: [Int: Int] = [:]
    var origin: [Int: [Int32: (Float, Float)]] = [:]
    var travel: [Int: Float] = [:]
    var frames = 0
    var states: [Int32: Int] = [:]  // raw state histogram (debug)
}
let s = Session()
let t0 = Date().timeIntervalSinceReferenceDate

let source = MultitouchSource()
do {
    try source.start { frame in
        s.lock.lock(); defer { s.lock.unlock() }
        s.frames += 1
        for t in frame.touches { s.states[t.state.rawValue, default: 0] += 1 }
        let d = frame.device
        let n = frame.fingersDown
        let prev = s.lastCount[d] ?? 0

        for t in frame.touches where t.state.isDown {
            if let o = s.origin[d, default: [:]][t.id] {
                s.travel[d] = max(s.travel[d] ?? 0, hypot(t.x - o.0, t.y - o.1))
            } else {
                s.origin[d, default: [:]][t.id] = (t.x, t.y)
            }
        }

        guard n != prev else { return }
        s.lastCount[d] = n
        if prev == 0 { s.start[d] = frame.timestamp; s.peak[d] = 0; s.travel[d] = 0; s.origin[d] = [:] }
        s.peak[d] = max(s.peak[d] ?? 0, n)

        let pts = frame.touches.filter(\.state.isDown)
            .map { String(format: "(%.2f,%.2f)", $0.x, $0.y) }.joined(separator: " ")
        print(String(format: "[%7.3fs] pad %d: %d -> %d fingers %@", Date().timeIntervalSinceReferenceDate - t0, d, prev, n, pts))

        if n == 0, let st = s.start[d] {
            let ms = (frame.timestamp - st) * 1000
            print(String(format: "           session: %.0f ms, peak %d fingers, max travel %.3f (pad units)", ms, s.peak[d] ?? 0, s.travel[d] ?? 0))
        }
    }
    print("TapDeck spike: capturing from \(source.deviceCount) trackpad(s). Tap with 1-5 fingers. Ctrl-C to quit.")
} catch {
    print("TapDeck spike failed: \(error)")
    exit(1)
}

// Debug heartbeat: proves whether frames arrive at all, and which states we see.
let debug = CommandLine.arguments.contains("--debug")
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now() + 1, repeating: 1)
timer.setEventHandler {
    guard debug else { return }
    s.lock.lock(); defer { s.lock.unlock() }
    if s.frames > 0 { print("  [debug] frames=\(s.frames) states=\(s.states.sorted { $0.key < $1.key })") }
    s.frames = 0; s.states = [:]
}
timer.resume()
CFRunLoopRun()
