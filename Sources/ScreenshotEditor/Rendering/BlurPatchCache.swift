import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Blur/pixelate regions sample the BASE image (never other annotations).
/// Each region's rendered patch is cached until its geometry, parameters,
/// or the underlying image (via cropGeneration) change.
/// This is one of the three y-flip sites: Core Image is y-up.
final class BlurPatchCache {
    private struct Key: Equatable {
        let rect: CGRect
        let mode: RedactionMode
        let cropGeneration: Int
    }

    private var patches: [UUID: (key: Key, image: CGImage)] = [:]
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    func patch(for annotation: Annotation, base: BaseImage,
               cropGeneration: Int) -> (image: CGImage, rect: CGRect)? {
        guard case .blur(let rawRect, let mode) = annotation.kind else { return nil }
        let rect = rawRect.integral.intersection(base.pixelRect)
        guard rect.width >= 1, rect.height >= 1 else { return nil }

        let key = Key(rect: rect, mode: mode, cropGeneration: cropGeneration)
        if let cached = patches[annotation.id], cached.key == key {
            return (cached.image, rect)
        }

        let imageHeight = CGFloat(base.cgImage.height)
        let ciRect = CGRect(x: rect.minX, y: imageHeight - rect.maxY,
                            width: rect.width, height: rect.height)
        let input = CIImage(cgImage: base.cgImage)
        let output: CIImage
        switch mode {
        case .gaussian(let radiusPx):
            let filter = CIFilter.gaussianBlur()
            // clampedToExtent prevents transparent-edge bleed (dark halos).
            filter.inputImage = input.clampedToExtent()
            filter.radius = Float(radiusPx)
            output = (filter.outputImage ?? input).cropped(to: ciRect)
        case .pixelate(let blockPx):
            let filter = CIFilter.pixellate()
            filter.inputImage = input.clampedToExtent()
            filter.scale = Float(blockPx)
            // Anchor the block grid to the region so the pattern is stable
            // while the user resizes it.
            filter.center = CGPoint(x: ciRect.minX, y: ciRect.minY)
            output = (filter.outputImage ?? input).cropped(to: ciRect)
        }

        // Keep the base image's color space (screenshots are often Display P3);
        // the default sRGB output would gamut-clamp and seam at patch edges.
        let colorSpace = base.cgImage.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let image = ciContext.createCGImage(output, from: ciRect,
                                                  format: .RGBA8,
                                                  colorSpace: colorSpace) else { return nil }
        patches[annotation.id] = (key, image)
        return (image, rect)
    }

    func invalidateAll() {
        patches.removeAll()
    }

    /// Drop patches for annotations that no longer exist (undo, delete).
    func prune(keeping ids: Set<UUID>) {
        patches = patches.filter { ids.contains($0.key) }
    }
}
