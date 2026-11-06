// Draws the TapDeck app icon and writes PNGs.
//
//   swift scripts/make-icon.swift <out.png> [size]     one PNG (default 1024)
//   scripts/make-icon.sh                                full .icns + README image
//
// Design: Apple-style white squircle; a frosted-glass trackpad with a thin
// glowing warm rim and a sensor-dot texture; three finger taps drawn as
// points of light inside a HUD-style pulse: "three fingers, one tap".
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

/// Rounded rect with continuous-looking corners (close to Apple's squircle).
func squircle(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Strokes `path` with a linear gradient, optionally with a soft glow of the middle color.
func strokeGradient(_ ctx: CGContext, _ path: CGPath, width: CGFloat, colors: [CGColor],
                    from: CGPoint, to: CGPoint, glow: CGFloat) {
    if glow > 0 {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 22, color: colors[colors.count / 2].copy(alpha: glow)!)
        ctx.addPath(path); ctx.setStrokeColor(colors[colors.count / 2].copy(alpha: 0.6)!); ctx.setLineWidth(width); ctx.strokePath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(path); ctx.setLineWidth(width); ctx.replacePathWithStrokedPath(); ctx.clip()
    let locations = colors.indices.map { CGFloat($0) / CGFloat(max(colors.count - 1, 1)) }
    ctx.drawLinearGradient(gradient(colors, locations), start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func drawIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Work in a 1024 grid, top-left origin.
    ctx.scaleBy(x: s / 1024, y: s / 1024)
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    // 1. Squircle body (macOS icon grid: 824 pt shape, 100 pt margin).
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = squircle(body, 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: color(0x000000, 0.22))
    ctx.addPath(bodyPath); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    ctx.drawLinearGradient(gradient([color(0xFFFFFF), color(0xF3F2F0)], [0, 1]),
                           start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    // Warm glow from the top so the white doesn't feel flat.
    ctx.drawRadialGradient(gradient([color(0xFFD27A, 0.28), color(0xFFD27A, 0)], [0, 1]),
                           startCenter: CGPoint(x: 512, y: 300), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 300), endRadius: 520, options: [])
    ctx.restoreGState()
    ctx.addPath(bodyPath); ctx.setStrokeColor(color(0x000000, 0.06)); ctx.setLineWidth(2); ctx.strokePath()

    // 2. Trackpad: frosted glass slab with a thin glowing warm rim.
    let pad = CGRect(x: 222, y: 300, width: 580, height: 424)
    let padPath = squircle(pad, 64)
    let warm = [color(0xFFD84D), color(0xFF9F1C), color(0xFF6A00)]
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: color(0xFF8A00, 0.18))
    ctx.addPath(padPath); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(padPath); ctx.clip()
    ctx.drawLinearGradient(gradient([color(0xFFFFFF), color(0xF1F0EE)], [0, 1]),
                           start: CGPoint(x: 512, y: pad.minY), end: CGPoint(x: 512, y: pad.maxY), options: [])
    // Fine dot grid: a quiet "sensor surface" texture.
    ctx.setFillColor(color(0x8A7A66, 0.10))
    var gy = pad.minY + 28
    while gy < pad.maxY - 16 {
        var gx = pad.minX + 30
        while gx < pad.maxX - 16 { ctx.fillEllipse(in: CGRect(x: gx - 2.2, y: gy - 2.2, width: 4.4, height: 4.4)); gx += 36 }
        gy += 36
    }
    ctx.restoreGState()
    strokeGradient(ctx, padPath, width: 4, colors: warm, from: CGPoint(x: pad.minX, y: pad.minY), to: CGPoint(x: pad.maxX, y: pad.maxY), glow: 0.45)
    // Inner glass highlight.
    ctx.addPath(squircle(pad.insetBy(dx: 7, dy: 7), 57))
    ctx.setStrokeColor(color(0xFFFFFF, 0.95)); ctx.setLineWidth(2.5); ctx.strokePath()

    // 3. HUD pulse: one thin full ring and two broken outer arcs, clipped to the pad.
    let center = CGPoint(x: 512, y: 506)
    ctx.saveGState()
    ctx.addPath(padPath); ctx.clip()
    let inner = CGMutablePath(); inner.addEllipse(in: CGRect(x: center.x - 172, y: center.y - 172, width: 344, height: 344))
    strokeGradient(ctx, inner, width: 3, colors: warm.map { $0.copy(alpha: 0.55)! }, from: CGPoint(x: 340, y: 334), to: CGPoint(x: 684, y: 678), glow: 0)
    for (start, end) in [(200.0, 340.0), (20.0, 160.0)] {   // degrees; gaps at left/right
        let arc = CGMutablePath()
        arc.addArc(center: center, radius: 232, startAngle: start * .pi / 180, endAngle: end * .pi / 180, clockwise: false)
        ctx.addPath(arc); ctx.setStrokeColor(color(0xFF9F1C, 0.28)); ctx.setLineWidth(2.5); ctx.setLineCap(.round); ctx.strokePath()
    }
    ctx.restoreGState()

    // 4. Three finger taps as points of light: flat warm discs, bright core, halo.
    let dots = [CGPoint(x: 400, y: 520), CGPoint(x: 512, y: 490), CGPoint(x: 624, y: 520)]
    let r: CGFloat = 40
    for d in dots {
        ctx.drawRadialGradient(gradient([color(0xFFB020, 0.42), color(0xFFB020, 0)], [0, 1]),   // halo
                               startCenter: d, startRadius: r * 0.7, endCenter: d, endRadius: r * 1.75, options: [])
        let rect = CGRect(x: d.x - r, y: d.y - r, width: r * 2, height: r * 2)
        ctx.saveGState()
        ctx.addEllipse(in: rect); ctx.clip()
        ctx.drawLinearGradient(gradient([color(0xFFE25C), color(0xFFA51F), color(0xFF7300)], [0, 0.5, 1]),
                               start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
        ctx.drawRadialGradient(gradient([color(0xFFFBE8, 0.95), color(0xFFF3C4, 0)], [0, 1]),   // hot core
                               startCenter: d, startRadius: 0, endCenter: d, endRadius: r * 0.55, options: [])
        ctx.restoreGState()
        ctx.addEllipse(in: rect.insetBy(dx: 1.5, dy: 1.5))
        ctx.setStrokeColor(color(0xFFFFFF, 0.75)); ctx.setLineWidth(3); ctx.strokePath()
    }

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(path)") }
}

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: make-icon.swift <out.png> [size]"); exit(2) }
writePNG(drawIcon(size: args.count > 2 ? Int(args[2])! : 1024), to: args[1])
