import AppKit
import CoreText

/// CoreText measurement + drawing used by BOTH the on-screen canvas and export,
/// so committed text is pixel-identical in each. This is one of the three
/// y-flip sites in the app (CoreText draws y-up).
enum TextRendering {
    struct Metrics {
        var width: CGFloat
        var ascent: CGFloat
        var descent: CGFloat
        var height: CGFloat { ascent + descent }
    }

    static func font(sizePx: CGFloat, weight: NSFont.Weight = .semibold) -> NSFont {
        NSFont.systemFont(ofSize: sizePx, weight: weight)
    }

    private static func line(string: String, font: NSFont) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            // Take the fill color from the CGContext at draw time so the same
            // line works for measurement and any color.
            kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true,
        ]
        return CTLineCreateWithAttributedString(
            NSAttributedString(string: string, attributes: attributes))
    }

    static func metrics(string: String, font: NSFont) -> Metrics {
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line(string: string, font: font),
                                               &ascent, &descent, &leading)
        return Metrics(width: CGFloat(width), ascent: ascent, descent: descent)
    }

    /// Bounds of a committed text annotation in image pixels (origin = top-left).
    static func bounds(of payload: TextPayload) -> CGRect {
        let display = payload.string.isEmpty ? " " : payload.string
        let m = metrics(string: display, font: font(sizePx: payload.fontSizePx))
        return CGRect(x: payload.origin.x, y: payload.origin.y,
                      width: max(m.width, payload.fontSizePx * 0.4), height: m.height)
    }

    /// Draws `string` with its top-left at `origin` into a y-DOWN context.
    static func draw(string: String, font: NSFont, color: CGColor,
                     topLeft origin: CGPoint, shadow: Bool, in ctx: CGContext) {
        guard !string.isEmpty else { return }
        let m = metrics(string: string, font: font)
        ctx.saveGState()
        if shadow {
            ctx.setShadow(offset: .zero, blur: max(2, font.pointSize * 0.1),
                          color: CGColor(gray: 0, alpha: 0.5))
        }
        ctx.setFillColor(color)
        ctx.translateBy(x: origin.x, y: origin.y + m.ascent)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        ctx.textPosition = .zero
        CTLineDraw(line(string: string, font: font), ctx)
        ctx.restoreGState()
    }

    static func draw(_ payload: TextPayload, color: CGColor, in ctx: CGContext) {
        draw(string: payload.string, font: font(sizePx: payload.fontSizePx),
             color: color, topLeft: payload.origin, shadow: true, in: ctx)
    }

    /// Draws `string` optically centered on `center` (horizontal: typographic
    /// width; vertical: capHeight — bounding-box centering sits digits too low).
    static func drawCentered(string: String, font: NSFont, color: CGColor,
                             at center: CGPoint, in ctx: CGContext) {
        guard !string.isEmpty else { return }
        let m = metrics(string: string, font: font)
        let baselineY = center.y + font.capHeight / 2
        ctx.saveGState()
        ctx.setFillColor(color)
        ctx.translateBy(x: center.x - m.width / 2, y: baselineY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        ctx.textPosition = .zero
        CTLineDraw(line(string: string, font: font), ctx)
        ctx.restoreGState()
    }
}
