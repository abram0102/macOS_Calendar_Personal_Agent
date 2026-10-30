import AppKit
import CoreGraphics
import Foundation

// Draws the app icon from scratch with Core Graphics, so the artwork is text
// and can be regenerated at any size.
//
//   swiftc -O Tools/MakeIcon.swift -o /tmp/makeicon && /tmp/makeicon <outdir> [concept]
//
// Concepts: graphite (default), violet, paper

// MARK: - Palette

struct Concept {
    let name: String
    let bodyTop: CGColor
    let bodyBottom: CGColor
    let glyph: CGColor
    let accentTop: CGColor
    let accentBottom: CGColor
    /// A hairline along the top edge that makes the body read as glass
    let sheen: CGFloat
}

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

let concepts: [String: Concept] = [
    // Dark graphite body, white mark, warm coral check
    "graphite": Concept(name: "graphite",
                        bodyTop: rgb(60, 64, 74),
                        bodyBottom: rgb(22, 24, 29),
                        glyph: rgb(255, 255, 255, 0.94),
                        accentTop: rgb(255, 149, 110),
                        accentBottom: rgb(255, 94, 87),
                        sheen: 0.14),
    // Saturated indigo to violet, everything in white
    "violet": Concept(name: "violet",
                      bodyTop: rgb(124, 104, 255),
                      bodyBottom: rgb(58, 42, 190),
                      glyph: rgb(255, 255, 255, 0.96),
                      accentTop: rgb(255, 255, 255),
                      accentBottom: rgb(226, 222, 255),
                      sheen: 0.22),
    // Warm paper, graphite mark, coral check
    "paper": Concept(name: "paper",
                     bodyTop: rgb(250, 249, 246),
                     bodyBottom: rgb(228, 226, 220),
                     glyph: rgb(38, 40, 46, 0.92),
                     accentTop: rgb(255, 126, 95),
                     accentBottom: rgb(240, 78, 86),
                     sheen: 0.0),
]

// MARK: - Drawing

func gradient(_ top: CGColor, _ bottom: CGColor) -> CGGradient? {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
               colors: [top, bottom] as CFArray,
               locations: [0, 1])
}

/// Apple's macOS icon grid: a 1024 canvas with an 824 body, nudged up to leave
/// room for the shadow underneath.
func bodyRect(in size: CGFloat) -> CGRect {
    let side = size * 0.8047
    return CGRect(x: (size - side) / 2, y: (size - side) / 2 + size * 0.0137,
                  width: side, height: side)
}

func squirclePath(_ r: CGRect) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: r.width * 0.2237, cornerHeight: r.width * 0.2237,
           transform: nil)
}

func draw(_ c: Concept, size: CGFloat, into ctx: CGContext) {
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let body = bodyRect(in: size)
    let path = squirclePath(body)

    // Soft shadow under the body
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                  blur: size * 0.035,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.30))
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()

    // Body gradient
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    if let g = gradient(c.bodyTop, c.bodyBottom) {
        ctx.drawLinearGradient(g,
                               start: CGPoint(x: body.midX, y: body.maxY),
                               end: CGPoint(x: body.midX, y: body.minY),
                               options: [])
    }
    // Hairline sheen along the top edge
    if c.sheen > 0 {
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: c.sheen))
        ctx.setLineWidth(size * 0.006)
        ctx.addPath(squirclePath(body.insetBy(dx: size * 0.003, dy: size * 0.003)))
        ctx.strokePath()
    }
    ctx.restoreGState()

    drawGlyph(c, body: body, size: size, into: ctx)
}

/// A calendar page with a check inside it: the two things the app is for.
func drawGlyph(_ c: Concept, body: CGRect, size: CGFloat, into ctx: CGContext) {
    let w = body.width
    let stroke = w * 0.058

    // The page
    let page = CGRect(x: body.minX + w * 0.215,
                      y: body.minY + w * 0.185,
                      width: w * 0.570,
                      height: w * 0.545)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(stroke)
    ctx.setStrokeColor(c.glyph)
    ctx.addPath(CGPath(roundedRect: page.insetBy(dx: stroke / 2, dy: stroke / 2),
                       cornerWidth: page.width * 0.165, cornerHeight: page.width * 0.165,
                       transform: nil))
    ctx.strokePath()

    // Header rule
    let headerY = page.maxY - page.height * 0.255
    ctx.move(to: CGPoint(x: page.minX + stroke / 2, y: headerY))
    ctx.addLine(to: CGPoint(x: page.maxX - stroke / 2, y: headerY))
    ctx.strokePath()

    // Two binder rings poking out of the top
    let ringLen = w * 0.085
    for fraction in [0.30, 0.70] as [CGFloat] {
        let x = page.minX + page.width * fraction
        ctx.move(to: CGPoint(x: x, y: page.maxY - stroke * 0.1))
        ctx.addLine(to: CGPoint(x: x, y: page.maxY + ringLen))
    }
    ctx.strokePath()

    // The check, in the accent, filling the page below the header
    let inner = CGRect(x: page.minX, y: page.minY,
                       width: page.width, height: headerY - page.minY)
    let checkPath = CGMutablePath()
    checkPath.move(to: CGPoint(x: inner.minX + inner.width * 0.185,
                               y: inner.minY + inner.height * 0.520))
    checkPath.addLine(to: CGPoint(x: inner.minX + inner.width * 0.420,
                                  y: inner.minY + inner.height * 0.275))
    checkPath.addLine(to: CGPoint(x: inner.minX + inner.width * 0.840,
                                  y: inner.minY + inner.height * 0.760))

    ctx.saveGState()
    ctx.setLineWidth(stroke * 1.12)
    ctx.addPath(checkPath)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    if let g = gradient(c.accentTop, c.accentBottom) {
        ctx.drawLinearGradient(g,
                               start: CGPoint(x: inner.minX, y: inner.maxY),
                               end: CGPoint(x: inner.maxX, y: inner.minY),
                               options: [])
    }
    ctx.restoreGState()
}

// MARK: - Output

func render(_ c: Concept, size: Int) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
    else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    draw(c, size: CGFloat(size), into: ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MakeIcon", code: 1)
    }
    try data.write(to: url)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: makeicon <outdir> [concept]\n".data(using: .utf8)!)
    exit(2)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let wanted: [Concept] = args.count >= 3
    ? [concepts[args[2]]].compactMap { $0 }
    : ["graphite", "violet", "paper"].compactMap { concepts[$0] }
guard !wanted.isEmpty else {
    FileHandle.standardError.write("unknown concept\n".data(using: .utf8)!)
    exit(2)
}

// 1024 for review, plus every size an .iconset needs
let sizes = args.count >= 3 ? [16, 32, 64, 128, 256, 512, 1024] : [256, 1024]
for c in wanted {
    for s in sizes {
        guard let rep = render(c, size: s) else { continue }
        try write(rep, to: outDir.appendingPathComponent("\(c.name)-\(s).png"))
    }
    print("drew \(c.name)")
}
