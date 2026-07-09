import CoreGraphics
import Testing
@testable import ScreenshotEditor

/// Regressions for bugs confirmed by the adversarial review.
@Suite struct ReviewRegressionTests {
    private func makeViewModel(width: Int = 400, height: Int = 300) -> EditorViewModel {
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let base = BaseImage(cgImage: ctx.makeImage()!, pixelsPerPoint: 2)
        return EditorViewModel(document: Document(base: base))
    }

    @Test func eccentricEllipseHasNoFalsePositivesPastTips() {
        let a = Annotation(kind: .ellipse(rect: CGRect(x: 0, y: 0, width: 800, height: 10)),
                           style: AnnotationStyle(color: .red, strokeWidthPx: 6))
        // Far past the right tip on the midline: must NOT hit.
        #expect(!a.hitTest(CGPoint(x: 850, y: 5), tolerance: 6))
        #expect(!a.hitTest(CGPoint(x: 1100, y: 5), tolerance: 6))
        // On the tip and on the flat top edge: must hit.
        #expect(a.hitTest(CGPoint(x: 800, y: 5), tolerance: 6))
        #expect(a.hitTest(CGPoint(x: 400, y: 0), tolerance: 6))
    }

    @Test func hairlineEllipseIsStillHittable() {
        let a = Annotation(kind: .ellipse(rect: CGRect(x: 10, y: 10, width: 200, height: 0)),
                           style: AnnotationStyle(color: .red, strokeWidthPx: 6))
        #expect(a.hitTest(CGPoint(x: 100, y: 10), tolerance: 6))
    }

    @Test func undoDuringDragAbortsInsteadOfCorruptingHistory() {
        let vm = makeViewModel()
        vm.tool = .rectangle
        vm.pointerDown(at: CGPoint(x: 50, y: 50), tolerance: 6, handleTolerance: 8)
        vm.pointerDragged(to: CGPoint(x: 150, y: 120))
        vm.pointerUp(at: CGPoint(x: 150, y: 120))
        #expect(vm.document.annotations.count == 1)
        let committed = vm.document.annotations[0]

        // Start moving it, then hit ⌘Z mid-drag.
        vm.tool = .select
        vm.pointerDown(at: CGPoint(x: 100, y: 50), tolerance: 6, handleTolerance: 8)
        vm.pointerDragged(to: CGPoint(x: 130, y: 80))
        vm.undo()

        // The drag is aborted (position restored), history untouched.
        #expect(vm.document.annotations[0] == committed)
        #expect(vm.canUndo)      // the original draw is still undoable
        #expect(!vm.canRedo)     // no mid-drag junk pushed to redo
        #expect(vm.interaction == .idle)
    }

    @Test func deleteAndNudgeDuringDragAreIgnored() {
        let vm = makeViewModel()
        vm.tool = .rectangle
        vm.pointerDown(at: CGPoint(x: 50, y: 50), tolerance: 6, handleTolerance: 8)
        vm.pointerDragged(to: CGPoint(x: 150, y: 120))
        vm.pointerUp(at: CGPoint(x: 150, y: 120))

        vm.tool = .select
        vm.pointerDown(at: CGPoint(x: 100, y: 50), tolerance: 6, handleTolerance: 8)
        vm.pointerDragged(to: CGPoint(x: 110, y: 60))
        vm.deleteSelection()
        vm.nudgeSelection(dx: 1, dy: 0)
        #expect(vm.document.annotations.count == 1)   // still there mid-gesture
        vm.pointerUp(at: CGPoint(x: 110, y: 60))
        #expect(vm.document.annotations.count == 1)
    }

    @Test func styleChangeDuringNewTextEditLeavesNoGhostOnCancel() {
        let vm = makeViewModel()
        vm.tool = .text
        vm.pointerDown(at: CGPoint(x: 50, y: 50), tolerance: 6, handleTolerance: 8)
        #expect(vm.editingTextID != nil)
        vm.strokeColor = .blue          // style change mid-edit
        vm.cancelTextEdit()             // Esc
        #expect(vm.document.annotations.isEmpty)
        #expect(!vm.canUndo)
    }

    @Test func redoDuringTextEditDoesNotDestroyRedoStack() {
        let vm = makeViewModel()
        vm.tool = .badge
        vm.pointerDown(at: CGPoint(x: 50, y: 50), tolerance: 6, handleTolerance: 8)
        vm.undo()
        #expect(vm.canRedo)

        vm.tool = .text
        vm.pointerDown(at: CGPoint(x: 80, y: 80), tolerance: 6, handleTolerance: 8)
        vm.draftText = "hello"
        vm.redo()                        // mid-edit: must be a no-op
        #expect(vm.canRedo)
        vm.commitTextEdit()
    }

    @Test func annotationFullyOutsideImageIsNotCommitted() {
        let vm = makeViewModel(width: 400, height: 300)
        vm.tool = .rectangle
        vm.pointerDown(at: CGPoint(x: 500, y: 400), tolerance: 6, handleTolerance: 8)
        vm.pointerDragged(to: CGPoint(x: 600, y: 500))
        vm.pointerUp(at: CGPoint(x: 600, y: 500))
        #expect(vm.document.annotations.isEmpty)
    }
}
