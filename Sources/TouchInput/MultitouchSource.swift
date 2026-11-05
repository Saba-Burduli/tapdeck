import CMultitouch
import Foundation
import os

public enum MultitouchError: Error, CustomStringConvertible {
    case frameworkNotFound
    case symbolMissing(String)
    case noDevices

    public var description: String {
        switch self {
        case .frameworkNotFound: "MultitouchSupport.framework could not be loaded"
        case .symbolMissing(let s): "MultitouchSupport symbol missing: \(s)"
        case .noDevices: "No multitouch trackpads found"
        }
    }
}

/// Global, system-wide touch capture via Apple's private MultitouchSupport.framework.
/// Only one instance should run at a time (the C callback cannot carry context).
public final class MultitouchSource: TouchSource, @unchecked Sendable {
    private static let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    // The C callback has no user-data pointer, so the active handler lives here.
    private static let state = OSAllocatedUnfairLock<State>(initialState: State())
    private struct State {
        var handler: (@Sendable (TouchFrame) -> Void)?
        var deviceIndex: [UInt: Int] = [:]
    }

    private var deviceList: NSArray?  // keeps the device objects alive
    private var devices: [MTDeviceRef] = []
    private var register: MTRegisterContactFrameCallbackFn?
    private var unregister: MTUnregisterContactFrameCallbackFn?
    private var startFn: MTDeviceStartFn?
    private var stopFn: MTDeviceStopFn?

    public init() {}

    public var deviceCount: Int { devices.count }

    public func start(_ handler: @escaping @Sendable (TouchFrame) -> Void) throws {
        guard let lib = dlopen(Self.path, RTLD_NOW) else { throw MultitouchError.frameworkNotFound }

        func sym<T>(_ name: String, as: T.Type) throws -> T {
            guard let p = dlsym(lib, name) else { throw MultitouchError.symbolMissing(name) }
            return unsafeBitCast(p, to: T.self)
        }
        let createList = try sym("MTDeviceCreateList", as: MTDeviceCreateListFn.self)
        register = try sym("MTRegisterContactFrameCallback", as: MTRegisterContactFrameCallbackFn.self)
        unregister = try sym("MTUnregisterContactFrameCallback", as: MTUnregisterContactFrameCallbackFn.self)
        startFn = try sym("MTDeviceStart", as: MTDeviceStartFn.self)
        stopFn = try sym("MTDeviceStop", as: MTDeviceStopFn.self)

        guard let list = createList() else { throw MultitouchError.noDevices }
        let nsList = list.takeRetainedValue() as NSArray
        deviceList = nsList
        let array = nsList as [AnyObject]
        devices = array.map { Unmanaged.passUnretained($0).toOpaque() }
        guard !devices.isEmpty else { throw MultitouchError.noDevices }

        let indexMap = Dictionary(uniqueKeysWithValues: devices.enumerated().map { (UInt(bitPattern: $1), $0) })
        Self.state.withLock {
            $0.handler = handler
            $0.deviceIndex = indexMap
        }
        for d in devices {
            register?(d, Self.callback)
            startFn?(d, 0)
        }
    }

    public func stop() {
        for d in devices {
            unregister?(d, Self.callback)
            stopFn?(d)
        }
        devices.removeAll()
        deviceList = nil
        Self.state.withLock { $0 = State() }
    }

    private static let callback: MTContactCallbackFunction = { device, touches, count, timestamp, _ in
        let key = device.map { UInt(bitPattern: $0) } ?? 0
        let (handler, index) = MultitouchSource.state.withLock { s in
            (s.handler, s.deviceIndex[key] ?? -1)
        }
        guard let handler else { return 0 }
        var out: [Touch] = []
        out.reserveCapacity(Int(count))
        if let touches {
            for i in 0..<Int(count) {
                let t = touches[i]
                out.append(Touch(
                    id: t.pathIndex,
                    state: TouchState(rawValue: t.state) ?? .notTracking,
                    x: t.normalized.position.x, y: t.normalized.position.y,
                    vx: t.normalized.velocity.x, vy: t.normalized.velocity.y,
                    size: t.zTotal))
            }
        }
        handler(TouchFrame(device: index, timestamp: timestamp, touches: out))
        return 0
    }
}
