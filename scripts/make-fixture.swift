// Generates a synthetic "Retina screenshot" test fixture:
// 1600x1200 px, four solid-color quadrants plus a 100-px registration grid,
// so scale/offset bugs show up in single-pixel probes.
// Usage: swift scripts/make-fixture.swift fixtures/fixture.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "fixtures/fixture.png"
let width = 1600, height = 1200

guard let ctx = CGContext(
    data: nil, width: width, height: height,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("no context") }

// CGBitmapContext is y-up; quadrant names below refer to IMAGE orientation (row 0 = top).
let w = CGFloat(width), h = CGFloat(height)
func fill(_ rect: CGRect, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
    ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
    ctx.fill(rect)
}
fill(CGRect(x: 0, y: h / 2, width: w / 2, height: h / 2), 1, 0, 0)      // top-left: red
fill(CGRect(x: w / 2, y: h / 2, width: w / 2, height: h / 2), 0, 1, 0)  // top-right: green
fill(CGRect(x: 0, y: 0, width: w / 2, height: h / 2), 0, 0, 1)          // bottom-left: blue
fill(CGRect(x: w / 2, y: 0, width: w / 2, height: h / 2), 1, 1, 0)      // bottom-right: yellow

ctx.setStrokeColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
ctx.setLineWidth(1)
for x in stride(from: 0, through: width, by: 100) {
    ctx.move(to: CGPoint(x: CGFloat(x) + 0.5, y: 0))
    ctx.addLine(to: CGPoint(x: CGFloat(x) + 0.5, y: h))
}
for y in stride(from: 0, through: height, by: 100) {
    ctx.move(to: CGPoint(x: 0, y: CGFloat(y) + 0.5))
    ctx.addLine(to: CGPoint(x: w, y: CGFloat(y) + 0.5))
}
ctx.strokePath()

guard let image = ctx.makeImage() else { fatalError("no image") }
let url = URL(fileURLWithPath: outPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no destination")
}
// 144 DPI marks it as a 2x (Retina) capture.
let props: [CFString: Any] = [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144]
CGImageDestinationAddImage(dest, image, props as CFDictionary)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print("wrote \(outPath) (\(width)x\(height))")
