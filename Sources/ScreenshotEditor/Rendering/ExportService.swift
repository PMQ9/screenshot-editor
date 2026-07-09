import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Full-resolution export: a bitmap context at EXACT base-image pixel
/// dimensions, fed through the shared renderer. No view state, no display
/// scale — pixels in == pixels out.
enum ExportService {
    static func renderFullResolution(_ document: Document,
                                     blurCache: BlurPatchCache?) -> CGImage? {
        let width = document.base.cgImage.width
        let height = document.base.cgImage.height
        guard width > 0, height > 0,
              let ctx = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: exportColorSpace(for: document.base.cgImage),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        // Flip once so the shared renderer's top-left/y-down convention holds.
        // (One of the isolated flip sites.)
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        AnnotationRenderer.draw(document, into: ctx, blurCache: blurCache)
        return ctx.makeImage()
    }

    /// Screenshots are typically Display P3; compositing into sRGB would
    /// visibly shift the base image, so keep the source space when it's RGB.
    private static func exportColorSpace(for image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb { return space }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    static func pngData(_ image: CGImage, pixelsPerPoint: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        // 144 DPI for 2x sources so paste targets show the natural size.
        let dpi = 72 * pixelsPerPoint
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    static func renderPNG(_ document: Document, blurCache: BlurPatchCache?) -> Data? {
        guard let image = renderFullResolution(document, blurCache: blurCache) else {
            return nil
        }
        return pngData(image, pixelsPerPoint: document.base.pixelsPerPoint)
    }
}
