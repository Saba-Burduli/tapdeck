import AppKit
import ApplicationServices

public enum ActionError: Error, CustomStringConvertible, Equatable {
    case appNotFound(String)
    case needsAccessibility
    case noFocusedWindow
    case cannotMoveWindow
    case eventFailed

    public var description: String {
        switch self {
        case let .appNotFound(id): "No app with bundle ID \(id)"
        case .needsAccessibility: "TapDeck needs Accessibility permission for this action"
        case .noFocusedWindow: "No focused window"
        case .cannotMoveWindow: "That window can't be moved or resized"
        case .eventFailed: "Could not create the input event"
        }
    }
}

/// Performs actions. Main-actor only: AppKit and the AX API expect the main thread.
@MainActor
public final class ActionRunner {
    public init() {}

    public func run(_ action: Action) throws {
        switch action {
        case let .openApp(id, toggle): try openApp(bundleID: id, toggle: toggle)
        case let .keystroke(k): try press(k)
        case let .window(w): try moveWindow(w)
        case let .media(m): try pressMedia(m)
        }
    }

    // MARK: Apps (no permission needed)

    private func openApp(bundleID: String, toggle: Bool) throws {
        if toggle, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first, app.isActive {
            app.hide()
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw ActionError.appNotFound(bundleID)
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    // MARK: Keystrokes (Accessibility)

    private func press(_ k: KeyCombo) throws {
        guard Permissions.isAccessibilityTrusted else { throw ActionError.needsAccessibility }
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: k.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: k.keyCode, keyDown: false)
        else { throw ActionError.eventFailed }
        let flags = Self.flags(k.modifiers, keyCode: k.keyCode)
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Arrow keys carry these flags on real hardware; system shortcuts such as
    /// Mission Control (⌃↑) ignore synthetic arrow presses without them.
    nonisolated static let arrowKeys: Set<UInt16> = [123, 124, 125, 126]
    /// Keys a real keyboard reports with the Fn flag: arrows, F-keys, Home/End/PgUp/PgDn, forward delete.
    nonisolated static let fnKeys: Set<UInt16> = arrowKeys.union([122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
                                                      115, 119, 116, 121, 117])

    nonisolated static func flags(_ m: KeyCombo.Modifiers, keyCode: UInt16? = nil) -> CGEventFlags {
        var f: CGEventFlags = []
        if let keyCode {
            if arrowKeys.contains(keyCode) { f.insert(.maskNumericPad) }
            if fnKeys.contains(keyCode) { f.insert(.maskSecondaryFn) }
        }
        if m.contains(.command) { f.insert(.maskCommand) }
        if m.contains(.shift) { f.insert(.maskShift) }
        if m.contains(.option) { f.insert(.maskAlternate) }
        if m.contains(.control) { f.insert(.maskControl) }
        if m.contains(.function) { f.insert(.maskSecondaryFn) }
        return f
    }

    // MARK: Media keys (Accessibility)

    private func pressMedia(_ key: MediaKey) throws {
        guard Permissions.isAccessibilityTrusted else { throw ActionError.needsAccessibility }
        for down in [true, false] {
            guard let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: key.eventData(down: down), data2: -1
            )?.cgEvent else { throw ActionError.eventFailed }
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: Windows (Accessibility)

    private func moveWindow(_ command: WindowCommand) throws {
        guard Permissions.isAccessibilityTrusted else { throw ActionError.needsAccessibility }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { throw ActionError.noFocusedWindow }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { throw ActionError.noFocusedWindow }
        let window = value as! AXUIElement

        guard let current = frame(of: window) else { throw ActionError.cannotMoveWindow }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens.map { WindowLayout.axRect(fromAppKit: $0.visibleFrame, primaryHeight: primaryHeight) }
        guard let target = WindowLayout.frame(for: command, window: current, screens: screens) else { return }

        // Size, then position, then size again: some apps clamp size to the old screen.
        guard set(window, size: target.size), set(window, origin: target.origin) else { throw ActionError.cannotMoveWindow }
        _ = set(window, size: target.size)
    }

    private func frame(of w: AXUIElement) -> CGRect? {
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &size) == .success
        else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(pos as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    private func set(_ w: AXUIElement, origin: CGPoint) -> Bool {
        var p = origin
        guard let v = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v) == .success
    }

    private func set(_ w: AXUIElement, size: CGSize) -> Bool {
        var s = size
        guard let v = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, v) == .success
    }
}

/// Accessibility permission: required to send keystrokes, media keys, and move windows.
public enum Permissions {
    public static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system "allow Accessibility" prompt if not yet trusted. Returns current state.
    @discardableResult
    public static func requestAccessibility() -> Bool {
        let key = "AXTrustedCheckOptionPrompt"   // kAXTrustedCheckOptionPrompt (not concurrency-safe to read)
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Opens System Settings at Privacy & Security > Accessibility.
    @MainActor public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
