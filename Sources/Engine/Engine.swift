import Actions
import AppKit
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
        /// "My shortcut" or the pack's name.
        public var source: String?
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

    #if DEBUG
    /// Feeds synthetic fingers to the visualizer, for screenshots without a real hand on the pad.
    public func injectLiveTouches(_ touches: [Touch]) { liveTouches = touches }
    #endif

    public var config: AppConfig {
        didSet { rearm() }
    }
    /// Bundle ID of the frontmost app; app-specific shortcuts and packs follow it.
    public private(set) var frontApp: String? = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

    @ObservationIgnored private let core = Core()
    @ObservationIgnored private let touches = MultitouchSource()
    @ObservationIgnored private let clicks = ClickSource()
    @ObservationIgnored private let runner = ActionRunner()
    @ObservationIgnored private var tickWork: DispatchWorkItem?
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var recorder: ((Gesture) -> Void)?
    @ObservationIgnored private var appObserver: NSObjectProtocol?

    public init(config: AppConfig) {
        self.config = config
        rearm()
    }

    /// Tells the recognizer which gestures are live for the current app, so a
    /// tap only waits for a double tap when one is bound right here.
    private func rearm() {
        core.apply(config, bound: recorder != nil ? nil : Set(config.activeBindings(frontApp: frontApp).keys))
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
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, self.frontApp != id else { return }
                self.frontApp = id
                self.rearm()
            }
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.accessibilityTrusted = Permissions.isAccessibilityTrusted }
        }
    }

    public func stop() {
        touches.stop()
        clicks.stop()
        tickWork?.cancel()
        permissionTimer?.invalidate()
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        appObserver = nil
        isRunning = false
    }

    /// The next recognized gesture goes to `handler` instead of running an action.
    /// While recording, every gesture counts as bound, so multi-taps are captured whole.
    public func recordNextGesture(_ handler: @escaping (Gesture) -> Void) {
        recorder = handler
        rearm()
    }

    public func cancelRecording() {
        recorder = nil
        rearm()
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
        // Ask for the frontmost app now rather than trusting the last notification.
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? frontApp
        guard let (action, source) = config.resolved(frontApp: front)[gesture] else { return }
        var failure: String?
        do { try runner.run(action) } catch { failure = "\(error)" }
        let from: String = switch source {
        case .mine: "My shortcut"
        case let .pack(_, name): name
        }
        lastFired = Fired(gesture: gesture, action: action, source: from, error: failure, date: Date())
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

    /// `bound` = gestures with an action right now; nil while recording a gesture.
    func apply(_ config: AppConfig, bound: Set<Gesture>?) {
        lock.withLock {
            recognizerConfig = config.recognizer
            self.bound = bound
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
            // Visualizer: at most ~60 updates per second, plus the final "all lifted" frame.
            let down = frame.touches.filter(\.state.isDown)
            if wantsTouches, frame.timestamp - lastLiveSent > 1.0 / 60 || down.isEmpty {
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
