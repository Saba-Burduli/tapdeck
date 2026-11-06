import CoreGraphics

/// Pure window geometry, in Accessibility coordinates: origin at the top-left of
/// the primary screen, y grows downward. No OS calls, so it's unit-tested.
public enum WindowLayout {
    /// - Parameters:
    ///   - window: the window's current frame.
    ///   - screens: each screen's usable area (menu bar and Dock excluded), AX coordinates.
    /// - Returns: the new frame, or nil if there's nothing to do.
    public static func frame(for command: WindowCommand, window: CGRect, screens: [CGRect]) -> CGRect? {
        guard let index = screenIndex(for: window, in: screens) else { return nil }
        let s = screens[index]
        switch command {
        // Halves are built from rounded edges so the two halves tile the screen exactly.
        case .leftHalf: return edges(s.minX, s.midX, s.minY, s.maxY)
        case .rightHalf: return edges(s.midX, s.maxX, s.minY, s.maxY)
        case .topHalf: return edges(s.minX, s.maxX, s.minY, s.midY)
        case .bottomHalf: return edges(s.minX, s.maxX, s.midY, s.maxY)
        case .maximize: return s
        case .center:
            let w = min(window.width, s.width), h = min(window.height, s.height)
            // Round only the origin, so the window keeps its exact size.
            return CGRect(x: (s.midX - w / 2).rounded(), y: (s.midY - h / 2).rounded(), width: w, height: h)
        case .nextDisplay:
            guard screens.count > 1 else { return nil }
            let t = screens[(index + 1) % screens.count]
            // Keep the window's relative position and size on the new screen.
            let rx = (window.minX - s.minX) / s.width, ry = (window.minY - s.minY) / s.height
            let w = min(window.width / s.width * t.width, t.width)
            let h = min(window.height / s.height * t.height, t.height)
            return edges(t.minX + rx * t.width, t.minX + rx * t.width + w, t.minY + ry * t.height, t.minY + ry * t.height + h)
        }
    }

    /// The screen holding most of the window, or the nearest one if it's off-screen.
    static func screenIndex(for window: CGRect, in screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
        let overlaps = screens.map { area($0.intersection(window)) }
        if let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }), overlaps[best] > 0 { return best }
        let c = CGPoint(x: window.midX, y: window.midY)
        return screens.indices.min { hypot(screens[$0].midX - c.x, screens[$0].midY - c.y) < hypot(screens[$1].midX - c.x, screens[$1].midY - c.y) }
    }

    /// A rect from rounded edges. (`CGRect.integral` grows a rect to cover partial
    /// pixels, which would make a centered window 1 pt bigger or overflow the screen.)
    static func edges(_ x0: CGFloat, _ x1: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> CGRect {
        let l = x0.rounded(), r = x1.rounded(), t = y0.rounded(), b = y1.rounded()
        return CGRect(x: l, y: t, width: r - l, height: b - t)
    }

    /// Converts an AppKit screen rect (origin bottom-left of the primary screen) to AX coordinates.
    public static func axRect(fromAppKit r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}

