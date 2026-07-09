import AppKit
import Observation

enum Tool: CaseIterable, Equatable, Sendable {
    case select, rectangle, ellipse, arrow, pen, highlighter, text, badge, blur, pixelate, crop
}

enum ZoomMode: Equatable, Sendable {
    case fit
    case actualSize   // 1 image pixel = 1 device pixel
}

enum Interaction: Equatable {
    case idle
    case drawing(draft: Annotation, anchor: CGPoint)
    case draggingAnnotation(id: UUID, lastPoint: CGPoint)
    case resizing(id: UUID, handle: Handle, original: Annotation)
    case editingText(id: UUID)
    case croppingDrag(anchor: CGPoint, current: CGPoint)
    case croppingDraft(rect: CGRect)   // parked until Return applies it
}

/// Tool/interaction state machine. All incoming points are already in
/// image-pixel space (the view converts via CanvasTransform at the boundary).
@MainActor @Observable final class EditorViewModel {
    var document: Document
    var tool: Tool = .select {
        didSet {
            guard tool != oldValue else { return }
            // Resolve anything the previous tool left in flight.
            switch interaction {
            case .editingText:
                commitTextEdit()
            case .croppingDrag, .croppingDraft, .drawing:
                interaction = .idle
            case .idle, .draggingAnnotation, .resizing:
                break
            }
        }
    }
    var interaction: Interaction = .idle
    var selectedID: UUID?
    var zoomMode: ZoomMode = .fit
    var draftText: String = ""

    // Style presets are point-denominated in the UI, pixel-denominated in the model.
    var strokeColor: RGBAColor = .red {
        didSet { applyStyleToSelection() }
    }
    var strokeWidthPt: CGFloat = 3 {
        didSet { applyStyleToSelection() }
    }
    var fontSizePt: CGFloat = 20 {
        didSet { applyStyleToSelection() }
    }

    let blurCache = BlurPatchCache()

    private(set) var undoStack: [Document] = []
    private(set) var redoStack: [Document] = []
    private var preGestureSnapshot: Document?

    init(document: Document) {
        self.document = document
    }

    var pixelsPerPoint: CGFloat { document.base.pixelsPerPoint }
    var strokeWidthPx: CGFloat { strokeWidthPt * pixelsPerPoint }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Annotation being drawn right now (not yet committed to the document).
    var draftAnnotation: Annotation? {
        if case .drawing(let draft, _) = interaction { return draft }
        return nil
    }

    var cropDraftRect: CGRect? {
        switch interaction {
        case .croppingDrag(let anchor, let current):
            return CGRect(dragFrom: anchor, to: current)
        case .croppingDraft(let rect):
            return rect
        default:
            return nil
        }
    }

    var editingTextID: UUID? {
        if case .editingText(let id) = interaction { return id }
        return nil
    }

    // MARK: - Undo (snapshot stacks; one entry per user-visible operation)

    private func beginGesture() {
        preGestureSnapshot = document
    }

    private func endGesture() {
        if let snapshot = preGestureSnapshot, snapshot != document {
            undoStack.append(snapshot)
            redoStack.removeAll()
        }
        preGestureSnapshot = nil
    }

    func undo() {
        if case .editingText = interaction { cancelTextEdit() }
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
        didRestoreHistory()
    }

    func redo() {
        if case .editingText = interaction { commitTextEdit() }
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        didRestoreHistory()
    }

    private func didRestoreHistory() {
        interaction = .idle
        preGestureSnapshot = nil
        if let id = selectedID, document.annotation(with: id) == nil {
            selectedID = nil
        }
        blurCache.prune(keeping: Set(document.annotations.map(\.id)))
    }

    // MARK: - Pointer events (image-pixel space)

    func pointerDown(at p: CGPoint, tolerance: CGFloat, handleTolerance: CGFloat) {
        if case .editingText = interaction {
            commitTextEdit()
        }
        if case .croppingDraft(let rect) = interaction {
            // Inside the marquee: wait for Return/double-click to apply.
            // Outside: restart the marquee (crop tool) or fall through.
            if rect.insetBy(dx: -tolerance, dy: -tolerance).contains(p) {
                return
            }
            interaction = .idle
        }

        switch tool {
        case .select:
            if let handle = selectedHandleHit(at: p, tolerance: handleTolerance),
               let id = selectedID, let original = document.annotation(with: id) {
                beginGesture()
                interaction = .resizing(id: id, handle: handle, original: original)
                return
            }
            if let hit = document.topAnnotation(at: p, tolerance: tolerance) {
                selectedID = hit.id
                beginGesture()
                interaction = .draggingAnnotation(id: hit.id, lastPoint: p)
            } else {
                selectedID = nil
            }

        case .rectangle, .ellipse, .arrow, .blur, .pixelate:
            let draft = Annotation(kind: draftKind(at: p), style: currentStyle)
            selectedID = nil
            interaction = .drawing(draft: draft, anchor: p)

        case .pen, .highlighter:
            let kind: AnnotationKind = tool == .pen
                ? .pen(points: [p]) : .highlighter(points: [p])
            selectedID = nil
            interaction = .drawing(draft: Annotation(kind: kind, style: currentStyle),
                                   anchor: p)

        case .text:
            beginGesture()
            let payload = TextPayload(string: "", origin: p,
                                      fontSizePx: fontSizePt * pixelsPerPoint)
            let annotation = Annotation(kind: .text(payload), style: currentStyle)
            document.annotations.append(annotation)
            selectedID = annotation.id
            draftText = ""
            interaction = .editingText(id: annotation.id)

        case .badge:
            beginGesture()
            let annotation = Annotation(
                kind: .badge(center: p, number: document.nextBadgeNumber,
                             radiusPx: 15 * pixelsPerPoint),
                style: currentStyle)
            document.annotations.append(annotation)
            selectedID = annotation.id
            endGesture()

        case .crop:
            selectedID = nil
            interaction = .croppingDrag(anchor: p, current: p)
        }
    }

    func pointerDragged(to p: CGPoint) {
        switch interaction {
        case .drawing(var draft, let anchor):
            switch draft.kind {
            case .rectangle:
                draft.kind = .rectangle(rect: CGRect(dragFrom: anchor, to: p))
            case .ellipse:
                draft.kind = .ellipse(rect: CGRect(dragFrom: anchor, to: p))
            case .blur(_, let mode):
                draft.kind = .blur(rect: CGRect(dragFrom: anchor, to: p), mode: mode)
            case .arrow:
                draft.kind = .arrow(start: anchor, end: p)
            case .pen(var points):
                if p.distance(to: points[points.count - 1]) >= 2 {
                    points.append(p)
                    draft.kind = .pen(points: points)
                }
            case .highlighter(var points):
                if p.distance(to: points[points.count - 1]) >= 2 {
                    points.append(p)
                    draft.kind = .highlighter(points: points)
                }
            case .text, .badge:
                break
            }
            interaction = .drawing(draft: draft, anchor: anchor)

        case .draggingAnnotation(let id, let lastPoint):
            guard let index = document.index(of: id) else {
                interaction = .idle
                return
            }
            document.annotations[index].translate(
                by: CGPoint(x: p.x - lastPoint.x, y: p.y - lastPoint.y))
            interaction = .draggingAnnotation(id: id, lastPoint: p)

        case .resizing(let id, let handle, let original):
            guard let index = document.index(of: id) else {
                interaction = .idle
                return
            }
            document.annotations[index] = original.resized(handle: handle, to: p)

        case .croppingDrag(let anchor, _):
            interaction = .croppingDrag(anchor: anchor, current: p)

        case .idle, .editingText, .croppingDraft:
            break
        }
    }

    func pointerUp(at p: CGPoint) {
        switch interaction {
        case .drawing(let draft, let anchor):
            interaction = .idle
            guard isCommittable(draft, anchor: anchor, end: p) else { return }
            beginGesture()
            document.annotations.append(draft)
            endGesture()
            // Keep the tool active for rapid repeated annotation,
            // but select the new annotation so it's immediately adjustable.
            selectedID = draft.id

        case .draggingAnnotation, .resizing:
            endGesture()
            interaction = .idle

        case .croppingDrag(let anchor, let current):
            let rect = CGRect(dragFrom: anchor, to: current)
            interaction = (rect.width >= 4 && rect.height >= 4)
                ? .croppingDraft(rect: rect) : .idle

        case .idle, .editingText, .croppingDraft:
            break
        }
    }

    /// Double-click: apply a pending crop, or start editing a text annotation.
    func doubleClick(at p: CGPoint, tolerance: CGFloat) {
        if case .croppingDraft(let rect) = interaction,
           rect.insetBy(dx: -tolerance, dy: -tolerance).contains(p) {
            applyCropDraft()
            return
        }
        guard tool == .select,
              let hit = document.topAnnotation(at: p, tolerance: tolerance),
              case .text = hit.kind else { return }
        // The drag gesture's pointer down/up already ran for this click;
        // make sure it left no half-open gesture behind.
        interaction = .idle
        preGestureSnapshot = nil
        selectedID = hit.id
        startTextEdit(id: hit.id)
    }

    private func draftKind(at p: CGPoint) -> AnnotationKind {
        let zero = CGRect(origin: p, size: .zero)
        switch tool {
        case .rectangle: return .rectangle(rect: zero)
        case .ellipse: return .ellipse(rect: zero)
        case .arrow: return .arrow(start: p, end: p)
        case .blur: return .blur(rect: zero, mode: .gaussian(radiusPx: 8 * pixelsPerPoint))
        case .pixelate: return .blur(rect: zero, mode: .pixelate(blockPx: 12 * pixelsPerPoint))
        default: return .rectangle(rect: zero)
        }
    }

    private var currentStyle: AnnotationStyle {
        AnnotationStyle(color: strokeColor, strokeWidthPx: strokeWidthPx)
    }

    private func isCommittable(_ draft: Annotation, anchor: CGPoint, end: CGPoint) -> Bool {
        switch draft.kind {
        case .rectangle(let r), .ellipse(let r), .blur(let r, _):
            return hypot(r.width, r.height) >= 4
        case .arrow(let start, let end):
            return start.distance(to: end) >= 4
        case .pen, .highlighter:
            return true   // a click is a legitimate dot
        case .text, .badge:
            return true
        }
    }

    private func selectedHandleHit(at p: CGPoint, tolerance: CGFloat) -> Handle? {
        guard let id = selectedID, let annotation = document.annotation(with: id) else {
            return nil
        }
        return annotation.handles
            .first { $0.position.distance(to: p) <= tolerance }?.handle
    }

    // MARK: - Selection edits

    private func applyStyleToSelection() {
        guard let id = selectedID, let index = document.index(of: id) else { return }
        beginGesture()
        document.annotations[index].style.color = strokeColor
        document.annotations[index].style.strokeWidthPx = strokeWidthPx
        if case .text(var payload) = document.annotations[index].kind {
            payload.fontSizePx = fontSizePt * pixelsPerPoint
            document.annotations[index].kind = .text(payload)
        }
        endGesture()
    }

    func deleteSelection() {
        if case .editingText = interaction {
            cancelTextEdit()
            return
        }
        guard let id = selectedID, let index = document.index(of: id) else { return }
        beginGesture()
        document.annotations.remove(at: index)
        endGesture()
        selectedID = nil
        blurCache.prune(keeping: Set(document.annotations.map(\.id)))
    }

    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard let id = selectedID, let index = document.index(of: id) else { return }
        beginGesture()
        document.annotations[index].translate(
            by: CGPoint(x: dx * pixelsPerPoint, y: dy * pixelsPerPoint))
        endGesture()
    }

    // MARK: - Keyboard

    /// Esc: cancel whatever is in progress, then deselect.
    /// Returns false when there was nothing to do (caller may close the window).
    @discardableResult
    func handleEscape() -> Bool {
        switch interaction {
        case .editingText:
            cancelTextEdit()
            return true
        case .drawing, .croppingDrag, .croppingDraft:
            interaction = .idle
            return true
        case .draggingAnnotation, .resizing:
            // Abort the drag: restore the pre-gesture state.
            if let snapshot = preGestureSnapshot {
                document = snapshot
            }
            preGestureSnapshot = nil
            interaction = .idle
            return true
        case .idle:
            if selectedID != nil {
                selectedID = nil
                return true
            }
            return false
        }
    }

    func handleReturn() {
        switch interaction {
        case .croppingDraft:
            applyCropDraft()
        case .editingText:
            commitTextEdit()
        default:
            break
        }
    }

    // MARK: - Crop

    func applyCropDraft() {
        guard case .croppingDraft(let rect) = interaction else { return }
        beginGesture()
        document.applyCrop(rect)
        endGesture()
        blurCache.invalidateAll()
        interaction = .idle
        selectedID = nil
        tool = .select
    }

    // MARK: - Text editing

    private func startTextEdit(id: UUID) {
        guard let annotation = document.annotation(with: id),
              case .text(let payload) = annotation.kind else { return }
        beginGesture()
        draftText = payload.string
        interaction = .editingText(id: id)
    }

    func commitTextEdit() {
        guard case .editingText(let id) = interaction,
              let index = document.index(of: id),
              case .text(var payload) = document.annotations[index].kind else {
            interaction = .idle
            return
        }
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            document.annotations.remove(at: index)
            selectedID = nil
        } else {
            payload.string = text
            document.annotations[index].kind = .text(payload)
        }
        interaction = .idle
        endGesture()
    }

    func cancelTextEdit() {
        guard case .editingText = interaction else { return }
        if let snapshot = preGestureSnapshot {
            document = snapshot
            if let id = selectedID, document.annotation(with: id) == nil {
                selectedID = nil
            }
        }
        preGestureSnapshot = nil
        interaction = .idle
    }

    // MARK: - Paste replaces the image (undoable)

    func replaceDocument(with base: BaseImage) {
        if case .editingText = interaction {
            cancelTextEdit()
        }
        beginGesture()
        document = Document(base: base)
        endGesture()
        selectedID = nil
        interaction = .idle
        blurCache.invalidateAll()
    }

    // MARK: - Export

    /// Commit any in-flight edit so exports reflect what the user sees.
    func prepareForExport() {
        if case .editingText = interaction {
            commitTextEdit()
        }
    }

    func renderPNG() -> Data? {
        prepareForExport()
        return ExportService.renderPNG(document, blurCache: blurCache)
    }

    func renderImage() -> CGImage? {
        prepareForExport()
        return ExportService.renderFullResolution(document, blurCache: blurCache)
    }
}
