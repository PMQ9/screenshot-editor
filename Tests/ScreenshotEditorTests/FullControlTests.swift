import CoreGraphics
import Testing
@testable import ScreenshotEditor

/// Coverage for full move/resize/rotate + per-shape property control.
@Suite struct FullControlTests {
    private func makeViewModel(width: Int = 400, height: Int = 300) -> EditorViewModel {
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let base = BaseImage(cgImage: ctx.makeImage()!, pixelsPerPoint: 2)
        return EditorViewModel(document: Document(base: base))
    }

    private let style = AnnotationStyle(color: .red, strokeWidthPx: 4)

    private func drawRect(_ vm: EditorViewModel, from a: CGPoint, to b: CGPoint,
                          tool: Tool = .rectangle) {
        vm.tool = tool
        vm.pointerDown(at: a, tolerance: 6, handleTolerance: 8)
        vm.pointerDragged(to: b)
        vm.pointerUp(at: b)
    }

    // MARK: - Phase A: manipulation reachable from any tool

    @Test func selectedShapeMovesFromDrawTool() {
        let vm = makeViewModel()
        drawRect(vm, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 150, y: 120))
        #expect(vm.document.annotations.count == 1)
        #expect(vm.selectedID != nil)
        let before = vm.document.annotations[0].bounds

        // Still in the rectangle tool: pressing the shape's border moves it.
        vm.pointerDown(at: CGPoint(x: 100, y: 50), tolerance: 6, handleTolerance: 8)
        vm.pointerDragged(to: CGPoint(x: 130, y: 80))
        vm.pointerUp(at: CGPoint(x: 130, y: 80))
        #expect(vm.document.annotations.count == 1)     // no new rectangle drawn
        let after = vm.document.annotations[0].bounds
        #expect(after.minX == before.minX + 30 && after.minY == before.minY + 30)
    }

    @Test func selectedShapeResizesFromDrawTool() {
        let vm = makeViewModel()
        drawRect(vm, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 150, y: 120))
        // Grab the bottom-right handle while still in the rectangle tool.
        vm.pointerDown(at: CGPoint(x: 150, y: 120), tolerance: 6, handleTolerance: 8)
        vm.pointerDragged(to: CGPoint(x: 200, y: 200))
        vm.pointerUp(at: CGPoint(x: 200, y: 200))
        #expect(vm.document.annotations.count == 1)
        guard case .rectangle(let r) = vm.document.annotations[0].kind else {
            Issue.record("kind"); return
        }
        #expect(r == CGRect(x: 50, y: 50, width: 150, height: 150))
    }

    @Test func clickingEmptyCanvasStillDrawsFromDrawTool() {
        let vm = makeViewModel()
        drawRect(vm, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 150, y: 120))
        // Away from the selected shape: draws a second rectangle.
        drawRect(vm, from: CGPoint(x: 250, y: 200), to: CGPoint(x: 300, y: 250))
        #expect(vm.document.annotations.count == 2)
    }

    // MARK: - Phase E: rotation geometry

    @Test func rotatedResizeKeepsOppositeCornerFixed() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        var a = Annotation(kind: .rectangle(rect: rect), style: style)
        a.rotation = .pi / 6   // 30°
        let center = rect.center
        let fixedBefore = CGPoint(x: rect.minX, y: rect.minY).rotated(around: center, by: a.rotation)
        let draggedTo = CGPoint(x: 360, y: 240)

        let resized = a.resized(handle: .bottomRight, to: draggedTo)
        guard case .rectangle(let r2) = resized.kind else { Issue.record("kind"); return }
        #expect(resized.rotation == a.rotation)   // rotation preserved

        // Both the dragged corner and the fixed opposite corner must appear
        // among r2's world-space corners (normalization-order independent).
        let worldCorners = [CGPoint(x: r2.minX, y: r2.minY), CGPoint(x: r2.maxX, y: r2.minY),
                            CGPoint(x: r2.maxX, y: r2.maxY), CGPoint(x: r2.minX, y: r2.maxY)]
            .map { $0.rotated(around: r2.center, by: resized.rotation) }
        func present(_ p: CGPoint) -> Bool { worldCorners.contains { $0.distance(to: p) < 1e-6 } }
        #expect(present(draggedTo))
        #expect(present(fixedBefore))
    }

    @Test func unrotatedResizeUnchanged() {
        // rotation == 0 must match the legacy axis-aligned behavior exactly.
        let a = Annotation(kind: .rectangle(rect: CGRect(x: 100, y: 100, width: 100, height: 100)),
                           style: style)
        let resized = a.resized(handle: .bottomRight, to: CGPoint(x: 300, y: 250))
        guard case .rectangle(let r) = resized.kind else { Issue.record("kind"); return }
        #expect(r == CGRect(x: 100, y: 100, width: 200, height: 150))
    }

    @Test func rotatedHitTestUsesLocalFrame() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 40)
        var a = Annotation(kind: .rectangle(rect: rect), style: style)
        let rightMid = CGPoint(x: 300, y: 120)   // on the unrotated right edge
        #expect(a.hitTest(rightMid, tolerance: 6))

        a.rotation = .pi / 2
        #expect(!a.hitTest(rightMid, tolerance: 6))   // no longer on the border
        let rotatedRightMid = rightMid.rotated(around: rect.center, by: .pi / 2)
        #expect(a.hitTest(rotatedRightMid, tolerance: 6))
    }

    @Test func rotateHandleRotatesSelection() {
        let vm = makeViewModel()
        drawRect(vm, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 160))
        let a = vm.document.annotations[0]
        #expect(a.rotation == 0)

        let handlePos = a.handles.first { $0.handle == .rotate }!.position
        let center = a.rotationCenter
        vm.pointerDown(at: handlePos, tolerance: 6, handleTolerance: 8)
        // Drag the handle to due-right of center → +90°.
        vm.pointerDragged(to: CGPoint(x: center.x + 50, y: center.y))
        vm.pointerUp(at: CGPoint(x: center.x + 50, y: center.y))
        #expect(abs(vm.document.annotations[0].rotation - .pi / 2) < 1e-6)
    }

    // MARK: - Phase D: z-order

    @Test func zOrderReordersSelection() {
        let vm = makeViewModel()
        let a = Annotation(kind: .rectangle(rect: CGRect(x: 0, y: 0, width: 10, height: 10)), style: style)
        let b = Annotation(kind: .rectangle(rect: CGRect(x: 20, y: 0, width: 10, height: 10)), style: style)
        let c = Annotation(kind: .rectangle(rect: CGRect(x: 40, y: 0, width: 10, height: 10)), style: style)
        vm.document.annotations = [a, b, c]
        vm.selectedID = a.id

        vm.bringSelectionToFront()
        #expect(vm.document.annotations.map(\.id) == [b.id, c.id, a.id])
        vm.sendSelectionToBack()
        #expect(vm.document.annotations.map(\.id) == [a.id, b.id, c.id])
        vm.bringSelectionForward()
        #expect(vm.document.annotations.map(\.id) == [b.id, a.id, c.id])
        vm.sendSelectionBackward()
        #expect(vm.document.annotations.map(\.id) == [a.id, b.id, c.id])
    }

    // MARK: - Phase B/C: per-shape style edits apply + undo coalescing

    @Test func styleEditsApplyToSelectedShape() {
        let vm = makeViewModel()
        drawRect(vm, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 120))
        vm.fillEnabled = true
        vm.cornerRadiusPt = 5
        let s = vm.document.annotations[0].style
        #expect(s.filled)
        #expect(s.cornerRadiusPx == 5 * vm.pixelsPerPoint)
    }

    @Test func blurIntensityAndModeEditableAfterCreation() {
        let vm = makeViewModel()
        drawRect(vm, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 120), tool: .blur)
        #expect(vm.document.annotations.count == 1)

        vm.blurRadiusPt = 30
        guard case .blur(_, .gaussian(let r)) = vm.document.annotations[0].kind else {
            Issue.record("expected gaussian"); return
        }
        #expect(r == 30 * vm.pixelsPerPoint)

        vm.redactionMode = .pixelate
        vm.pixelateBlockPt = 16
        guard case .blur(_, .pixelate(let block)) = vm.document.annotations[0].kind else {
            Issue.record("expected pixelate"); return
        }
        #expect(block == 16 * vm.pixelsPerPoint)
    }

    @Test func sliderDragCoalescesToSingleUndoEntry() {
        let vm = makeViewModel()
        drawRect(vm, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 120))
        let undosAfterDraw = vm.undoStack.count

        // Simulate a slider drag: one begin, many value ticks, one end.
        vm.beginInteractiveEdit()
        for w: CGFloat in [3, 4, 5, 6, 7, 8] { vm.strokeWidthPt = w }
        vm.endInteractiveEdit()

        #expect(vm.undoStack.count == undosAfterDraw + 1)   // exactly one entry
        #expect(vm.document.annotations[0].style.strokeWidthPx == 8 * vm.pixelsPerPoint)
    }

    @Test func numericFrameEditsMoveAndResizeRect() {
        let vm = makeViewModel()
        drawRect(vm, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 120))
        vm.updateSelectedFrame(x: 10, y: 15, width: 200, height: 150)
        #expect(vm.selectedFrame == CGRect(x: 10, y: 15, width: 200, height: 150))
    }
}
