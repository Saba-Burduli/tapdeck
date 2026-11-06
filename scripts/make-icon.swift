// Draws the TapDeck app icon and writes PNGs.
//
//   swift scripts/make-icon.swift <out.png> [size]     one PNG (default 1024)
//   scripts/make-icon.sh                                full .icns + README image
//
// Design: Apple-style white squircle, a soft light trackpad, and three
// orange-to-yellow finger taps with a ripple: "three fingers, one tap".
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

    // 2. Trackpad slab.
    let pad = CGRect(x: 222, y: 300, width: 580, height: 424)
    let padPath = squircle(pad, 64)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: color(0x8A6A3A, 0.18))
    ctx.addPath(padPath); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(padPath); ctx.clip()
    ctx.drawLinearGradient(gradient([color(0xFDFDFC), color(0xEDECEA)], [0, 1]),
                           start: CGPoint(x: 512, y: pad.minY), end: CGPoint(x: 512, y: pad.maxY), options: [])
    ctx.restoreGState()
    ctx.addPath(padPath); ctx.setStrokeColor(color(0x000000, 0.07)); ctx.setLineWidth(3); ctx.strokePath()
    // Glass highlight along the top edge.
    ctx.addPath(squircle(pad.insetBy(dx: 6, dy: 6), 58))
    ctx.setStrokeColor(color(0xFFFFFF, 0.9)); ctx.setLineWidth(3); ctx.strokePath()

    // 3. Tap ripple: rings around the whole three-finger group, clipped to the pad.
    let center = CGPoint(x: 512, y: 504)
    ctx.saveGState()
    ctx.addPath(padPath); ctx.clip()
    for (radius, alpha, width) in [(178.0, 0.30, 5.0), (238.0, 0.17, 4.0), (300.0, 0.08, 3.0)] {
        ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        ctx.setStrokeColor(color(0xFF9A2E, alpha)); ctx.setLineWidth(width); ctx.strokePath()
    }
    ctx.restoreGState()

    // 4. Three finger taps: a gentle arc, the middle one slightly higher.
    let dots = [CGPoint(x: 400, y: 516), CGPoint(x: 512, y: 488), CGPoint(x: 624, y: 516)]
    let r: CGFloat = 44
    for d in dots {
        let rect = CGRect(x: d.x - r, y: d.y - r, width: r * 2, height: r * 2)
        ctx.saveGState()   // glow
        ctx.setShadow(offset: .zero, blur: 34, color: color(0xFF8A00, 0.55))
        ctx.addEllipse(in: rect); ctx.setFillColor(color(0xFFA62B)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()   // orange -> yellow fill
        ctx.addEllipse(in: rect); ctx.clip()
        ctx.drawLinearGradient(gradient([color(0xFFE15A), color(0xFFB02E), color(0xFF7A1A)], [0, 0.45, 1]),
                               start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
        // Specular highlight.
        ctx.drawRadialGradient(gradient([color(0xFFFFFF, 0.40), color(0xFFFFFF, 0)], [0, 1]),
                               startCenter: CGPoint(x: d.x - 14, y: d.y - 16), startRadius: 0,
                               endCenter: CGPoint(x: d.x - 14, y: d.y - 16), endRadius: 30, options: [])
        ctx.restoreGState()
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
