import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Headless export pipeline for scripted verification:
///   ScreenshotEditor --test-render <input.png> <annotations.json> <output.png>
/// Exercises the EXACT pipeline the UI uses (Document → AnnotationRenderer →
/// ExportService), so pixel assertions on the output cover real behavior.
///
/// JSON schema (all geometry in image pixels):
/// {
///   "annotations": [
///     {"type": "rectangle",   "rect": [x,y,w,h], "color": [r,g,b,a], "width": 6},
///     {"type": "ellipse",     "rect": [x,y,w,h], ...},
///     {"type": "arrow",       "start": [x,y], "end": [x,y], ...},
///     {"type": "pen",         "points": [[x,y], ...], ...},
///     {"type": "highlighter", "points": [[x,y], ...], ...},
///     {"type": "text",        "text": "hi", "origin": [x,y], "fontSize": 40, "color": [...]},
///     {"type": "badge",       "center": [x,y], "number": 1, "radius": 30, "color": [...]},
///     {"type": "blur",        "rect": [x,y,w,h], "radius": 12},
///     {"type": "pixelate",    "rect": [x,y,w,h], "block": 24}
///   ],
///   "crop": [x,y,w,h]   // optional, applied after annotations are placed
/// }
enum TestRenderMode {
    static func run(arguments: [String]) -> Int32 {
        guard let flagIndex = arguments.firstIndex(of: "--test-render"),
              arguments.count >= flagIndex + 4 else {
            FileHandle.standardError.write(Data(
                "usage: ScreenshotEditor --test-render <input.png> <annotations.json> <output.png>\n".utf8))
            return 2
        }
        let inputPath = arguments[flagIndex + 1]
        let jsonPath = arguments[flagIndex + 2]
        let outputPath = arguments[flagIndex + 3]

        guard let source = CGImageSourceCreateWithURL(
                URL(fileURLWithPath: inputPath) as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            FileHandle.standardError.write(Data("cannot read \(inputPath)\n".utf8))
            return 1
        }
        var pixelsPerPoint: CGFloat = 2
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let dpi = props[kCGImagePropertyDPIWidth] as? Double, dpi > 0 {
            pixelsPerPoint = CGFloat(dpi / 72)
        }

        var document = Document(base: BaseImage(cgImage: cgImage,
                                                pixelsPerPoint: pixelsPerPoint))
        do {
            let spec = try JSONSerialization.jsonObject(
                with: Data(contentsOf: URL(fileURLWithPath: jsonPath))) as? [String: Any] ?? [:]
            document.annotations = try parseAnnotations(spec["annotations"] as? [[String: Any]] ?? [])
            if let crop = spec["crop"] as? [Double], crop.count == 4 {
                document.applyCrop(CGRect(x: crop[0], y: crop[1],
                                          width: crop[2], height: crop[3]))
            }
        } catch {
            FileHandle.standardError.write(Data("bad annotations JSON: \(error)\n".utf8))
            return 1
        }

        let cache = BlurPatchCache()
        guard let rendered = ExportService.renderFullResolution(document, blurCache: cache),
              let png = ExportService.pngData(rendered,
                                              pixelsPerPoint: document.base.pixelsPerPoint) else {
            FileHandle.standardError.write(Data("render failed\n".utf8))
            return 1
        }
        do {
            try png.write(to: URL(fileURLWithPath: outputPath))
        } catch {
            FileHandle.standardError.write(Data("cannot write \(outputPath): \(error)\n".utf8))
            return 1
        }
        print("OK \(rendered.width)x\(rendered.height)")
        return 0
    }

    private enum ParseError: Error { case malformed(String) }

    private static func parseAnnotations(_ items: [[String: Any]]) throws -> [Annotation] {
        try items.map { item in
            guard let type = item["type"] as? String else {
                throw ParseError.malformed("missing type")
            }
            let style = AnnotationStyle(color: color(item["color"]),
                                        strokeWidthPx: cg(item["width"], default: 6))
            let kind: AnnotationKind
            switch type {
            case "rectangle": kind = .rectangle(rect: try rect(item["rect"]))
            case "ellipse": kind = .ellipse(rect: try rect(item["rect"]))
            case "arrow": kind = .arrow(start: try point(item["start"]),
                                        end: try point(item["end"]))
            case "pen": kind = .pen(points: try points(item["points"]))
            case "highlighter": kind = .highlighter(points: try points(item["points"]))
            case "text":
                kind = .text(TextPayload(string: item["text"] as? String ?? "",
                                         origin: try point(item["origin"]),
                                         fontSizePx: cg(item["fontSize"], default: 40)))
            case "badge":
                kind = .badge(center: try point(item["center"]),
                              number: item["number"] as? Int ?? 1,
                              radiusPx: cg(item["radius"], default: 30))
            case "blur":
                kind = .blur(rect: try rect(item["rect"]),
                             mode: .gaussian(radiusPx: cg(item["radius"], default: 12)))
            case "pixelate":
                kind = .blur(rect: try rect(item["rect"]),
                             mode: .pixelate(blockPx: cg(item["block"], default: 24)))
            default:
                throw ParseError.malformed("unknown type \(type)")
            }
            return Annotation(kind: kind, style: style)
        }
    }

    private static func cg(_ value: Any?, default fallback: CGFloat) -> CGFloat {
        (value as? Double).map { CGFloat($0) } ?? fallback
    }

    private static func color(_ value: Any?) -> RGBAColor {
        guard let c = value as? [Double], c.count == 4 else { return .red }
        return RGBAColor(r: c[0], g: c[1], b: c[2], a: c[3])
    }

    private static func rect(_ value: Any?) throws -> CGRect {
        guard let r = value as? [Double], r.count == 4 else {
            throw ParseError.malformed("rect must be [x,y,w,h]")
        }
        return CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
    }

    private static func point(_ value: Any?) throws -> CGPoint {
        guard let p = value as? [Double], p.count == 2 else {
            throw ParseError.malformed("point must be [x,y]")
        }
        return CGPoint(x: p[0], y: p[1])
    }

    private static func points(_ value: Any?) throws -> [CGPoint] {
        guard let list = value as? [[Double]] else {
            throw ParseError.malformed("points must be [[x,y],...]")
        }
        return try list.map { try point($0) }
    }
}
