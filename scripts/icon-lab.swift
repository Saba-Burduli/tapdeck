// Icon lab: ten TapDeck icon directions in a white + yellow palette.
//
//   swift scripts/icon-lab.swift <out-dir>
//
// Writes <out-dir>/<n>-<name>.png (1024 px) for each design plus
// <out-dir>/contact-sheet.png comparing them side by side.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let white = rgb(0xFFFFFF), cream = rgb(0xFBF8F1), mist = rgb(0xF2F1EE)
let lemon = rgb(0xFFE45C), yellow = rgb(0xFFD60A), gold = rgb(0xFFC300), amber = rgb(0xFFA800), tangerine = rgb(0xFF8A00)
let graphite = rgb(0x1C1C1E), ink = rgb(0x0B0B0D)

// MARK: - Drawing helpers (1024 grid, top-left origin)

func grad(_ c: [CGColor], _ l: [CGFloat]? = nil) -> CGGradient {
    let locs = l ?? c.indices.map { CGFloat($0) / CGFloat(max(c.count - 1, 1)) }
    return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: c as CFArray, locations: locs)!
}
func rr(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }
func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r) }

let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = rr(bodyRect, 185)

extension CGContext {
    func fill(_ path: CGPath, _ g: CGGradient, from: CGPoint, to: CGPoint) {
        saveGState(); addPath(path); clip()
        drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }
    func fillEllipse(_ rect: CGRect, _ g: CGGradient) {
        fill(CGPath(ellipseIn: rect, transform: nil), g, from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY))
    }
    func glow(_ c: CGPoint, inner: CGFloat, outer: CGFloat, _ color: CGColor, _ alpha: CGFloat) {
        drawRadialGradient(grad([color.copy(alpha: alpha)!, color.copy(alpha: 0)!]),
                           startCenter: c, startRadius: inner, endCenter: c, endRadius: outer, options: [])
    }
    func stroke(_ path: CGPath, _ color: CGColor, _ width: CGFloat) {
        addPath(path); setStrokeColor(color); setLineWidth(width); setLineCap(.round); strokePath()
    }
    func strokeGradient(_ path: CGPath, width: CGFloat, _ g: CGGradient, from: CGPoint, to: CGPoint) {
        saveGState(); addPath(path); setLineWidth(width); setLineCap(.round); replacePathWithStrokedPath(); clip()
        drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }
    func shadowed(_ offsetY: CGFloat, blur: CGFloat, _ color: CGColor, _ body: () -> Void) {
        saveGState(); setShadow(offset: CGSize(width: 0, height: offsetY), blur: blur, color: color); body(); restoreGState()
    }
    /// The squircle with drop shadow and a background gradient; then clips to it for `inside`.
    func body(_ g: CGGradient, rim: CGColor = rgb(0x000000, 0.06), inside: () -> Void) {
        shadowed(10, blur: 28, rgb(0x000000, 0.22)) { addPath(bodyPath); setFillColor(white); fillPath() }
        saveGState(); addPath(bodyPath); clip()
        drawLinearGradient(g, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
        inside()
        restoreGState()
        stroke(bodyPath, rim, 2)
    }
    /// A warm "light point" finger tap.
    func tapDot(_ c: CGPoint, _ r: CGFloat, halo: CGFloat = 0.4, core: Bool = true, colors: [CGColor] = [lemon, gold, amber]) {
        glow(c, inner: r * 0.7, outer: r * 1.8, gold, halo)
        let rect = circle(c, r)
        fillEllipse(rect, grad(colors))
        if core { saveGState(); addEllipse(in: rect); clip(); glow(c, inner: 0, outer: r * 0.6, rgb(0xFFFBE6), 0.9); restoreGState() }
        stroke(CGPath(ellipseIn: rect.insetBy(dx: 1.5, dy: 1.5), transform: nil), rgb(0xFFFFFF, 0.7), 3)
    }
}

// MARK: - The ten designs

typealias Design = (name: String, blurb: String, draw: (CGContext) -> Void)

let designs: [Design] = [
    ("Glow Pad", "Current direction, yellower: glowing trackpad rim, HUD pulse, three light points", { ctx in
        ctx.body(grad([white, mist])) { ctx.glow(CGPoint(x: 512, y: 280), inner: 0, outer: 520, lemon, 0.28) }
        let pad = CGRect(x: 222, y: 300, width: 580, height: 424), p = rr(pad, 64)
        ctx.shadowed(18, blur: 40, rgb(0xFFB800, 0.2)) { ctx.addPath(p); ctx.setFillColor(white); ctx.fillPath() }
        ctx.fill(p, grad([white, rgb(0xF3F2EF)]), from: CGPoint(x: 512, y: 300), to: CGPoint(x: 512, y: 724))
        ctx.strokeGradient(p, width: 4, grad([lemon, gold, amber]), from: CGPoint(x: 222, y: 300), to: CGPoint(x: 802, y: 724))
        ctx.saveGState(); ctx.addPath(p); ctx.clip()
        ctx.stroke(CGPath(ellipseIn: circle(CGPoint(x: 512, y: 506), 172), transform: nil), rgb(0xFFC300, 0.45), 3)
        for (s, e) in [(200.0, 340.0), (20.0, 160.0)] {
            let a = CGMutablePath(); a.addArc(center: CGPoint(x: 512, y: 506), radius: 232, startAngle: s * .pi / 180, endAngle: e * .pi / 180, clockwise: false)
            ctx.stroke(a, rgb(0xFFC300, 0.28), 2.5)
        }
        ctx.restoreGState()
        for c in [CGPoint(x: 400, y: 520), CGPoint(x: 512, y: 490), CGPoint(x: 624, y: 520)] { ctx.tapDot(c, 40) }
    }),

    ("Solo", "Ultra minimal: one big glowing tap and a single ring", { ctx in
        ctx.body(grad([white, cream])) {}
        let c = CGPoint(x: 512, y: 512)
        ctx.stroke(CGPath(ellipseIn: circle(c, 250), transform: nil), rgb(0xFFC300, 0.30), 6)
        ctx.stroke(CGPath(ellipseIn: circle(c, 320), transform: nil), rgb(0xFFC300, 0.12), 4)
        ctx.tapDot(c, 150, halo: 0.5)
    }),

    ("Trio", "Three bold flat dots in a triangle: three fingers, no trackpad", { ctx in
        ctx.body(grad([white, mist])) {}
        let dots: [(CGPoint, [CGColor])] = [(CGPoint(x: 512, y: 372), [lemon, yellow]), (CGPoint(x: 382, y: 600), [yellow, gold]), (CGPoint(x: 642, y: 600), [gold, amber])]
        for (c, cols) in dots {
            ctx.shadowed(14, blur: 26, rgb(0xFFA800, 0.35)) { ctx.addEllipse(in: circle(c, 104)); ctx.setFillColor(gold); ctx.fillPath() }
            ctx.fillEllipse(circle(c, 104), grad(cols))
            ctx.stroke(CGPath(ellipseIn: circle(c, 70), transform: nil), rgb(0xFFFFFF, 0.55), 5)
        }
    }),

    ("Ripple", "A single tap sending waves across the icon", { ctx in
        ctx.body(grad([white, cream])) {
            let c = CGPoint(x: 360, y: 660)
            for (i, r) in [150.0, 240.0, 330.0, 420.0, 510.0].enumerated() {
                let a = CGFloat(0.85 - Double(i) * 0.15)
                ctx.strokeGradient(CGPath(ellipseIn: circle(c, r), transform: nil), width: CGFloat(26 - i * 4),
                                   grad([lemon.copy(alpha: a)!, amber.copy(alpha: a)!]), from: CGPoint(x: 100, y: 924), to: CGPoint(x: 924, y: 100))
            }
            ctx.tapDot(c, 62, halo: 0.5)
        }
    }),

    ("Deck", "A play on the name: a fanned deck of cards, top card lit with three taps", { ctx in
        ctx.body(grad([white, mist])) {}
        let card = CGRect(x: 312, y: 262, width: 400, height: 500)
        for (angle, fill, shadow) in [(-20.0, rgb(0xFFE7A3), 0.14), (-8.0, rgb(0xFFF3CC), 0.16)] {
            ctx.saveGState(); ctx.translateBy(x: 512, y: 512); ctx.rotate(by: angle * .pi / 180); ctx.translateBy(x: -512, y: -512)
            ctx.shadowed(10, blur: 24, rgb(0x000000, shadow)) { ctx.addPath(rr(card, 56)); ctx.setFillColor(fill); ctx.fillPath() }
            ctx.restoreGState()
        }
        ctx.saveGState(); ctx.translateBy(x: 512, y: 512); ctx.rotate(by: 4 * .pi / 180); ctx.translateBy(x: -512, y: -512)
        ctx.shadowed(14, blur: 30, rgb(0xFFA800, 0.28)) { ctx.addPath(rr(card, 56)); ctx.setFillColor(white); ctx.fillPath() }
        ctx.strokeGradient(rr(card, 56), width: 5, grad([lemon, gold, amber]), from: CGPoint(x: 312, y: 262), to: CGPoint(x: 712, y: 762))
        for c in [CGPoint(x: 420, y: 530), CGPoint(x: 512, y: 500), CGPoint(x: 604, y: 530)] { ctx.tapDot(c, 34) }
        ctx.restoreGState()
    }),

    ("Keypad", "The trackpad as a grid of shortcut keys, one key lit", { ctx in
        ctx.body(grad([white, mist])) {}
        let pad = CGRect(x: 200, y: 290, width: 624, height: 444)
        ctx.shadowed(14, blur: 30, rgb(0x000000, 0.12)) { ctx.addPath(rr(pad, 60)); ctx.setFillColor(rgb(0xF4F3F0)); ctx.fillPath() }
        let w: CGFloat = 176, h: CGFloat = 186, gap: CGFloat = 18
        for row in 0..<2 {
            for col in 0..<3 {
                let k = CGRect(x: pad.minX + 26 + CGFloat(col) * (w + gap), y: pad.minY + 26 + CGFloat(row) * (h + gap), width: w, height: h)
                if row == 0 && col == 1 {
                    ctx.shadowed(0, blur: 36, rgb(0xFFB800, 0.6)) { ctx.addPath(rr(k, 34)); ctx.setFillColor(gold); ctx.fillPath() }
                    ctx.fill(rr(k, 34), grad([lemon, gold, amber]), from: CGPoint(x: k.minX, y: k.minY), to: CGPoint(x: k.maxX, y: k.maxY))
                    ctx.addEllipse(in: circle(CGPoint(x: k.midX, y: k.midY), 26)); ctx.setFillColor(rgb(0xFFFFFF, 0.92)); ctx.fillPath()
                } else {
                    ctx.shadowed(3, blur: 6, rgb(0x000000, 0.08)) { ctx.addPath(rr(k, 34)); ctx.setFillColor(white); ctx.fillPath() }
                }
            }
        }
    }),

    ("Noir", "Controversial: a dark graphite icon with neon-yellow light", { ctx in
        ctx.body(grad([rgb(0x2C2C2F), ink]), rim: rgb(0xFFFFFF, 0.08)) {
            ctx.glow(CGPoint(x: 512, y: 520), inner: 0, outer: 460, gold, 0.18)
        }
        let pad = CGRect(x: 222, y: 300, width: 580, height: 424), p = rr(pad, 64)
        ctx.addPath(p); ctx.setFillColor(rgb(0xFFFFFF, 0.04)); ctx.fillPath()
        ctx.shadowed(0, blur: 26, rgb(0xFFD60A, 0.9)) { ctx.stroke(p, rgb(0xFFD60A, 0.9), 4) }
        for c in [CGPoint(x: 400, y: 520), CGPoint(x: 512, y: 490), CGPoint(x: 624, y: 520)] {
            ctx.glow(c, inner: 20, outer: 110, yellow, 0.55)
            ctx.addEllipse(in: circle(c, 36)); ctx.setFillColor(rgb(0xFFF3B0)); ctx.fillPath()
            ctx.stroke(CGPath(ellipseIn: circle(c, 36), transform: nil), yellow, 5)
        }
    }),

    ("Sunrise", "Inverted: a sunny yellow icon with a white trackpad", { ctx in
        ctx.body(grad([lemon, gold, amber]), rim: rgb(0xFF9500, 0.25)) {
            ctx.glow(CGPoint(x: 512, y: 180), inner: 0, outer: 600, rgb(0xFFFBE0), 0.75)
        }
        let pad = CGRect(x: 222, y: 312, width: 580, height: 424), p = rr(pad, 64)
        ctx.shadowed(18, blur: 36, rgb(0xB36B00, 0.35)) { ctx.addPath(p); ctx.setFillColor(white); ctx.fillPath() }
        ctx.fill(p, grad([white, rgb(0xFFF8E6)]), from: CGPoint(x: 512, y: 312), to: CGPoint(x: 512, y: 736))
        for c in [CGPoint(x: 400, y: 530), CGPoint(x: 512, y: 500), CGPoint(x: 624, y: 530)] { ctx.tapDot(c, 40, halo: 0.25) }
    }),

    ("Monogram", "A geometric T whose stem ends in a glowing tap", { ctx in
        ctx.body(grad([white, cream])) {}
        let g = grad([lemon, gold, amber])
        ctx.shadowed(12, blur: 26, rgb(0xFFA800, 0.35)) {
            ctx.addPath(rr(CGRect(x: 282, y: 268, width: 460, height: 120), 60)); ctx.setFillColor(gold); ctx.fillPath()
        }
        ctx.fill(rr(CGRect(x: 282, y: 268, width: 460, height: 120), 60), g, from: CGPoint(x: 282, y: 268), to: CGPoint(x: 742, y: 388))
        ctx.fill(rr(CGRect(x: 452, y: 300, width: 120, height: 330), 60), g, from: CGPoint(x: 452, y: 300), to: CGPoint(x: 572, y: 630))
        let tip = CGPoint(x: 512, y: 718)
        for (r, a) in [(120.0, 0.25), (170.0, 0.12)] { ctx.stroke(CGPath(ellipseIn: circle(tip, r), transform: nil), rgb(0xFFC300, a), 5) }
        ctx.tapDot(tip, 64)
    }),

    ("Isometric", "A 3D trackpad slab seen from above, three taps on its surface", { ctx in
        ctx.body(grad([white, mist])) { ctx.glow(CGPoint(x: 512, y: 560), inner: 0, outer: 420, lemon, 0.22) }
        // Isometric transform: rotate 45°, squash vertically.
        func iso(_ ctx: CGContext, dy: CGFloat, _ draw: () -> Void) {
            ctx.saveGState(); ctx.translateBy(x: 512, y: 500 + dy); ctx.scaleBy(x: 1, y: 0.58); ctx.rotate(by: .pi / 4); ctx.translateBy(x: -512, y: -512)
            draw(); ctx.restoreGState()
        }
        let pad = CGRect(x: 292, y: 292, width: 440, height: 440), p = rr(pad, 70)
        for i in stride(from: 46, through: 1, by: -3) {   // slab thickness
            iso(ctx, dy: CGFloat(i)) { ctx.addPath(p); ctx.setFillColor(i > 40 ? rgb(0xE0B000, 0.25) : rgb(0xF0C63A)); ctx.fillPath() }
        }
        iso(ctx, dy: 0) {
            ctx.fill(p, grad([white, rgb(0xF6F4EF)]), from: CGPoint(x: 292, y: 292), to: CGPoint(x: 732, y: 732))
            ctx.stroke(p, rgb(0xFFFFFF, 0.9), 4)
            for c in [CGPoint(x: 420, y: 590), CGPoint(x: 512, y: 512), CGPoint(x: 604, y: 434)] { ctx.tapDot(c, 60, halo: 0.45) }
        }
    }),
]

// MARK: - Output

func render(_ d: Design, size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    ctx.translateBy(x: 0, y: 1024); ctx.scaleBy(x: 1, y: -1)
    d.draw(ctx)
    return ctx.makeImage()!
}

func write(_ img: CGImage, _ path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write failed: \(path)") }
}

func text(_ ctx: CGContext, _ s: String, at p: CGPoint, size: CGFloat, weight: CGFloat, color: CGColor, width: CGFloat) {
    let font = CTFontCreateWithName(weight > 0.3 ? "SFProDisplay-Semibold" as CFString : "SFProText-Regular" as CFString, size, nil)
    let attrs: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): color]
    let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs)),
                                         CFRange(), CGPath(rect: CGRect(x: p.x, y: p.y, width: width, height: size * 3.2), transform: nil), nil)
    CTFrameDraw(frame, ctx)
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-options"
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

let cols = 5, cell: CGFloat = 420, iconSize: CGFloat = 300, labelH: CGFloat = 120
let rows = (designs.count + cols - 1) / cols
let sheetW = Int(CGFloat(cols) * cell), sheetH = Int(CGFloat(rows) * (cell + labelH - 60) + 120)
let sheet = CGContext(data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sheet.setFillColor(rgb(0xF5F5F7)); sheet.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
text(sheet, "TapDeck icon options", at: CGPoint(x: 40, y: CGFloat(sheetH) - 120), size: 34, weight: 0.5, color: graphite, width: 900)

for (i, d) in designs.enumerated() {
    let img = render(d, size: 1024)
    let slug = d.name.lowercased().replacingOccurrences(of: " ", with: "-")
    write(img, "\(out)/\(String(format: "%02d", i + 1))-\(slug).png")

    // Contact sheet uses bottom-left origin; row 0 at the top.
    let col = i % cols, row = i / cols
    let x = CGFloat(col) * cell + (cell - iconSize) / 2
    let top = CGFloat(sheetH) - 120 - CGFloat(row) * (cell + labelH - 60)
    sheet.draw(img, in: CGRect(x: x, y: top - iconSize, width: iconSize, height: iconSize))
    text(sheet, "\(i + 1). \(d.name)", at: CGPoint(x: CGFloat(col) * cell + 30, y: top - iconSize - 54), size: 22, weight: 0.5, color: graphite, width: cell - 60)
    text(sheet, d.blurb, at: CGPoint(x: CGFloat(col) * cell + 30, y: top - iconSize - 84), size: 15, weight: 0, color: rgb(0x6E6E73), width: cell - 60)
}
write(sheet.makeImage()!, "\(out)/contact-sheet.png")
print("Wrote \(designs.count) designs and contact-sheet.png to \(out)")
