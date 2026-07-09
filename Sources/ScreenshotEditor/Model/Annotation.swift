import CoreGraphics
import Foundation

// All annotation geometry is in BASE-IMAGE PIXELS, top-left origin, y-down.
// The view layer converts through CanvasTransform at the event boundary;
// nothing below this line knows about points or screen scale.

struct Annotation: Identifiable, Equatable, Sendable {
    let id: UUID
    var kind: AnnotationKind
    var style: AnnotationStyle
    /// Rotation about the shape's center, in radians (0 = axis-aligned).
    /// Applied only to rotatable kinds; ignored otherwise.
    var rotation: CGFloat = 0

    init(id: UUID = UUID(), kind: AnnotationKind, style: AnnotationStyle,
         rotation: CGFloat = 0) {
        self.id = id
        self.kind = kind
        self.style = style
        self.rotation = rotation
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
    var color: RGBAColor              // stroke color (a = stroke opacity)
    var strokeWidthPx: CGFloat
    // Fill (rectangle / ellipse). Older code and undo snapshots predate these,
    // so every field defaults to the previous stroke-only behavior.
    var filled: Bool = false
    var fillColor: RGBAColor = RGBAColor(r: 1, g: 1, b: 1, a: 0.25)
    var cornerRadiusPx: CGFloat = 0  // rectangle only; 0 = sharp corners
    /// Multiplier on the arrow head size (1 = default proportions).
    var arrowHeadScale: CGFloat = 1
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
    case rotate       // rotation handle (floats above the shape)
}

// MARK: - Geometry

extension Annotation {
    var isBlur: Bool {
        if case .blur = kind { return true }
        return false
    }

    /// Kinds that support a rotation angle. Arrows rotate by moving endpoints;
    /// pen/highlighter/badge are excluded.
    var isRotatable: Bool {
        switch kind {
        case .rectangle, .ellipse, .blur, .text: return true
        case .arrow, .pen, .highlighter, .badge: return false
        }
    }

    /// The point rotation pivots around (the shape's unrotated center).
    var rotationCenter: CGPoint {
        switch kind {
        case .rectangle(let r), .ellipse(let r), .blur(let r, _): return r.center
        default: return bounds.center
        }
    }

    /// The 4 corners of the shape's box in world space (rotated if applicable),
    /// used to draw the selection outline. Order: TL, TR, BR, BL.
    var outlineCorners: [CGPoint] {
        let b: CGRect
        switch kind {
        case .rectangle(let r), .ellipse(let r), .blur(let r, _): b = r
        default: b = bounds
        }
        let corners = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                       CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)]
        guard isRotatable, rotation != 0 else { return corners }
        let c = rotationCenter
        return corners.map { $0.rotated(around: c, by: rotation) }
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
        // Test in the shape's local (unrotated) frame.
        let q = (isRotatable && rotation != 0)
            ? p.rotated(around: rotationCenter, by: -rotation) : p
        let halfStroke = style.strokeWidthPx / 2
        switch kind {
        case .rectangle(let rect):
            return rect.borderBandContains(q, band: tolerance + halfStroke)
        case .ellipse(let rect):
            return rect.ellipseBorderContains(q, band: tolerance + halfStroke)
        case .arrow(let start, let end):
            return q.distanceToSegment(start, end) <= tolerance + halfStroke
        case .pen(let points):
            return q.isNear(polyline: points, within: tolerance + halfStroke)
        case .highlighter(let points):
            // Highlighter strokes are drawn ~3x wider than the preset.
            return q.isNear(polyline: points, within: tolerance + halfStroke * 3)
        case .text, .badge:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(q)
        case .blur(let rect, _):
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(q)
        }
    }

    /// Constant image-pixel gap between the shape's top edge and its rotate handle.
    private static let rotateHandleGap: CGFloat = 28

    /// Resize/rotate handles this annotation exposes, in world (rotated) space.
    var handles: [(handle: Handle, position: CGPoint)] {
        func rotated(_ p: CGPoint, _ c: CGPoint) -> CGPoint {
            rotation == 0 ? p : p.rotated(around: c, by: rotation)
        }
        switch kind {
        case .rectangle(let rect), .ellipse(let rect), .blur(let rect, _):
            let c = rect.center
            let rotateLocal = CGPoint(x: rect.midX, y: rect.minY - Self.rotateHandleGap)
            return [(.topLeft, rotated(CGPoint(x: rect.minX, y: rect.minY), c)),
                    (.topRight, rotated(CGPoint(x: rect.maxX, y: rect.minY), c)),
                    (.bottomLeft, rotated(CGPoint(x: rect.minX, y: rect.maxY), c)),
                    (.bottomRight, rotated(CGPoint(x: rect.maxX, y: rect.maxY), c)),
                    (.rotate, rotated(rotateLocal, c))]
        case .arrow(let start, let end):
            return [(.start, start), (.end, end)]
        case .text:
            let b = bounds
            let rotateLocal = CGPoint(x: b.midX, y: b.minY - Self.rotateHandleGap)
            return [(.rotate, rotated(rotateLocal, b.center))]
        case .pen, .highlighter, .badge:
            return []   // move-only
        }
    }

    /// Returns a copy with `handle` moved to `p`, anchored on the original geometry.
    func resized(handle: Handle, to p: CGPoint) -> Annotation {
        var copy = self
        switch kind {
        case .rectangle(let rect):
            copy.kind = .rectangle(rect: resizedRect(rect, handle: handle, to: p))
        case .ellipse(let rect):
            copy.kind = .ellipse(rect: resizedRect(rect, handle: handle, to: p))
        case .blur(let rect, let mode):
            copy.kind = .blur(rect: resizedRect(rect, handle: handle, to: p), mode: mode)
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

    /// Resize a (possibly rotated) rect by dragging `handle` to world point `p`,
    /// keeping the opposite corner fixed in world space. Reduces to the plain
    /// axis-aligned resize when `rotation == 0`.
    private func resizedRect(_ rect: CGRect, handle: Handle, to p: CGPoint) -> CGRect {
        guard rotation != 0 else { return rect.movingCorner(handle, to: p) }
        let center = rect.center
        let fixedWorld = rect.oppositeCorner(handle).rotated(around: center, by: rotation)
        let newCenter = CGPoint(x: (fixedWorld.x + p.x) / 2, y: (fixedWorld.y + p.y) / 2)
        return CGRect(dragFrom: fixedWorld.rotated(around: newCenter, by: -rotation),
                      to: p.rotated(around: newCenter, by: -rotation))
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

    /// True if `p` lies within `band` of the ellipse border inscribed in this
    /// rect, using the first-order distance approximation |f| / |∇f| for
    /// f = (dx/a)² + (dy/b)² − 1. (Scaling the ring deviation by min(a,b)
    /// balloons the hit zone along the major axis of eccentric ellipses.)
    func ellipseBorderContains(_ p: CGPoint, band: CGFloat) -> Bool {
        let a = width / 2, b = height / 2
        guard a > 0.5, b > 0.5 else {
            // Degenerate (hairline) ellipse renders as a line: hit like a rect border.
            return borderBandContains(p, band: band)
        }
        let dx = p.x - midX, dy = p.y - midY
        let f = (dx * dx) / (a * a) + (dy * dy) / (b * b) - 1
        let gradient = hypot(2 * dx / (a * a), 2 * dy / (b * b))
        guard gradient > 0 else { return band >= Swift.min(a, b) }   // exact center
        return abs(f) / gradient <= band
    }

    var center: CGPoint { CGPoint(x: midX, y: midY) }

    /// The corner diagonally opposite `handle` (the fixed anchor during resize).
    func oppositeCorner(_ handle: Handle) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: maxX, y: maxY)
        case .topRight: return CGPoint(x: minX, y: maxY)
        case .bottomLeft: return CGPoint(x: maxX, y: minY)
        case .bottomRight: return CGPoint(x: minX, y: minY)
        case .start, .end, .rotate: return center
        }
    }

    func movingCorner(_ handle: Handle, to p: CGPoint) -> CGRect {
        switch handle {
        case .start, .end, .rotate: return self
        default: return CGRect(dragFrom: oppositeCorner(handle), to: p)
        }
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }

    /// Rotate this point `angle` radians about `center`.
    func rotated(around center: CGPoint, by angle: CGFloat) -> CGPoint {
        let s = sin(angle), c = cos(angle)
        let dx = x - center.x, dy = y - center.y
        return CGPoint(x: center.x + dx * c - dy * s,
                       y: center.y + dx * s + dy * c)
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
