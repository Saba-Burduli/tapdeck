import CoreGraphics
import Foundation

/// Reports physical trackpad clicks (mouse button down), which never appear in
/// multitouch frames. Uses a listen-only event tap: it observes, never blocks or
/// alters, the click.
public final class ClickSource: @unchecked Sendable {
    public enum Error: Swift.Error, CustomStringConvertible {
        case tapUnavailable
        public var description: String {
            "Could not create a mouse event tap (check Accessibility / Input Monitoring permission)"
        }
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    fileprivate var handler: (@Sendable () -> Void)?

    public init() {}

    /// `handler` runs on the current thread's run loop for every left/right button press.
    public func start(_ handler: @escaping @Sendable () -> Void) throws {
        self.handler = handler
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, ctx in
                guard let ctx else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<ClickSource>.fromOpaque(ctx).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                } else {
                    me.handler?()
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { throw Error.tapUnavailable }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        tap = nil; source = nil; handler = nil
    }
}
