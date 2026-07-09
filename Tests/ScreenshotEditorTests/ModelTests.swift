import CoreGraphics
import Testing
@testable import ScreenshotEditor

@Suite struct CanvasTransformTests {
    @Test func roundTripPointAndRect() {
        let t = CanvasTransform(scale: 0.5, offset: CGPoint(x: 20, y: 10))
        let p = CGPoint(x: 123, y: 456)
        let back = t.toImage(t.toView(p))
        #expect(abs(back.x - p.x) < 1e-9 && abs(back.y - p.y) < 1e-9)

        let r = CGRect(x: 10, y: 20, width: 300, height: 400)
        let backRect = t.toImage(t.toView(r))
        #expect(abs(backRect.midX - r.midX) < 1e-9 && abs(backRect.height - r.height) < 1e-9)
    }

    @Test func fitNeverUpscalesPastNaturalSize() {
        // 200x100 px @2x in a huge view: capped at 1/2 (natural size), centered.
        let t = CanvasTransform.fit(pixelSize: CGSize(width: 200, height: 100),
                                    in: CGSize(width: 2000, height: 2000),
                                    pixelsPerPoint: 2)
        let expectedScale: CGFloat = 0.5
        let expectedOffsetX: CGFloat = (2000 - 100) / 2
        #expect(t.scale == expectedScale)
        #expect(t.offset.x == expectedOffsetX)
    }

    @Test func fitShrinksToWindow() {
        let t = CanvasTransform.fit(pixelSize: CGSize(width: 1600, height: 1200),
                                    in: CGSize(width: 400, height: 400),
                                    pixelsPerPoint: 2)
        let expectedScale: CGFloat = 400.0 / 1600.0
        #expect(t.scale == expectedScale)
    }
}

@Suite struct HitTestTests {
    private let style = AnnotationStyle(color: .red, strokeWidthPx: 4)

    @Test func rectangleHitsBorderNotInterior() {
        let a = Annotation(kind: .rectangle(rect: CGRect(x: 100, y: 100, width: 200, height: 100)),
                           style: style)
        #expect(a.hitTest(CGPoint(x: 100, y: 150), tolerance: 6))      // left edge
        #expect(a.hitTest(CGPoint(x: 300, y: 100), tolerance: 6))      // corner
        #expect(!a.hitTest(CGPoint(x: 200, y: 150), tolerance: 6))     // deep interior
        #expect(!a.hitTest(CGPoint(x: 50, y: 50), tolerance: 6))       // outside
    }

    @Test func tinyRectangleIsFullyHittable() {
        let a = Annotation(kind: .rectangle(rect: CGRect(x: 10, y: 10, width: 4, height: 4)),
                           style: style)
        #expect(a.hitTest(CGPoint(x: 12, y: 12), tolerance: 6))
    }

    @Test func ellipseHitsBorderBand() {
        let a = Annotation(kind: .ellipse(rect: CGRect(x: 0, y: 0, width: 200, height: 100)),
                           style: style)
        #expect(a.hitTest(CGPoint(x: 200, y: 50), tolerance: 6))       // rightmost point
        #expect(a.hitTest(CGPoint(x: 100, y: 0), tolerance: 6))        // topmost point
        #expect(!a.hitTest(CGPoint(x: 100, y: 50), tolerance: 6))      // center
        #expect(!a.hitTest(CGPoint(x: 0, y: 0), tolerance: 6))         // rect corner is OFF the ellipse
    }

    @Test func arrowHitsAlongSegment() {
        let a = Annotation(kind: .arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100)),
                           style: style)
        #expect(a.hitTest(CGPoint(x: 50, y: 52), tolerance: 6))
        #expect(!a.hitTest(CGPoint(x: 80, y: 20), tolerance: 6))
    }

    @Test func polylineHitUsesSegments() {
        let a = Annotation(kind: .pen(points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
                                               CGPoint(x: 100, y: 100)]),
                           style: style)
        #expect(a.hitTest(CGPoint(x: 50, y: 3), tolerance: 6))
        #expect(a.hitTest(CGPoint(x: 98, y: 60), tolerance: 6))
        #expect(!a.hitTest(CGPoint(x: 40, y: 60), tolerance: 6))
    }

    @Test func badgeHitsDisc() {
        let a = Annotation(kind: .badge(center: CGPoint(x: 50, y: 50), number: 1, radiusPx: 20),
                           style: style)
        #expect(a.hitTest(CGPoint(x: 60, y: 60), tolerance: 0))
        #expect(!a.hitTest(CGPoint(x: 100, y: 100), tolerance: 0))
    }
}

@Suite struct GeometryEditTests {
    private let style = AnnotationStyle(color: .blue, strokeWidthPx: 4)

    @Test func translateMovesEverything() {
        var a = Annotation(kind: .arrow(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 20, y: 30)),
                           style: style)
        a.translate(by: CGPoint(x: 5, y: -5))
        guard case .arrow(let s, let e) = a.kind else {
            Issue.record("kind changed"); return
        }
        #expect(s == CGPoint(x: 15, y: 5) && e == CGPoint(x: 25, y: 25))
    }

    @Test func resizeAnchorsOppositeCorner() {
        let a = Annotation(kind: .rectangle(rect: CGRect(x: 100, y: 100, width: 100, height: 100)),
                           style: style)
        let resized = a.resized(handle: .bottomRight, to: CGPoint(x: 300, y: 250))
        guard case .rectangle(let r) = resized.kind else {
            Issue.record("kind changed"); return
        }
        #expect(r == CGRect(x: 100, y: 100, width: 200, height: 150))

        // Dragging a corner past its anchor normalizes instead of inverting.
        let crossed = a.resized(handle: .bottomRight, to: CGPoint(x: 50, y: 60))
        guard case .rectangle(let r2) = crossed.kind else {
            Issue.record("kind changed"); return
        }
        #expect(r2 == CGRect(x: 50, y: 60, width: 50, height: 40))
    }

    @Test func dragRectNormalizes() {
        let r = CGRect(dragFrom: CGPoint(x: 200, y: 50), to: CGPoint(x: 100, y: 150))
        #expect(r == CGRect(x: 100, y: 50, width: 100, height: 100))
    }
}

@Suite struct DocumentTests {
    private func makeBase(width: Int = 400, height: Int = 300) -> BaseImage {
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return BaseImage(cgImage: ctx.makeImage()!, pixelsPerPoint: 2)
    }

    @Test func badgeNumberingIsStableMaxPlusOne() {
        var doc = Document(base: makeBase())
        let style = AnnotationStyle(color: .red, strokeWidthPx: 4)
        for n in [1, 2, 3] {
            doc.annotations.append(Annotation(
                kind: .badge(center: .zero, number: n, radiusPx: 20), style: style))
        }
        doc.annotations.remove(at: 1)          // delete badge 2 → {1, 3}
        #expect(doc.nextBadgeNumber == 4)      // stable: no renumbering
        doc.annotations.removeLast()           // delete badge 3 → {1}
        #expect(doc.nextBadgeNumber == 2)      // natural "oops, replace it"
    }

    @Test func cropRebasesAnnotationsAndBumpsGeneration() {
        var doc = Document(base: makeBase(width: 400, height: 300))
        doc.annotations = [Annotation(
            kind: .rectangle(rect: CGRect(x: 100, y: 100, width: 50, height: 50)),
            style: AnnotationStyle(color: .red, strokeWidthPx: 4))]
        doc.applyCrop(CGRect(x: 80, y: 90, width: 200, height: 150))
        #expect(doc.base.cgImage.width == 200 && doc.base.cgImage.height == 150)
        #expect(doc.cropGeneration == 1)
        guard case .rectangle(let r) = doc.annotations[0].kind else {
            Issue.record("kind changed"); return
        }
        #expect(r.origin == CGPoint(x: 20, y: 10))
    }

    @Test func cropOutsideBoundsIsIgnored() {
        var doc = Document(base: makeBase())
        doc.applyCrop(CGRect(x: 1000, y: 1000, width: 50, height: 50))
        #expect(doc.base.cgImage.width == 400 && doc.cropGeneration == 0)
    }
}
