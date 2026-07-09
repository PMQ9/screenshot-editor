import AppKit
import CoreGraphics

/// The single draw routine shared by the on-screen canvas
/// (`GraphicsContext.withCGContext`) and full-resolution export.
/// The context must already be transformed so 1 unit == 1 image pixel,
/// top-left origin, y-down. Screen and export cannot diverge: same code.
enum AnnotationRenderer {
    /// Passes: base image → blur/pixelate patches → vector annotations.
    /// Blur always sits below vectors; patches sample only the base image.
    static func draw(_ document: Document,
                     into ctx: CGContext,
                     blurCache: BlurPatchCache?,
                     excluding excludedID: UUID? = nil) {
        ctx.drawImageYDown(document.base.cgImage, in: document.base.pixelRect)

        for annotation in document.annotations where annotation.isBlur {
            guard annotation.id != excludedID else { continue }
            if let cache = blurCache,
               let patch = cache.patch(for: annotation, base: document.base,
                                       cropGeneration: document.cropGeneration) {
                if annotation.rotation != 0 {
                    // Patch pixels are the unrotated footprint (redaction is
                    // destructive + blurred, so source orientation is invisible);
                    // rotate the blit so the covered region matches the shape.
                    let c = annotation.rotationCenter
                    ctx.saveGState()
                    ctx.translateBy(x: c.x, y: c.y)
                    ctx.rotate(by: annotation.rotation)
                    ctx.translateBy(x: -c.x, y: -c.y)
                    ctx.drawImageYDown(patch.image, in: patch.rect)
                    ctx.restoreGState()
                } else {
                    ctx.drawImageYDown(patch.image, in: patch.rect)
                }
            }
        }

        for annotation in document.annotations
        where !annotation.isBlur && annotation.id != excludedID {
            draw(annotation, into: ctx)
        }
    }

    static func draw(_ annotation: Annotation, into ctx: CGContext) {
        guard annotation.isRotatable, annotation.rotation != 0 else {
            drawUnrotated(annotation, into: ctx)
            return
        }
        let c = annotation.rotationCenter
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: annotation.rotation)
        ctx.translateBy(x: -c.x, y: -c.y)
        drawUnrotated(annotation, into: ctx)
        ctx.restoreGState()
    }

    private static func drawUnrotated(_ annotation: Annotation, into ctx: CGContext) {
        let style = annotation.style
        switch annotation.kind {
        case .rectangle(let rect):
            ctx.saveGState()
            let path: CGPath = style.cornerRadiusPx > 0
                ? CGPath(roundedRect: rect.standardized,
                         cornerWidth: min(style.cornerRadiusPx, rect.width / 2),
                         cornerHeight: min(style.cornerRadiusPx, rect.height / 2),
                         transform: nil)
                : CGPath(rect: rect, transform: nil)
            if style.filled {
                ctx.setFillColor(style.fillColor.cgColor)
                ctx.addPath(path)
                ctx.fillPath()
            }
            if style.strokeWidthPx > 0 {
                ctx.setStrokeColor(style.color.cgColor)
                ctx.setLineWidth(style.strokeWidthPx)
                ctx.setLineJoin(.round)
                ctx.addPath(path)
                ctx.strokePath()
            }
            ctx.restoreGState()

        case .ellipse(let rect):
            ctx.saveGState()
            if style.filled {
                ctx.setFillColor(style.fillColor.cgColor)
                ctx.fillEllipse(in: rect)
            }
            if style.strokeWidthPx > 0 {
                ctx.setStrokeColor(style.color.cgColor)
                ctx.setLineWidth(style.strokeWidthPx)
                ctx.strokeEllipse(in: rect)
            }
            ctx.restoreGState()

        case .arrow(let start, let end):
            let geometry = ArrowGeometry(start: start, end: end,
                                         strokeWidthPx: style.strokeWidthPx,
                                         headScale: style.arrowHeadScale)
            ctx.saveGState()
            ctx.setStrokeColor(style.color.cgColor)
            ctx.setFillColor(style.color.cgColor)
            ctx.setLineWidth(style.strokeWidthPx)
            ctx.setLineCap(.round)
            ctx.move(to: geometry.shaftStart)
            ctx.addLine(to: geometry.shaftEnd)
            ctx.strokePath()
            ctx.addPath(geometry.headPath)
            ctx.fillPath()
            ctx.restoreGState()

        case .pen(let points):
            strokePolyline(points, width: style.strokeWidthPx,
                           color: style.color.cgColor, blendMode: .normal, in: ctx)

        case .highlighter(let points):
            // Classic marker: one path, ONE stroke op (no double-darkening at
            // self-overlaps), multiply blend at alpha 1.0, ~3x pen width.
            strokePolyline(points, width: style.strokeWidthPx * 3,
                           color: style.color.cgColor, blendMode: .multiply, in: ctx)

        case .text(let payload):
            TextRendering.draw(payload, color: style.color.cgColor, in: ctx)

        case .badge(let center, let number, let radius):
            let circle = CGRect(x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2)
            ctx.saveGState()
            ctx.setFillColor(style.color.cgColor)
            ctx.fillEllipse(in: circle)
            ctx.setStrokeColor(RGBAColor.white.cgColor)
            ctx.setLineWidth(max(1.5, radius * 0.12))
            ctx.strokeEllipse(in: circle.insetBy(dx: radius * 0.06, dy: radius * 0.06))
            ctx.restoreGState()
            TextRendering.drawCentered(
                string: String(number),
                font: TextRendering.font(sizePx: radius * 1.15, weight: .bold),
                color: RGBAColor.white.cgColor, at: center, in: ctx)

        case .blur:
            break   // handled in the patch pass
        }
    }

    private static func strokePolyline(_ points: [CGPoint], width: CGFloat,
                                       color: CGColor, blendMode: CGBlendMode,
                                       in ctx: CGContext) {
        guard let first = points.first else { return }
        ctx.saveGState()
        ctx.setBlendMode(blendMode)
        ctx.setFillColor(color)
        ctx.setStrokeColor(color)
        if points.count == 1 {
            // A click without a drag: round caps don't render zero-length lines.
            ctx.fillEllipse(in: CGRect(x: first.x - width / 2, y: first.y - width / 2,
                                       width: width, height: width))
        } else {
            ctx.setLineWidth(width)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(Self.smoothedPath(points))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Quadratic smoothing through segment midpoints — cheap and looks hand-drawn.
    static func smoothedPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count >= 3 else {
            for p in points.dropFirst() { path.addLine(to: p) }
            return path
        }
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2,
                              y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}

struct ArrowGeometry {
    let shaftStart: CGPoint
    let shaftEnd: CGPoint     // pulled back so the filled head owns the tip
    let headPath: CGPath

    init(start: CGPoint, end: CGPoint, strokeWidthPx: CGFloat, headScale: CGFloat = 1) {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = max(hypot(dx, dy), 0.001)
        let ux = dx / length, uy = dy / length
        let headLength = min(max(strokeWidthPx * 4.5, 18) * max(headScale, 0.1), length * 0.9)
        let headHalfWidth = headLength * 0.45
        shaftStart = start
        shaftEnd = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)
        let px = -uy, py = ux
        let path = CGMutablePath()
        path.move(to: end)
        path.addLine(to: CGPoint(x: shaftEnd.x + px * headHalfWidth,
                                 y: shaftEnd.y + py * headHalfWidth))
        path.addLine(to: CGPoint(x: shaftEnd.x - px * headHalfWidth,
                                 y: shaftEnd.y - py * headHalfWidth))
        path.closeSubpath()
        headPath = path
    }
}

extension CGContext {
    /// `CGContext.draw(_:in:)` assumes y-up; in our y-down contexts images
    /// would render mirrored. This helper flips locally around the target rect.
    /// (One of the isolated flip sites — nothing else may flip.)
    func drawImageYDown(_ image: CGImage, in rect: CGRect) {
        saveGState()
        translateBy(x: 0, y: rect.minY + rect.maxY)
        scaleBy(x: 1, y: -1)
        draw(image, in: rect)
        restoreGState()
    }
}
