import AppKit
import Observation

enum Tool: CaseIterable, Equatable, Sendable {
    case select, rectangle, ellipse, arrow, pen, highlighter, text, badge, blur, pixelate, crop
}

enum ZoomMode: Equatable, Sendable {
    case fit
    case actualSize   // 1 image pixel = 1 device pixel
}

/// UI-level selector for a redaction region's flavor (maps to `RedactionMode`).
enum RedactionKind: Equatable, Hashable, Sendable { case gaussian, pixelate }

enum Interaction: Equatable {
    case idle
    case drawing(draft: Annotation, anchor: CGPoint)
    case draggingAnnotation(id: UUID, lastPoint: CGPoint)
    case resizing(id: UUID, handle: Handle, original: Annotation)
    case rotating(id: UUID, original: Annotation)
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
            case .idle, .draggingAnnotation, .resizing, .rotating:
                break
            }
        }
    }
    var interaction: Interaction = .idle
    var selectedID: UUID? {
        didSet {
            guard selectedID != oldValue else { return }
            syncControlsFromSelection()
        }
    }
    var zoomMode: ZoomMode = .fit
    var draftText: String = ""

    // Style presets are point-denominated in the UI, pixel-denominated in the
    // model. Each doubles as the "next shape" default AND live-applies to the
    // current selection (via applyStyleToSelection). `isSyncing` suppresses that
    // apply while we copy values FROM a newly selected shape INTO these.
    var strokeColor: RGBAColor = .red { didSet { applyStyleToSelection() } }
    var strokeWidthPt: CGFloat = 3 { didSet { applyStyleToSelection() } }
    var fontSizePt: CGFloat = 20 { didSet { applyStyleToSelection() } }

    // Fill (rectangle / ellipse).
    var fillEnabled: Bool = false { didSet { applyStyleToSelection() } }
    var fillColor: RGBAColor = RGBAColor(r: 1, g: 1, b: 1, a: 0.25) {
        didSet { applyStyleToSelection() }
    }
    var cornerRadiusPt: CGFloat = 0 { didSet { applyStyleToSelection() } }

    // Arrow head size multiplier.
    var arrowHeadScale: CGFloat = 1 { didSet { applyStyleToSelection() } }

    // Redaction (blur / pixelate): `redactionMode` picks which intensity applies
    // to a selected region and lets the inspector convert between the two.
    var redactionMode: RedactionKind = .gaussian { didSet { applyStyleToSelection() } }
    var blurRadiusPt: CGFloat = 8 { didSet { applyStyleToSelection() } }
    var pixelateBlockPt: CGFloat = 12 { didSet { applyStyleToSelection() } }

    /// Inspector panel visibility (toolbar toggle).
    var showInspector: Bool = true

    private var isSyncing = false
    private var interactiveEditDepth = 0

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

    /// Abort any in-flight pointer gesture, restoring the pre-gesture state.
    /// Returns true if something was in flight (the caller should stop there:
    /// the first ⌘Z aborts the gesture, the next one pops history).
    private func abortInFlightGesture() -> Bool {
        switch interaction {
        case .drawing, .croppingDrag:
            interaction = .idle
            return true
        case .draggingAnnotation, .resizing, .rotating:
            if let snapshot = preGestureSnapshot {
                document = snapshot
            }
            preGestureSnapshot = nil
            interaction = .idle
            return true
        case .idle, .editingText, .croppingDraft:
            return false
        }
    }

    func undo() {
        if case .editingText = interaction {
            // ⌘Z mid-edit cancels the edit only; history stays intact.
            cancelTextEdit()
            return
        }
        if abortInFlightGesture() { return }
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
        didRestoreHistory()
    }

    func redo() {
        if case .editingText = interaction { return }
        if abortInFlightGesture() { return }
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

        // Direct manipulation of the CURRENTLY SELECTED shape works from any
        // tool, so a shape you just drew is immediately movable/resizable
        // without first switching to the Select tool. Only the selected shape
        // is grabbable this way; clicking elsewhere still draws a new shape.
        // (Crop has its own marquee and is excluded.)
        if tool != .crop, let id = selectedID,
           let selected = document.annotation(with: id) {
            if let grab = beginHandleGesture(at: p, id: id, selected: selected,
                                             tolerance: handleTolerance) {
                interaction = grab
                return
            }
            if selected.hitTest(p, tolerance: tolerance) {
                beginGesture()
                interaction = .draggingAnnotation(id: id, lastPoint: p)
                return
            }
        }

        switch tool {
        case .select:
            // The selected shape (if any) was already handled above. Here we
            // pick up a DIFFERENT shape under the cursor, or deselect.
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

        case .rotating(let id, let original):
            guard let index = document.index(of: id) else {
                interaction = .idle
                return
            }
            let center = original.rotationCenter
            // The rotate handle sits straight up from center; align it to p.
            var angle = atan2(p.y - center.y, p.x - center.x) + .pi / 2
            if NSEvent.modifierFlags.contains(.shift) {
                let step = CGFloat.pi / 12   // snap to 15°
                angle = (angle / step).rounded() * step
            }
            document.annotations[index].rotation = angle

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

        case .draggingAnnotation, .resizing, .rotating:
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
        case .blur: return .blur(rect: zero, mode: .gaussian(radiusPx: blurRadiusPt * pixelsPerPoint))
        case .pixelate: return .blur(rect: zero, mode: .pixelate(blockPx: pixelateBlockPt * pixelsPerPoint))
        default: return .rectangle(rect: zero)
        }
    }

    private var currentStyle: AnnotationStyle {
        AnnotationStyle(color: strokeColor, strokeWidthPx: strokeWidthPx,
                        filled: fillEnabled, fillColor: fillColor,
                        cornerRadiusPx: cornerRadiusPt * pixelsPerPoint,
                        arrowHeadScale: arrowHeadScale)
    }

    private func isCommittable(_ draft: Annotation, anchor: CGPoint, end: CGPoint) -> Bool {
        // Fully outside the image: invisible in export, so don't commit.
        guard draft.bounds.intersects(document.base.pixelRect) else { return false }
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

    /// If `p` is on one of the selected shape's handles, snapshot for undo and
    /// return the interaction to enter. Returns nil when no handle is hit.
    private func beginHandleGesture(at p: CGPoint, id: UUID, selected: Annotation,
                                    tolerance: CGFloat) -> Interaction? {
        guard let handle = selectedHandleHit(at: p, tolerance: tolerance) else { return nil }
        beginGesture()
        return handle == .rotate
            ? .rotating(id: id, original: selected)
            : .resizing(id: id, handle: handle, original: selected)
    }

    // MARK: - Selection edits

    /// Copy the selected shape's properties INTO the control state so the
    /// toolbar/inspector reflect what's selected. Guarded by `isSyncing` so the
    /// resulting `didSet`s don't write the values straight back.
    private func syncControlsFromSelection() {
        guard let id = selectedID, let a = document.annotation(with: id) else { return }
        isSyncing = true
        defer { isSyncing = false }
        strokeColor = a.style.color
        strokeWidthPt = a.style.strokeWidthPx / pixelsPerPoint
        fillEnabled = a.style.filled
        fillColor = a.style.fillColor
        cornerRadiusPt = a.style.cornerRadiusPx / pixelsPerPoint
        arrowHeadScale = a.style.arrowHeadScale
        switch a.kind {
        case .text(let payload):
            fontSizePt = payload.fontSizePx / pixelsPerPoint
        case .blur(_, let mode):
            switch mode {
            case .gaussian(let r): redactionMode = .gaussian; blurRadiusPt = r / pixelsPerPoint
            case .pixelate(let b): redactionMode = .pixelate; pixelateBlockPt = b / pixelsPerPoint
            }
        default:
            break
        }
    }

    private func applyStyleToSelection() {
        guard !isSyncing else { return }
        guard let id = selectedID, let index = document.index(of: id) else { return }
        if case .editingText(let editingID) = interaction {
            // Mid-edit style change: the edit's own gesture snapshot covers it;
            // taking another would clobber that snapshot and leak a ghost
            // annotation on cancel.
            guard editingID == id else { return }
            applyCurrentStyle(at: index)
            return
        }
        guard case .idle = interaction else { return }
        if interactiveEditDepth > 0 {
            // A slider drag holds the undo bracket; just mutate.
            applyCurrentStyle(at: index)
        } else {
            beginGesture()
            applyCurrentStyle(at: index)
            endGesture()
        }
    }

    private func applyCurrentStyle(at index: Int) {
        var style = document.annotations[index].style
        style.color = strokeColor
        style.strokeWidthPx = strokeWidthPx
        style.filled = fillEnabled
        style.fillColor = fillColor
        style.cornerRadiusPx = cornerRadiusPt * pixelsPerPoint
        style.arrowHeadScale = arrowHeadScale
        document.annotations[index].style = style
        switch document.annotations[index].kind {
        case .text(var payload):
            payload.fontSizePx = fontSizePt * pixelsPerPoint
            document.annotations[index].kind = .text(payload)
        case .blur(let rect, _):
            document.annotations[index].kind = .blur(rect: rect, mode: currentRedactionMode)
        default:
            break
        }
    }

    /// The `RedactionMode` implied by the current inspector selection.
    private var currentRedactionMode: RedactionMode {
        switch redactionMode {
        case .gaussian: return .gaussian(radiusPx: blurRadiusPt * pixelsPerPoint)
        case .pixelate: return .pixelate(blockPx: pixelateBlockPt * pixelsPerPoint)
        }
    }

    // MARK: - Interactive edits (Inspector direct-manipulation controls)

    /// Open a single undo bracket spanning a continuous edit (slider drag).
    /// Style `didSet`s and `mutateSelected` mutate inside it without pushing
    /// per-tick history; `endInteractiveEdit` pushes one entry.
    func beginInteractiveEdit() {
        guard case .idle = interaction else { return }
        if interactiveEditDepth == 0 { beginGesture() }
        interactiveEditDepth += 1
    }

    func endInteractiveEdit() {
        guard interactiveEditDepth > 0 else { return }
        interactiveEditDepth -= 1
        if interactiveEditDepth == 0 { endGesture() }
    }

    /// Mutate the selected annotation in place. Wraps itself in a one-shot undo
    /// gesture unless a `beginInteractiveEdit` bracket is already open.
    func mutateSelected(_ body: (inout Annotation) -> Void) {
        guard case .idle = interaction else { return }
        guard let id = selectedID, let index = document.index(of: id) else { return }
        let bracketed = interactiveEditDepth > 0
        if !bracketed { beginGesture() }
        body(&document.annotations[index])
        if !bracketed { endGesture() }
    }

    // MARK: - Numeric geometry (Inspector)

    /// Bounding rect of the selection in image pixels (nil if nothing selected).
    var selectedFrame: CGRect? {
        selectedID.flatMap { document.annotation(with: $0)?.bounds }
    }

    /// Set position/size numerically (image pixels). Rect-based kinds take the
    /// new rect directly (preserving rotation); other kinds translate to the new
    /// origin and ignore width/height. One undo entry per call.
    func updateSelectedFrame(x: CGFloat? = nil, y: CGFloat? = nil,
                             width: CGFloat? = nil, height: CGFloat? = nil) {
        guard case .idle = interaction else { return }
        guard let id = selectedID, let index = document.index(of: id) else { return }
        let b = document.annotations[index].bounds
        let nx = x ?? b.minX, ny = y ?? b.minY
        let nw = max(width ?? b.width, 1), nh = max(height ?? b.height, 1)
        let newRect = CGRect(x: nx, y: ny, width: nw, height: nh)
        beginGesture()
        switch document.annotations[index].kind {
        case .rectangle:
            document.annotations[index].kind = .rectangle(rect: newRect)
        case .ellipse:
            document.annotations[index].kind = .ellipse(rect: newRect)
        case .blur(_, let mode):
            document.annotations[index].kind = .blur(rect: newRect, mode: mode)
        default:
            document.annotations[index].translate(
                by: CGPoint(x: nx - b.minX, y: ny - b.minY))
        }
        endGesture()
    }

    // MARK: - Z-order (Inspector)

    func bringSelectionToFront() {
        reorderSelection { arr, i in arr.append(arr.remove(at: i)) }
    }
    func sendSelectionToBack() {
        reorderSelection { arr, i in arr.insert(arr.remove(at: i), at: 0) }
    }
    func bringSelectionForward() {
        reorderSelection { arr, i in if i < arr.count - 1 { arr.swapAt(i, i + 1) } }
    }
    func sendSelectionBackward() {
        reorderSelection { arr, i in if i > 0 { arr.swapAt(i, i - 1) } }
    }

    private func reorderSelection(_ move: (inout [Annotation], Int) -> Void) {
        guard case .idle = interaction else { return }
        guard let id = selectedID, let index = document.index(of: id) else { return }
        beginGesture()
        move(&document.annotations, index)
        endGesture()
    }

    func deleteSelection() {
        if case .editingText = interaction {
            cancelTextEdit()
            return
        }
        // During a drag/resize the snapshot slot is occupied; mutating history
        // here would corrupt it.
        guard case .idle = interaction else { return }
        guard let id = selectedID, let index = document.index(of: id) else { return }
        beginGesture()
        document.annotations.remove(at: index)
        endGesture()
        selectedID = nil
        blurCache.prune(keeping: Set(document.annotations.map(\.id)))
    }

    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard case .idle = interaction else { return }
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
        case .draggingAnnotation, .resizing, .rotating:
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
