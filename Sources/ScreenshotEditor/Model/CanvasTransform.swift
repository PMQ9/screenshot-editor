import CoreGraphics

/// The ONLY place pixel↔view mapping happens. Gestures, hit tolerance,
/// overlay positioning, and canvas drawing all go through this struct;
/// no other code multiplies by 2 or by a scale factor.
struct CanvasTransform: Equatable {
    /// View points per image pixel.
    var scale: CGFloat
    /// View-point position of the image's top-left corner.
    var offset: CGPoint

    func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * scale + offset.x, y: p.y * scale + offset.y)
    }

    func toImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - offset.x) / scale, y: (p.y - offset.y) / scale)
    }

    func toView(_ r: CGRect) -> CGRect {
        CGRect(origin: toView(r.origin),
               size: CGSize(width: r.width * scale, height: r.height * scale))
    }

    func toImage(_ r: CGRect) -> CGRect {
        CGRect(origin: toImage(r.origin),
               size: CGSize(width: r.width / scale, height: r.height / scale))
    }

    /// A constant on-screen tolerance (view points) expressed in image pixels.
    func imageTolerance(viewPoints: CGFloat) -> CGFloat {
        viewPoints / scale
    }

    /// Aspect-fit the image in the view, centered, never upscaling beyond
    /// the image's natural on-screen size (1 px = 1 device px on a matching display).
    static func fit(pixelSize: CGSize, in viewSize: CGSize, pixelsPerPoint: CGFloat) -> CanvasTransform {
        guard pixelSize.width > 0, pixelSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else {
            return CanvasTransform(scale: 1, offset: .zero)
        }
        let scale = min(viewSize.width / pixelSize.width,
                        viewSize.height / pixelSize.height,
                        1 / pixelsPerPoint)
        let offset = CGPoint(x: (viewSize.width - pixelSize.width * scale) / 2,
                             y: (viewSize.height - pixelSize.height * scale) / 2)
        return CanvasTransform(scale: scale, offset: offset)
    }

    /// Natural size (100%): 1 image pixel = 1 device pixel, top-left anchored.
    static func actualSize(pixelsPerPoint: CGFloat) -> CanvasTransform {
        CanvasTransform(scale: 1 / pixelsPerPoint, offset: .zero)
    }
}
