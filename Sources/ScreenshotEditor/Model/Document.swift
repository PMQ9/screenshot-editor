import CoreGraphics
import Foundation

/// Immutable pixel-data wrapper so `Document` stays a cheap value type.
/// The CGImage is never mutated after init; equality is reference identity.
struct BaseImage: Equatable, @unchecked Sendable {
    let cgImage: CGImage
    /// Source pixel density (2.0 for Retina screenshots). Used only to convert
    /// point-denominated UI presets into pixels and to stamp PNG DPI on export.
    let pixelsPerPoint: CGFloat

    var pixelSize: CGSize {
        CGSize(width: cgImage.width, height: cgImage.height)
    }

    var pixelRect: CGRect {
        CGRect(origin: .zero, size: pixelSize)
    }

    static func == (lhs: BaseImage, rhs: BaseImage) -> Bool {
        lhs.cgImage === rhs.cgImage
    }
}

/// The whole editable state. Snapshots of this value ARE the undo stack.
struct Document: Equatable {
    var base: BaseImage
    var annotations: [Annotation] = []
    /// Bumped by crop so blur patches keyed on the old base image recompute.
    var cropGeneration: Int = 0

    var nextBadgeNumber: Int {
        let numbers = annotations.compactMap { annotation -> Int? in
            if case .badge(_, let n, _) = annotation.kind { return n }
            return nil
        }
        return (numbers.max() ?? 0) + 1
    }

    func index(of id: UUID) -> Int? {
        annotations.firstIndex { $0.id == id }
    }

    func annotation(with id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    /// Hit-test topmost-first. Blur regions are only grabbable via the select
    /// tool, which is the sole caller, so no special casing here.
    func topAnnotation(at p: CGPoint, tolerance: CGFloat) -> Annotation? {
        annotations.reversed().first { $0.hitTest(p, tolerance: tolerance) }
    }

    /// Destructive crop rebase: new base shares the backing store, annotations
    /// shift into the new origin, blur cache is invalidated via cropGeneration.
    mutating func applyCrop(_ pixelRect: CGRect) {
        let clamped = pixelRect.integral.intersection(base.pixelRect)
        guard clamped.width >= 1, clamped.height >= 1,
              let cropped = base.cgImage.cropping(to: clamped) else { return }
        base = BaseImage(cgImage: cropped, pixelsPerPoint: base.pixelsPerPoint)
        let delta = CGPoint(x: -clamped.minX, y: -clamped.minY)
        for i in annotations.indices {
            annotations[i].translate(by: delta)
        }
        cropGeneration += 1
    }
}
