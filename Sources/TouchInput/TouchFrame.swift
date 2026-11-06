import Foundation

/// Lifecycle state of a single contact, as reported by MultitouchSupport.
public enum TouchState: Int32, Sendable {
    case notTracking = 0, startInRange, hoverInRange, makeTouch, touching, breakTouch, lingerInRange, outOfRange

    /// True while the finger is physically on the pad.
    public var isDown: Bool { self == .makeTouch || self == .touching }
}

public struct Touch: Sendable, Equatable {
    public var id: Int32
    public var state: TouchState
    /// Normalized position, 0...1, origin bottom-left.
    public var x: Float
    public var y: Float
    public var vx: Float
    public var vy: Float
    public var size: Float

    public init(id: Int32, state: TouchState, x: Float, y: Float, vx: Float, vy: Float, size: Float) {
        self.id = id; self.state = state; self.x = x; self.y = y; self.vx = vx; self.vy = vy; self.size = size
    }
}

/// One sensor frame from one trackpad (~90-120 Hz).
public struct TouchFrame: Sendable {
    public var device: Int
    public var timestamp: Double
    public var touches: [Touch]

    public init(device: Int, timestamp: Double, touches: [Touch]) {
        self.device = device; self.timestamp = timestamp; self.touches = touches
    }

    public var fingersDown: Int { touches.lazy.filter(\.state.isDown).count }
}

/// Anything that can stream touch frames. Keeps the private API swappable/mocked.
public protocol TouchSource: AnyObject {
    func start(_ handler: @escaping @Sendable (TouchFrame) -> Void) throws
    func stop()
}
