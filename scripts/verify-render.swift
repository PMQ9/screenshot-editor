// Pixel assertions over the --test-render outputs. Run by scripts/verify-render.sh.
// Usage: swift scripts/verify-render.swift <fixture.png> <out-full.png> <out-crop.png>
import CoreGraphics
import Foundation
import ImageIO

struct Raster {
    let width: Int, height: Int
    let bytes: [UInt8]   // RGBA8, sRGB

    init?(path: String) {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = image.width, h = image.height
        width = w
        height = h
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        bytes = buf
    }

    /// (x, y) in top-left-origin image coordinates. Buffer row 0 is the top
    /// row: CGBitmapContext memory starts at the highest context-space y.
    func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let i = (y * width + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    func count(in rect: (x: Int, y: Int, w: Int, h: Int),
               where predicate: ((r: Int, g: Int, b: Int)) -> Bool) -> Int {
        var n = 0
        for y in rect.y..<(rect.y + rect.h) {
            for x in rect.x..<(rect.x + rect.w) where predicate(pixel(x, y)) {
                n += 1
            }
        }
        return n
    }
}

func isGray(_ p: (r: Int, g: Int, b: Int)) -> Bool {
    abs(p.r - 128) <= 10 && abs(p.g - 128) <= 10 && abs(p.b - 128) <= 10
}

var failures = 0
func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    if condition {
        print("PASS  \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)  \(detail)")
    }
}

let args = CommandLine.arguments
guard args.count == 4,
      let fixture = Raster(path: args[1]),
      let full = Raster(path: args[2]),
      let cropped = Raster(path: args[3]) else {
    print("FAIL  could not load rasters; usage: verify-render.swift fixture out-full out-crop")
    exit(1)
}

// --- Dimensions: the #1 Retina bug class (half-res / double-res export). ---
check("full export is exact pixel size", full.width == 1600 && full.height == 1200,
      "got \(full.width)x\(full.height)")
check("cropped export is exact crop size", cropped.width == 1000 && cropped.height == 800,
      "got \(cropped.width)x\(cropped.height)")

// --- Vector annotations at exact pixel positions. ---
let rectEdge = full.pixel(250, 100)
check("rectangle stroke on edge", rectEdge.r > 200 && rectEdge.g > 200 && rectEdge.b > 200,
      "got \(rectEdge)")
let rectInterior = full.pixel(250, 250)
check("rectangle interior untouched (red quadrant)",
      rectInterior.r > 200 && rectInterior.g < 60 && rectInterior.b < 60,
      "got \(rectInterior)")
let ellipseTop = full.pixel(1150, 150)
check("ellipse stroke at topmost point", ellipseTop.r > 200 && ellipseTop.g > 200 && ellipseTop.b > 200,
      "got \(ellipseTop)")
let arrowMid = full.pixel(1250, 775)
check("arrow shaft at midpoint", arrowMid.b > 180 && arrowMid.r > 200,
      "got \(arrowMid)")
let penMid = full.pixel(250, 650)
check("pen stroke", penMid.r > 200 && penMid.g > 200 && penMid.b > 200,
      "got \(penMid)")

// --- Highlighter: yellow multiply over pure blue → (0, 0, ~41). ---
let hl = full.pixel(320, 750)   // off the x=300 grid line
check("highlighter multiplies (not opaque paint)",
      hl.r < 40 && hl.g < 70 && hl.b > 10 && hl.b < 110,
      "got \(hl)")

// --- Text: enough white core pixels inside the text bounds. ---
let textWhite = full.count(in: (800, 950, 300, 100)) { $0.r > 220 && $0.g > 220 && $0.b > 220 }
check("text renders (white pixel mass)", textWhite > 100, "got \(textWhite) px")

// --- Badge: red disc below the digit. ---
let badge = full.pixel(300, 985)
check("badge disc fill", badge.r > 180 && badge.g < 90 && badge.b < 90, "got \(badge)")

// --- Redaction: grid lines must be DESTROYED inside blur/pixelate regions. ---
let blurRegion = (x: 700, y: 100, w: 200, h: 150)
let grayBeforeBlur = fixture.count(in: blurRegion, where: isGray)
let grayAfterBlur = full.count(in: blurRegion, where: isGray)
check("fixture blur region contains grid to destroy", grayBeforeBlur > 100,
      "got \(grayBeforeBlur)")
check("gaussian blur destroys grid lines", grayAfterBlur < 20,
      "before \(grayBeforeBlur), after \(grayAfterBlur)")
let blend = full.pixel(800, 175)
check("gaussian blur blends across red/green boundary", blend.r > 60 && blend.g > 60,
      "got \(blend)")

let pixRegion = (x: 850, y: 820, w: 180, h: 120)
let grayBeforePix = fixture.count(in: pixRegion, where: isGray)
let grayAfterPix = full.count(in: pixRegion, where: isGray)
check("fixture pixelate region contains grid to destroy", grayBeforePix > 100,
      "got \(grayBeforePix)")
check("pixelate destroys grid lines", grayAfterPix < 20,
      "before \(grayBeforePix), after \(grayAfterPix)")

// --- Crop: annotation drawn pre-crop lands at the rebased position. ---
let cropEdge = cropped.pixel(150, 100)
check("crop rebases annotation position", cropEdge.r > 200 && cropEdge.g > 200 && cropEdge.b > 200,
      "got \(cropEdge)")
let cropInterior = cropped.pixel(150, 150)
check("crop shows correct source region (red quadrant)",
      cropInterior.r > 200 && cropInterior.g < 60 && cropInterior.b < 60,
      "got \(cropInterior)")

if failures > 0 {
    print("\(failures) FAILURES")
    exit(1)
}
print("ALL RENDER CHECKS PASSED")
