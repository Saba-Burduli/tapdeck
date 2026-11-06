import Actions
import Config
import Foundation
import Observation
import Recognizer
import TouchInput

/// The always-on pipeline: trackpad frames + clicks -> GestureRecognizer -> actions.
///
/// Touch frames arrive on a private MultitouchSupport thread and are recognized
/// there (lock-protected `Core`), so recognition never waits on the UI. Results hop
/// to the main actor, where actions run and SwiftUI observes state.
@MainActor @Observable
public final class Engine {
    public struct Fired: Equatable, Sendable {
        public var gesture: Gesture
        public var action: Action?
        public var error: String?
        public var date: Date
    }

    // Observed by the UI.
    public private(set) var isRunning = false
    public private(set) var startError: String?
    public private(set) var lastFired: Fired?
    public private(set) var accessibilityTrusted = Permissions.isAccessibilityTrusted
    /// Fingers currently on the pad, for the live visualizer (only while `showsLiveTouches`).
    public private(set) var liveTouches: [Touch] = []
    public var showsLiveTouches = false {
        didSet { core.setWantsTouches(showsLiveTouches); if !showsLiveTouches { liveTouches = [] } }
    }

    public var config: AppConfig {
        didSet { core.apply(config, recording: recorder != nil) }
    }

    @ObservationIgnored private let core = Core()
    @ObservationIgnored private let touches = MultitouchSource()
    @ObservationIgnored private let clicks = ClickSource()
    @ObservationIgnored private let runner = ActionRunner()
    @ObservationIgnored private var tickWork: DispatchWorkItem?
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var recorder: ((Gesture) -> Void)?

    public init(config: AppConfig) {
        self.config = config
        core.apply(config, recording: false)
    }

    public func start() {
        guard !isRunning else { return }
        let core = self.core
        do {
            try touches.start { [weak self] frame in
                let (events, deadline, live) = core.process(frame)
                guard !events.isEmpty || deadline != nil || live != nil else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.handle(events, deadline: deadline, live: live) }
                }
            }
        } catch {
            startError = "\(error)"
            return
        }
        // Clicks are optional: without them, light taps still work.
        try? clicks.start { [weak self] in
            let (events, deadline) = core.click()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(events, deadline: deadline, live: nil) }
            }
        }
        isRunning = true
        startError = nil
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.accessibilityTrusted = Permissions.isAccessibilityTrusted }
        }
    }

    public func stop() {
        touches.stop()
        clicks.stop()
        tickWork?.cancel()
        permissionTimer?.invalidate()
        isRunning = false
    }

    /// The next recognized gesture goes to `handler` instead of running an action.
    /// While recording, every gesture counts as bound, so multi-taps are captured whole.
    public func recordNextGesture(_ handler: @escaping (Gesture) -> Void) {
        recorder = handler
        core.apply(config, recording: true)
    }

    public func cancelRecording() {
        recorder = nil
        core.apply(config, recording: false)
    }

    public func refreshPermissions() { accessibilityTrusted = Permissions.isAccessibilityTrusted }

    // MARK: - Private

    private func handle(_ events: [GestureEvent], deadline: Double?, live: [Touch]?) {
        if let live, showsLiveTouches { liveTouches = live }
        if let deadline { scheduleTick(at: deadline) }
        for e in events { fire(e.gesture) }
    }

    private func fire(_ gesture: Gesture) {
        if let recorder {
            cancelRecording()
            recorder(gesture)
            return
        }
        guard let action = config.activeBindings[gesture] else { return }
        var failure: String?
        do { try runner.run(action) } catch { failure = "\(error)" }
        lastFired = Fired(gesture: gesture, action: action, error: failure, date: Date())
    }

    /// One-shot timer for the earliest pending multi-tap; no polling while idle.
    private func scheduleTick(at deadline: Double) {
        tickWork?.cancel()
        let delay = max(0, deadline - core.frameNow)
        let core = self.core
        let work = DispatchWorkItem { [weak self] in
            let (events, next) = core.tick()
            MainActor.assumeIsolated { self?.handle(events, deadline: next, live: nil) }
        }
        tickWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// Recognizer state shared between the multitouch thread and the main actor.
final class Core: @unchecked Sendable {
    private let lock = NSLock()
    private var recognizers: [Int: GestureRecognizer] = [:]
    private var recognizerConfig = RecognizerConfig()
    private var bound: Set<Gesture>? = []
    private var clockOffset: Double?
    private var wantsTouches = false
    private var lastLiveSent: Double = 0

    /// Current time on the multitouch frame clock.
    var frameNow: Double {
        lock.withLock { ProcessInfo.processInfo.systemUptime - (clockOffset ?? 0) }
    }

    func apply(_ config: AppConfig, recording: Bool) {
        lock.withLock {
            recognizerConfig = config.recognizer
            bound = recording ? nil : Set(config.activeBindings.keys)
            for d in recognizers.keys {
                recognizers[d]?.config = recognizerConfig
                recognizers[d]?.bound = bound
            }
        }
    }

    func setWantsTouches(_ on: Bool) { lock.withLock { wantsTouches = on } }

    func process(_ frame: TouchFrame) -> ([GestureEvent], Double?, [Touch]?) {
        lock.withLock {
            clockOffset = ProcessInfo.processInfo.systemUptime - frame.timestamp
            var r = recognizers[frame.device] ?? GestureRecognizer(config: recognizerConfig, bound: bound)
            let events = r.process(frame)
            recognizers[frame.device] = r
            var live: [Touch]?
            // Visualizer: at most ~30 updates per second, plus the final "all lifted" frame.
            let down = frame.touches.filter(\.state.isDown)
            if wantsTouches, frame.timestamp - lastLiveSent > 1.0 / 30 || down.isEmpty {
                live = down
                lastLiveSent = frame.timestamp
            }
            return (events, r.nextDeadline, live)
        }
    }

    func click() -> ([GestureEvent], Double?) {
        lock.withLock {
            let now = ProcessInfo.processInfo.systemUptime - (clockOffset ?? 0)
            var events: [GestureEvent] = []
            for d in recognizers.keys {
                events += recognizers[d]!.click(at: now)
            }
            return (events, earliestDeadline())
        }
    }

    func tick() -> ([GestureEvent], Double?) {
        lock.withLock {
            let now = ProcessInfo.processInfo.systemUptime - (clockOffset ?? 0)
            var events: [GestureEvent] = []
            for d in recognizers.keys {
                events += recognizers[d]!.tick(now: now)
            }
            return (events, earliestDeadline())
        }
    }

    private func earliestDeadline() -> Double? {
        recognizers.values.compactMap(\.nextDeadline).min()
    }
}
