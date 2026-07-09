import CoreGraphics
import Foundation

// All annotation geometry is in BASE-IMAGE PIXELS, top-left origin, y-down.
// The view layer converts through CanvasTransform at the event boundary;
// nothing below this line knows about points or screen scale.

struct Annotation: Identifiable, Equatable, Sendable {
    let id: UUID
    var kind: AnnotationKind
    var style: AnnotationStyle

    init(id: UUID = UUID(), kind: AnnotationKind, style: AnnotationStyle) {
        self.id = id
        self.kind = kind
        self.style = style
    }
}

enum AnnotationKind: Equatable, Sendable {
    case rectangle(rect: CGRect)
    case ellipse(rect: CGRect)
    case arrow(start: CGPoint, end: CGPoint)
    case pen(points: [CGPoint])
    case highlighter(points: [CGPoint])
    case text(TextPayload)
    case badge(center: CGPoint, number: Int, radiusPx: CGFloat)
    case blur(rect: CGRect, mode: RedactionMode)
}

enum RedactionMode: Equatable, Hashable, Sendable {
    case gaussian(radiusPx: CGFloat)
    case pixelate(blockPx: CGFloat)
}

struct TextPayload: Equatable, Sendable {
    var string: String
    var origin: CGPoint      // top-left of the text bounds
    var fontSizePx: CGFloat
}

struct AnnotationStyle: Equatable, Sendable {
    var color: RGBAColor
    var strokeWidthPx: CGFloat
}

struct RGBAColor: Equatable, Hashable, Sendable {
    var r, g, b, a: Double

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    static let red = RGBAColor(r: 0.93, g: 0.19, b: 0.14, a: 1)
    static let orange = RGBAColor(r: 1.0, g: 0.58, b: 0.0, a: 1)
    static let yellow = RGBAColor(r: 1.0, g: 0.85, b: 0.16, a: 1)
    static let green = RGBAColor(r: 0.16, g: 0.72, b: 0.30, a: 1)
    static let blue = RGBAColor(r: 0.04, g: 0.44, b: 0.98, a: 1)
    static let black = RGBAColor(r: 0.1, g: 0.1, b: 0.1, a: 1)
    static let white = RGBAColor(r: 1, g: 1, b: 1, a: 1)
}

enum Handle: CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
    case start, end   // arrow endpoints
}

// MARK: - Geometry

extension Annotation {
    var isBlur: Bool {
        if case .blur = kind { return true }
        return false
    }

    /// Loose bounding box (ignores stroke width); text uses real font metrics.
    var bounds: CGRect {
        switch kind {
        case .rectangle(let rect), .ellipse(let rect), .blur(let rect, _):
            return rect
        case .arrow(let start, let end):
            return CGRect(containing: [start, end])
        case .pen(let points), .highlighter(let points):
            return CGRect(containing: points)
        case .text(let payload):
            return TextRendering.bounds(of: payload)
        case .badge(let center, _, let radius):
            return CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
        }
    }

    mutating func translate(by delta: CGPoint) {
        func moved(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + delta.x, y: p.y + delta.y) }
        func moved(_ r: CGRect) -> CGRect { r.offsetBy(dx: delta.x, dy: delta.y) }
        switch kind {
        case .rectangle(let rect): kind = .rectangle(rect: moved(rect))
        case .ellipse(let rect): kind = .ellipse(rect: moved(rect))
        case .arrow(let start, let end): kind = .arrow(start: moved(start), end: moved(end))
        case .pen(let points): kind = .pen(points: points.map(moved))
        case .highlighter(let points): kind = .highlighter(points: points.map(moved))
        case .text(var payload):
            payload.origin = moved(payload.origin)
            kind = .text(payload)
        case .badge(let center, let number, let radius):
            kind = .badge(center: moved(center), number: number, radiusPx: radius)
        case .blur(let rect, let mode): kind = .blur(rect: moved(rect), mode: mode)
        }
    }

    func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        let halfStroke = style.strokeWidthPx / 2
        switch kind {
        case .rectangle(let rect):
            return rect.borderBandContains(p, band: tolerance + halfStroke)
        case .ellipse(let rect):
            return rect.ellipseBorderContains(p, band: tolerance + halfStroke)
        case .arrow(let start, let end):
            return p.distanceToSegment(start, end) <= tolerance + halfStroke
        case .pen(let points):
            return p.isNear(polyline: points, within: tolerance + halfStroke)
        case .highlighter(let points):
            // Highlighter strokes are drawn ~3x wider than the preset.
            return p.isNear(polyline: points, within: tolerance + halfStroke * 3)
        case .text, .badge:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        case .blur(let rect, _):
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        }
    }

    /// Resize handles this annotation exposes, with their current pixel positions.
    var handles: [(handle: Handle, position: CGPoint)] {
        switch kind {
        case .rectangle(let rect), .ellipse(let rect), .blur(let rect, _):
            return [(.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
                    (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
                    (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
                    (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY))]
        case .arrow(let start, let end):
            return [(.start, start), (.end, end)]
        case .pen, .highlighter, .text, .badge:
            return []   // move-only
        }
    }

    /// Returns a copy with `handle` moved to `p`, anchored on the original geometry.
    func resized(handle: Handle, to p: CGPoint) -> Annotation {
        var copy = self
        switch kind {
        case .rectangle(let rect):
            copy.kind = .rectangle(rect: rect.movingCorner(handle, to: p))
        case .ellipse(let rect):
            copy.kind = .ellipse(rect: rect.movingCorner(handle, to: p))
        case .blur(let rect, let mode):
            copy.kind = .blur(rect: rect.movingCorner(handle, to: p), mode: mode)
        case .arrow(let start, let end):
            switch handle {
            case .start: copy.kind = .arrow(start: p, end: end)
            case .end: copy.kind = .arrow(start: start, end: p)
            default: break
            }
        case .pen, .highlighter, .text, .badge:
            break
        }
        return copy
    }
}

// MARK: - Geometry helpers

extension CGRect {
    /// Normalized rect spanning two drag points.
    init(dragFrom a: CGPoint, to b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y),
                  width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    init(containing points: [CGPoint]) {
        guard let first = points.first else {
            self = .zero
            return
        }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = Swift.min(minX, p.x); maxX = Swift.max(maxX, p.x)
            minY = Swift.min(minY, p.y); maxY = Swift.max(maxY, p.y)
        }
        self.init(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// True if `p` lies within `band` of the rect's border (not deep inside).
    func borderBandContains(_ p: CGPoint, band: CGFloat) -> Bool {
        let outer = insetBy(dx: -band, dy: -band)
        guard outer.contains(p) else { return false }
        let inner = insetBy(dx: band, dy: band)
        if inner.isNull || inner.isEmpty || inner.width <= 0 || inner.height <= 0 { return true }
        return !inner.contains(p)
    }

    /// True if `p` lies within `band` of the ellipse border inscribed in this rect.
    func ellipseBorderContains(_ p: CGPoint, band: CGFloat) -> Bool {
        let a = width / 2, b = height / 2
        guard a > 0, b > 0 else { return false }
        let dx = (p.x - midX) / a, dy = (p.y - midY) / b
        let t = (dx * dx + dy * dy).squareRoot()   // 1.0 exactly on the border
        return abs(t - 1) * Swift.min(a, b) <= band
    }

    func movingCorner(_ handle: Handle, to p: CGPoint) -> CGRect {
        let anchor: CGPoint
        switch handle {
        case .topLeft: anchor = CGPoint(x: maxX, y: maxY)
        case .topRight: anchor = CGPoint(x: minX, y: maxY)
        case .bottomLeft: anchor = CGPoint(x: maxX, y: minY)
        case .bottomRight: anchor = CGPoint(x: minX, y: minY)
        case .start, .end: return self
        }
        return CGRect(dragFrom: anchor, to: p)
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }

    func distanceToSegment(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x, aby = b.y - a.y
        let lengthSquared = abx * abx + aby * aby
        guard lengthSquared > 0 else { return distance(to: a) }
        let t = max(0, min(1, ((x - a.x) * abx + (y - a.y) * aby) / lengthSquared))
        return distance(to: CGPoint(x: a.x + t * abx, y: a.y + t * aby))
    }

    func isNear(polyline points: [CGPoint], within tolerance: CGFloat) -> Bool {
        guard !points.isEmpty else { return false }
        guard CGRect(containing: points)
            .insetBy(dx: -tolerance, dy: -tolerance).contains(self) else { return false }
        if points.count == 1 { return distance(to: points[0]) <= tolerance }
        for i in 0..<(points.count - 1)
        where distanceToSegment(points[i], points[i + 1]) <= tolerance {
            return true
        }
        return false
    }
}
