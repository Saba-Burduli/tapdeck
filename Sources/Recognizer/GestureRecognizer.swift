import TouchInput

/// Turns a stream of touch frames from one trackpad into gestures.
///
/// Pure state machine with no OS dependencies or timers. Feed every frame to
/// `process(_:)` and every trackpad click (mouse button down) to `click(at:)`.
/// While `nextDeadline` is non-nil, call `tick(now:)` at or after that time,
/// because a pending multi-tap may need to resolve once frames stop.
///
/// A "tap" is either a light, quick touch or a press that clicks the pad. People
/// mix both freely, so a light tap followed by a click is a double tap.
///
/// Speed rule: a tap fires the moment it's released (light tap) or the moment the
/// pad clicks (press). The exception is when a longer sequence with the same
/// finger count is bound; only then does it wait up to `multiTapInterval` for
/// the next tap.
public struct GestureRecognizer: Sendable {
    public var config: RecognizerConfig
    /// Gestures that have an action. `nil` means "treat everything as bound"
    /// (e.g. while recording a gesture), so multi-taps always wait.
    public var bound: Set<Gesture>?

    public init(config: RecognizerConfig = .init(), bound: Set<Gesture>? = nil) {
        self.config = config
        self.bound = bound
    }

    /// One continuous contact: from the first finger down until every finger is up.
    private struct Contact {
        var start: Double
        var peakFingers = 0
        var origins: [Int32: SIMD2<Float>] = [:]
        var travel: Float = 0
        var firstPosition: SIMD2<Float>?
        /// Can no longer become a light tap or hold (moved, too long, held, or clicked).
        var disqualified = false
        /// The pad clicked during this contact; its tap was already handled.
        var clicked = false
    }

    /// Taps waiting to see whether another tap extends the sequence.
    private struct Pending {
        var fingers: Int
        var count: Int
        /// When the contact that produced the last tap was released.
        /// `nil` while that contact is still down (a click fires before release).
        var releaseTime: Double?
    }

    private var contact: Contact?
    private var pending: Pending?

    /// When `tick(now:)` must next be called, if ever.
    public var nextDeadline: Double? {
        guard contact == nil, let release = pending?.releaseTime else { return nil }
        return release + config.multiTapInterval
    }

    public mutating func process(_ frame: TouchFrame) -> [GestureEvent] {
        let now = frame.timestamp
        let down = frame.touches.filter(\.state.isDown)
        var out: [GestureEvent] = []

        if contact == nil {
            out += tick(now: now)
            guard !down.isEmpty else { return out }
            contact = Contact(start: now)
        }
        guard var c = contact else { return out }

        c.peakFingers = max(c.peakFingers, down.count)
        c.travel = max(c.travel, Self.updateTravel(&c, down: down))

        let elapsed = now - c.start
        if !c.disqualified, c.travel > config.maxTravel {
            // A swipe or drag: not ours. Earlier taps in a sequence still count.
            c.disqualified = true
            out += flushPending(at: now)
        } else if !c.disqualified, !down.isEmpty, elapsed >= config.holdDuration {
            c.disqualified = true
            out += flushPending(at: now)
            out.append(GestureEvent(gesture: .hold(fingers: c.peakFingers), time: now))
        }
        // A touch that's too long for a light tap may still click, which would
        // extend a pending sequence, so pending taps resolve at release or deadline.

        if down.isEmpty {
            contact = nil
            out += release(c, at: now)
        } else {
            contact = c
        }
        return out
    }

    /// The pad clicked (mouse button down). The current contact counts as a tap
    /// right now, however long it has lasted, unless it already became a hold or drag.
    public mutating func click(at now: Double) -> [GestureEvent] {
        guard var c = contact, !c.clicked else { return [] }
        let wasDisqualified = c.disqualified
        c.clicked = true
        c.disqualified = true
        contact = c
        // One-finger clicks are ordinary clicks; holds and drags already resolved.
        guard c.peakFingers >= 2, !wasDisqualified else { return [] }
        return registerTap(fingers: c.peakFingers, contactStart: c.start, at: now, releaseTime: nil)
    }

    /// Resolves a pending multi-tap whose waiting window has passed.
    public mutating func tick(now: Double) -> [GestureEvent] {
        guard let deadline = nextDeadline, now >= deadline else { return [] }
        return flushPending(at: now)
    }

    // MARK: - Private

    /// How far the contact has moved this frame: the median finger's distance
    /// from where it landed. In a swipe every finger moves; in a 4-5 finger tap
    /// one finger (often the pinky, landing late or rolling off) can drift a lot,
    /// and the median ignores it. Also forgets fingers that lifted, so a reused
    /// touch id starts from its own landing point.
    private static func updateTravel(_ c: inout Contact, down: [Touch]) -> Float {
        let ids = Set(down.map(\.id))
        c.origins = c.origins.filter { ids.contains($0.key) }
        var distances: [Float] = []
        for t in down {
            let p = SIMD2(t.x, t.y)
            if c.firstPosition == nil { c.firstPosition = p }
            if let o = c.origins[t.id] {
                let d = p - o
                distances.append((d * d).sum().squareRoot())
            } else {
                c.origins[t.id] = p
                distances.append(0)
            }
        }
        return Self.median(distances)
    }

    static func median(_ xs: [Float]) -> Float {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted(), m = s.count / 2
        return s.count.isMultiple(of: 2) ? (s[m - 1] + s[m]) / 2 : s[m]
    }

    private mutating func release(_ c: Contact, at now: Double) -> [GestureEvent] {
        if c.clicked {
            // The tap already fired at the click; start the multi-tap window now.
            if pending != nil, pending?.releaseTime == nil { pending?.releaseTime = now }
            return []
        }
        guard !c.disqualified, now - c.start <= config.maxTapDuration, c.peakFingers > 0 else {
            // Not a tap. A pending sequence can't be extended by it.
            return flushPending(at: now)
        }
        let fingers = c.peakFingers

        if fingers == 1, let pos = c.firstPosition, let corner = corner(at: pos) {
            return flushPending(at: now) + [GestureEvent(gesture: .cornerTap(corner), time: now)]
        }
        return registerTap(fingers: fingers, contactStart: c.start, at: now, releaseTime: now)
    }

    /// Adds a tap to the current sequence (or starts one), then fires or waits.
    private mutating func registerTap(
        fingers: Int, contactStart: Double, at now: Double, releaseTime: Double?
    ) -> [GestureEvent] {
        var out: [GestureEvent] = []
        var count = 1
        if let p = pending {
            if p.fingers == fingers, let last = p.releaseTime, contactStart - last <= config.multiTapInterval {
                count = p.count + 1
                pending = nil
            } else {
                out += flushPending(at: now)
            }
        }
        if count >= RecognizerConfig.maxTapCount || !wantsLongerSequence(fingers: fingers, than: count) {
            out.append(GestureEvent(gesture: .tap(fingers: fingers, count: count), time: now))
        } else {
            pending = Pending(fingers: fingers, count: count, releaseTime: releaseTime)
        }
        return out
    }

    private mutating func flushPending(at now: Double) -> [GestureEvent] {
        guard let p = pending else { return [] }
        pending = nil
        return [GestureEvent(gesture: .tap(fingers: p.fingers, count: p.count), time: now)]
    }

    private func wantsLongerSequence(fingers: Int, than count: Int) -> Bool {
        guard let bound else { return true }
        return bound.contains {
            if case let .tap(f, c) = $0 { return f == fingers && c > count }
            return false
        }
    }

    private func corner(at p: SIMD2<Float>) -> Gesture.Corner? {
        let s = config.cornerSize
        let left = p.x < s, right = p.x > 1 - s
        let bottom = p.y < s, top = p.y > 1 - s   // origin is bottom-left
        switch (left, right, top, bottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        default: return nil
        }
    }
}
