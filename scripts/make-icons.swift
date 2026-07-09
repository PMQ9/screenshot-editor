// Usage: swift scripts/make-icons.swift [previewDir]
//
// Generates the "Focus" app identity from code (no SVG rasterizer needed):
//   Resources/AppIcon.icns    — full-color Dock/app icon, all 10 iconset sizes
//   Resources/MenuBarIcon.pdf — monochrome vector template for the menu-bar status item
//
// The design: a light squircle, four graphite crop-viewfinder brackets, and a small
// red annotation arrow (dot at small sizes). Everything is drawn in a normalized
// 1024-unit design space so it stays crisp from 16px to 1024px.
//
// If `previewDir` is given, also writes preview PNGs there for visual inspection.
// Regenerate via `make icons`. The emitted assets are checked in so `make app` is fast.

import AppKit
import CoreGraphics
import Foundation

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
}

let graphite  = rgb(0.133, 0.145, 0.169)   // #22252B  brackets
let signalRed = rgb(0.929, 0.188, 0.141)   // #ED3024  the app's default annotation color
let edgeInk   = rgb(0, 0, 0, 0.07)
let shadowInk = rgb(0, 0, 0, 0.16)
let gradTop   = rgb(1, 1, 1)               // #FFFFFF
let gradBot   = rgb(0.906, 0.918, 0.941)   // #E7EAF0

// MARK: - App icon (drawn in a 1024-unit, y-down, top-left design space)

func drawAppIcon(_ ctx: CGContext, small: Bool) {
    let pad: CGFloat = small ? 44 : 100
    let sq = CGRect(x: pad, y: pad, width: 1024 - 2 * pad, height: 1024 - 2 * pad)
    let side = sq.width
    let radius = side * 0.2237
    let squircle = CGPath(roundedRect: sq, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Baked ambient shadow (full-size only; there's no room at small sizes).
    // The CTM is y-down (flipped), so a negative height casts the shadow downward on screen.
    if !small {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 30, color: shadowInk)
        ctx.addPath(squircle); ctx.setFillColor(gradTop); ctx.fillPath()
        ctx.restoreGState()
    }

    // Gradient ground.
    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let grad = CGGradient(colorsSpace: sRGB, colors: [gradTop, gradBot] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: sq.midX, y: sq.minY),
                           end: CGPoint(x: sq.midX, y: sq.maxY),
                           options: [])
    ctx.restoreGState()

    func P(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
        CGPoint(x: sq.minX + nx * side, y: sq.minY + ny * side)
    }

    // Four crop-viewfinder brackets.
    let brackets = CGMutablePath()
    brackets.move(to: P(0.28, 0.388)); brackets.addLine(to: P(0.28, 0.28)); brackets.addLine(to: P(0.388, 0.28))
    brackets.move(to: P(0.612, 0.28)); brackets.addLine(to: P(0.72, 0.28)); brackets.addLine(to: P(0.72, 0.388))
    brackets.move(to: P(0.72, 0.612)); brackets.addLine(to: P(0.72, 0.72)); brackets.addLine(to: P(0.612, 0.72))
    brackets.move(to: P(0.388, 0.72)); brackets.addLine(to: P(0.28, 0.72)); brackets.addLine(to: P(0.28, 0.612))
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setStrokeColor(graphite)
    ctx.setLineWidth(side * (small ? 0.075 : 0.05))
    ctx.addPath(brackets); ctx.strokePath()

    // Center mark: red arrow at large sizes, red dot when too small to read.
    if small {
        let r = side * 0.05
        ctx.setFillColor(signalRed)
        ctx.fillEllipse(in: CGRect(x: sq.midX - r, y: sq.midY - r, width: 2 * r, height: 2 * r))
    } else {
        let arrow = CGMutablePath()
        arrow.move(to: P(0.4375, 0.5625)); arrow.addLine(to: P(0.5625, 0.4375))
        arrow.move(to: P(0.4958, 0.4375)); arrow.addLine(to: P(0.5625, 0.4375)); arrow.addLine(to: P(0.5625, 0.5042))
        ctx.setStrokeColor(signalRed)
        ctx.setLineWidth(side * 0.0458)
        ctx.addPath(arrow); ctx.strokePath()
    }

    // Hairline inner edge for a crisp rim.
    ctx.setStrokeColor(edgeInk); ctx.setLineWidth(3)
    ctx.addPath(squircle); ctx.strokePath()
}

func iconImage(px: Int, small: Bool) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    // Flip to a top-left origin, then scale the 1024-unit design space to px.
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: 1, y: -1)
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    drawAppIcon(ctx, small: small)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: - Menu-bar template (vector; single color + alpha; AppKit tints it per theme)

// Brackets + center dot, symmetric so it needs no y-flip. Shared by the PDF and the preview.
func drawTemplateGlyph(_ ctx: CGContext, in rect: CGRect, color: CGColor) {
    let side = rect.width
    func P(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + nx * side, y: rect.minY + ny * side)
    }
    let brackets = CGMutablePath()
    brackets.move(to: P(0.28, 0.40)); brackets.addLine(to: P(0.28, 0.28)); brackets.addLine(to: P(0.40, 0.28))
    brackets.move(to: P(0.60, 0.28)); brackets.addLine(to: P(0.72, 0.28)); brackets.addLine(to: P(0.72, 0.40))
    brackets.move(to: P(0.72, 0.60)); brackets.addLine(to: P(0.72, 0.72)); brackets.addLine(to: P(0.60, 0.72))
    brackets.move(to: P(0.40, 0.72)); brackets.addLine(to: P(0.28, 0.72)); brackets.addLine(to: P(0.28, 0.60))
    ctx.setStrokeColor(color)
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setLineWidth(side * 0.09)
    ctx.addPath(brackets); ctx.strokePath()

    let r = side * 0.05
    ctx.setFillColor(color)
    ctx.fillEllipse(in: CGRect(x: rect.midX - r, y: rect.midY - r, width: 2 * r, height: 2 * r))
}

func writeMenuBarPDF(to url: URL) {
    let s: CGFloat = 16
    var box = CGRect(x: 0, y: 0, width: s, height: s)
    let data = NSMutableData()
    let consumer = CGDataConsumer(data: data as CFMutableData)!
    let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    drawTemplateGlyph(ctx, in: box.insetBy(dx: 1.5, dy: 1.5), color: CGColor(gray: 0, alpha: 1))
    ctx.endPDFPage()
    ctx.closePDF()
    try! (data as Data).write(to: url)
}

// MARK: - Drive

func run(_ path: String, _ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    try! p.run(); p.waitUntilExit()
    if p.terminationStatus != 0 {
        FileHandle.standardError.write("failed: \(path) \(args.joined(separator: " "))\n".data(using: .utf8)!)
        exit(1)
    }
}

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let resources = cwd.appendingPathComponent("Resources")
let iconset = cwd.appendingPathComponent(".build/AppIcon.iconset")
try? fm.createDirectory(at: resources, withIntermediateDirectories: true)
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// The 10 slots iconutil expects.
let slots: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for slot in slots {
    let small = slot.px <= 64
    writePNG(iconImage(px: slot.px, small: small), to: iconset.appendingPathComponent("\(slot.name).png"))
}
run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path])
writeMenuBarPDF(to: resources.appendingPathComponent("MenuBarIcon.pdf"))
print("Wrote Resources/AppIcon.icns and Resources/MenuBarIcon.pdf")

// Optional preview sheets for visual inspection.
if CommandLine.arguments.count > 1 {
    let dir = URL(fileURLWithPath: CommandLine.arguments[1])
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

    // App icon at a range of sizes on a neutral ground (so transparency reads).
    let sizes = [512, 256, 128, 64, 32, 16]
    let gap = 24, margin = 24
    let W = margin * 2 + sizes.reduce(0, +) + gap * (sizes.count - 1)
    let H = margin * 2 + 512
    let sheet = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                          space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    sheet.setFillColor(rgb(0.62, 0.64, 0.68)); sheet.fill(CGRect(x: 0, y: 0, width: W, height: H))
    var x = margin
    for s in sizes {
        let img = iconImage(px: s, small: s <= 64)
        sheet.draw(img, in: CGRect(x: x, y: H - margin - s, width: s, height: s)) // top-aligned
        x += s + gap
    }
    writePNG(sheet.makeImage()!, to: dir.appendingPathComponent("preview-appicon.png"))

    // Menu-bar template on light and dark bars (mimics AppKit's template tinting).
    let cell = 120, glyph = 44
    let mb = CGContext(data: nil, width: cell * 2, height: cell, bitsPerComponent: 8, bytesPerRow: 0,
                       space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    mb.setFillColor(rgb(0.96, 0.96, 0.97)); mb.fill(CGRect(x: 0, y: 0, width: cell, height: cell))
    mb.setFillColor(rgb(0.16, 0.17, 0.19)); mb.fill(CGRect(x: cell, y: 0, width: cell, height: cell))
    let inset = (cell - glyph) / 2
    drawTemplateGlyph(mb, in: CGRect(x: inset, y: inset, width: glyph, height: glyph), color: rgb(0.12, 0.12, 0.13))
    drawTemplateGlyph(mb, in: CGRect(x: cell + inset, y: inset, width: glyph, height: glyph), color: rgb(1, 1, 1))
    writePNG(mb.makeImage()!, to: dir.appendingPathComponent("preview-menubar.png"))
    print("Wrote previews to \(dir.path)")
}
