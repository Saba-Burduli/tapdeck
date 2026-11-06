import SwiftUI
import TouchInput

/// Yellow and white liquid thrown off by the fingers on the trackpad.
///
/// Particles are emitted where fingers are, carry the finger's speed, slow down, drip a little and shrink.
/// Drawn blurred and alpha-thresholded, neighbouring particles melt into one liquid surface.
/// Positions are in points, origin top-left. Plain reference type: stepping it never invalidates SwiftUI views.
final class FluidSim {
    struct Particle {
        var position: CGPoint
        var velocity: CGVector
        var radius: CGFloat
        var age: Double = 0
        var life: Double
    }

    struct Ripple {
        var center: CGPoint
        var age: Double = 0
    }

    static let maxParticles = 260
    static let rippleLife = 0.7

    private(set) var particles: [Particle] = []
    private(set) var ripples: [Ripple] = []
    private var fingers: [Int32: CGPoint] = [:]
    private var lastTime: Double?
    private var rng = SystemRandomNumberGenerator()

    var isEmpty: Bool { particles.isEmpty && ripples.isEmpty }

    /// Advances to `time` and emits from `touches` (normalized trackpad coordinates, origin bottom-left).
    func step(to time: Double, touches: [Touch], in size: CGSize, emits: Bool) {
        let dt = min(max(time - (lastTime ?? time), 0), 1.0 / 20)
        lastTime = time
        let scale = min(size.width, size.height)

        var seen = Set<Int32>()
        for touch in touches {
            seen.insert(touch.id)
            let point = CGPoint(x: CGFloat(touch.x) * size.width, y: (1 - CGFloat(touch.y)) * size.height)
            guard emits else { fingers[touch.id] = point; continue }
            if let previous = fingers[touch.id], dt > 0 {
                let velocity = CGVector(dx: (point.x - previous.x) / dt, dy: (point.y - previous.y) / dt)
                let speed = hypot(velocity.dx, velocity.dy) / scale
                // Faster strokes throw more, bigger, longer-flying drops.
                let count = 1 + min(3, Int(speed * 3))
                for i in 0..<count {
                    let t = CGFloat(i) / CGFloat(count)
                    let origin = CGPoint(x: previous.x + (point.x - previous.x) * t, y: previous.y + (point.y - previous.y) * t)
                    emit(at: origin, velocity: CGVector(dx: velocity.dx * 0.55, dy: velocity.dy * 0.55),
                         spread: 40 + speed * 60, radius: scale * .random(in: 0.022...0.04, using: &rng) * (1 + min(speed, 1.5) * 0.3))
                }
            } else {
                splash(at: point, scale: scale)
            }
            fingers[touch.id] = point
        }
        for (id, point) in fingers where !seen.contains(id) {
            if emits { ripples.append(Ripple(center: point)) }
            fingers[id] = nil
        }

        let drag = CGFloat(pow(0.92, dt * 60))
        let gravity = scale * 0.25 * CGFloat(dt)
        for i in particles.indices {
            particles[i].velocity.dx *= drag
            particles[i].velocity.dy = particles[i].velocity.dy * drag + gravity
            particles[i].position.x += particles[i].velocity.dx * CGFloat(dt)
            particles[i].position.y += particles[i].velocity.dy * CGFloat(dt)
            particles[i].age += dt
        }
        particles.removeAll { $0.age >= $0.life }
        for i in ripples.indices { ripples[i].age += dt }
        ripples.removeAll { $0.age >= Self.rippleLife }
    }

    /// A ring of droplets, for a finger landing or a gesture firing.
    func splash(at point: CGPoint, scale: CGFloat, strength: CGFloat = 1) {
        let count = Int(12 * strength)
        for i in 0..<count {
            let angle = CGFloat(i) / CGFloat(count) * 2 * .pi + .random(in: -0.3...0.3, using: &rng)
            let speed = scale * .random(in: 0.35...0.9, using: &rng) * strength
            emit(at: point, velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                 spread: 0, radius: scale * .random(in: 0.015...0.03, using: &rng))
        }
        emit(at: point, velocity: .zero, spread: 0, radius: scale * 0.06 * strength)
    }

    /// The last known position of any finger, for splashes when a gesture fires.
    var lastFingerPosition: CGPoint? { fingers.values.first }

    private func emit(at point: CGPoint, velocity: CGVector, spread: CGFloat, radius: CGFloat) {
        let jitter = CGVector(dx: .random(in: -spread...spread, using: &rng), dy: .random(in: -spread...spread, using: &rng))
        particles.append(Particle(position: point,
                                  velocity: CGVector(dx: velocity.dx + jitter.dx, dy: velocity.dy + jitter.dy),
                                  radius: radius, life: .random(in: 0.9...1.4, using: &rng)))
        if particles.count > Self.maxParticles { particles.removeFirst(particles.count - Self.maxParticles) }
    }
}

/// The liquid layer behind the Settings window. Animates while fingers are down and for a moment after.
struct FluidLayer: View {
    var touches: [Touch]
    /// Changes each time a gesture fires, for a celebratory splash.
    var fired: Date?

    @State private var sim = FluidSim()
    @State private var running = false
    @State private var settleTask: Task<Void, Never>?
    @State private var pendingSplash = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !running)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                sim.step(to: time, touches: touches, in: size, emits: !reduceMotion)
                if pendingSplash, let point = sim.lastFingerPosition {
                    sim.splash(at: point, scale: min(size.width, size.height), strength: 1.6)
                }
                drawAmbient(&ctx, size: size, time: time)
                drawLiquid(&ctx, color: Theme.honey, radiusScale: 1, offset: .zero)
                drawLiquid(&ctx, color: Theme.butter, radiusScale: 0.78, offset: CGSize(width: -1.5, height: -2))
                drawLiquid(&ctx, color: Theme.warmWhite, radiusScale: 0.32, offset: CGSize(width: -4, height: -5), blur: 6)
                drawRipples(&ctx)
                drawFingers(&ctx, size: size)
            }
        }
        // Rasterize on the GPU; blurring on the CPU costs several times more.
        .drawingGroup()
        .allowsHitTesting(false)
        .onChange(of: touches.isEmpty, initial: true) { _, empty in
            settleTask?.cancel()
            if !empty {
                running = true
            } else {
                // Keep animating until the last drops fade, then stop redrawing.
                settleTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.5))
                    if !Task.isCancelled { running = false }
                }
            }
        }
        .onChange(of: fired) { _, _ in
            guard !reduceMotion else { return }
            pendingSplash = true
            running = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                pendingSplash = false
                if touches.isEmpty {
                    try? await Task.sleep(for: .seconds(2))
                    if touches.isEmpty { running = false }
                }
            }
        }
    }

    /// Soft butter clouds that drift slowly, so the window has colour even before you touch the pad.
    private func drawAmbient(_ ctx: inout GraphicsContext, size: CGSize, time: Double) {
        let blobs: [(CGFloat, CGFloat, CGFloat, Color)] = [
            (0.12, 0.18, 0.55, Theme.butter), (0.88, 0.12, 0.45, Theme.honey),
            (0.8, 0.9, 0.6, Theme.butter), (0.2, 0.85, 0.4, Theme.cream),
        ]
        let scale = max(size.width, size.height)
        for (i, (x, y, r, color)) in blobs.enumerated() {
            let drift = reduceMotion ? 0 : CGFloat(sin(time * 0.15 + Double(i) * 1.7)) * 0.04
            let center = CGPoint(x: (x + drift) * size.width, y: (y - drift) * size.height)
            let radius = r * scale * 0.5
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            ctx.fill(Path(ellipseIn: rect),
                     with: .radialGradient(Gradient(colors: [color.opacity(0.32), color.opacity(0)]),
                                           center: center, startRadius: 0, endRadius: radius))
        }
    }

    private func drawLiquid(_ ctx: inout GraphicsContext, color: Color, radiusScale: CGFloat, offset: CGSize, blur: CGFloat = 12) {
        guard !sim.particles.isEmpty else { return }
        // Blur cost grows with area, so filter only the region the drops cover.
        var bounds = CGRect.null
        for p in sim.particles {
            bounds = bounds.union(CGRect(x: p.position.x - p.radius, y: p.position.y - p.radius, width: p.radius * 2, height: p.radius * 2))
        }
        ctx.drawLayer { layer in
            layer.clip(to: Path(bounds.insetBy(dx: -blur * 3, dy: -blur * 3)))
            layer.addFilter(.alphaThreshold(min: 0.5, color: color))
            layer.addFilter(.blur(radius: blur))
            layer.drawLayer { drops in
                for p in sim.particles {
                    let fade = CGFloat(pow(max(0, 1 - p.age / p.life), 0.6))
                    let r = p.radius * radiusScale * fade
                    guard r > 0.5 else { continue }
                    let c = CGPoint(x: p.position.x + offset.width, y: p.position.y + offset.height)
                    drops.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.black))
                }
            }
        }
    }

    private func drawRipples(_ ctx: inout GraphicsContext) {
        for ripple in sim.ripples {
            let t = ripple.age / FluidSim.rippleLife
            let r = 12 + 70 * CGFloat(t)
            let rect = CGRect(x: ripple.center.x - r, y: ripple.center.y - r, width: r * 2, height: r * 2)
            ctx.stroke(Path(ellipseIn: rect), with: .color(Theme.honey.opacity(0.55 * (1 - t))), lineWidth: 3 * (1 - t) + 0.5)
        }
    }

    /// A white core with a honey glow under each finger.
    private func drawFingers(_ ctx: inout GraphicsContext, size: CGSize) {
        for touch in touches {
            let c = CGPoint(x: CGFloat(touch.x) * size.width, y: (1 - CGFloat(touch.y)) * size.height)
            let glow: CGFloat = 46
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - glow, y: c.y - glow, width: glow * 2, height: glow * 2)),
                     with: .radialGradient(Gradient(colors: [Theme.honey.opacity(0.45), Theme.honey.opacity(0)]),
                                           center: c, startRadius: 0, endRadius: glow))
            let core: CGFloat = 9
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - core, y: c.y - core, width: core * 2, height: core * 2)), with: .color(.white))
        }
    }
}
