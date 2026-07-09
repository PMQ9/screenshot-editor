import SwiftUI

/// The canvas: draws the document through the SAME Core Graphics renderer the
/// export uses (inside `withCGContext`), converts gestures to image-pixel
/// space through CanvasTransform, and overlays view-space chrome (selection
/// handles, crop marquee) plus the live text-editing field.
struct EditorCanvasView: View {
    @Bindable var viewModel: EditorViewModel

    @State private var dragActive = false
    @State private var dragMoved = false
    @FocusState private var canvasFocused: Bool
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            switch viewModel.zoomMode {
            case .fit:
                content(transform: CanvasTransform.fit(
                    pixelSize: viewModel.document.base.pixelSize,
                    in: geometry.size,
                    pixelsPerPoint: viewModel.pixelsPerPoint))
            case .actualSize:
                ScrollView([.horizontal, .vertical]) {
                    content(transform: .actualSize(pixelsPerPoint: viewModel.pixelsPerPoint))
                        .frame(
                            width: viewModel.document.base.pixelSize.width / viewModel.pixelsPerPoint,
                            height: viewModel.document.base.pixelSize.height / viewModel.pixelsPerPoint)
                }
            }
        }
    }

    private func content(transform: CanvasTransform) -> some View {
        // Read observable state in the view body so SwiftUI re-renders the
        // Canvas when any of it changes; the closure then uses these values.
        let document = viewModel.document
        let draft = viewModel.draftAnnotation
        let cropRect = viewModel.cropDraftRect
        let selected = viewModel.selectedID.flatMap { document.annotation(with: $0) }
        let editingID = viewModel.editingTextID

        return ZStack(alignment: .topLeading) {
            Canvas { context, size in
                context.withCGContext { cg in
                    cg.saveGState()
                    cg.translateBy(x: transform.offset.x, y: transform.offset.y)
                    cg.scaleBy(x: transform.scale, y: transform.scale)
                    // Export clips at the bitmap bounds; clip the screen the
                    // same way so overhanging ink can't silently diverge.
                    cg.clip(to: document.base.pixelRect)
                    cg.interpolationQuality = .high
                    AnnotationRenderer.draw(document, into: cg,
                                            blurCache: viewModel.blurCache,
                                            excluding: editingID)
                    if let draft {
                        if case .blur(let rect, _) = draft.kind {
                            // Cheap placeholder while dragging; the real patch
                            // is computed once on commit.
                            cg.setFillColor(CGColor(gray: 0.2, alpha: 0.45))
                            cg.fill(rect)
                        } else {
                            AnnotationRenderer.draw(draft, into: cg)
                        }
                    }
                    cg.restoreGState()
                }
                drawChrome(context, size: size, transform: transform,
                           selected: selected, editingID: editingID, cropRect: cropRect)
            }
            .gesture(dragGesture(transform: transform))
            .onTapGesture(count: 2) { location in
                viewModel.doubleClick(at: transform.toImage(location),
                                      tolerance: transform.imageTolerance(viewPoints: 6))
            }

            textEditingOverlay(transform: transform)
        }
        .focusable()
        .focused($canvasFocused)
        .onKeyPress(phases: [.down, .repeat]) { press in
            handleKey(press)
        }
        .onAppear { canvasFocused = true }
        .onChange(of: viewModel.editingTextID) { _, editing in
            if editing == nil {
                canvasFocused = true
            }
        }
    }

    // MARK: - Gestures

    private func dragGesture(transform: CanvasTransform) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !dragActive {
                    dragActive = true
                    dragMoved = false
                    viewModel.pointerDown(
                        at: transform.toImage(value.startLocation),
                        tolerance: transform.imageTolerance(viewPoints: 6),
                        handleTolerance: transform.imageTolerance(viewPoints: 8))
                }
                // 2-pt slop so a jittery click doesn't become a real move
                // (and a junk undo entry).
                let travel = hypot(value.location.x - value.startLocation.x,
                                   value.location.y - value.startLocation.y)
                if dragMoved || travel > 2 {
                    dragMoved = true
                    viewModel.pointerDragged(to: transform.toImage(value.location))
                }
            }
            .onEnded { value in
                dragActive = false
                viewModel.pointerUp(at: transform.toImage(value.location))
            }
    }

    // MARK: - Keyboard

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .escape:
            return viewModel.handleEscape() ? .handled : .ignored
        case .return:
            viewModel.handleReturn()
            return .handled
        case .delete, .deleteForward:
            viewModel.deleteSelection()
            return .handled
        case .upArrow:
            viewModel.nudgeSelection(dx: 0, dy: -1)
            return .handled
        case .downArrow:
            viewModel.nudgeSelection(dx: 0, dy: 1)
            return .handled
        case .leftArrow:
            viewModel.nudgeSelection(dx: -1, dy: 0)
            return .handled
        case .rightArrow:
            viewModel.nudgeSelection(dx: 1, dy: 0)
            return .handled
        default:
            break
        }
        guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else {
            return .ignored
        }
        if let tool = Self.toolKeys[press.characters.lowercased()] {
            viewModel.tool = tool
            return .handled
        }
        return .ignored
    }

    private static let toolKeys: [String: Tool] = [
        "v": .select, "r": .rectangle, "o": .ellipse, "a": .arrow,
        "p": .pen, "h": .highlighter, "t": .text, "n": .badge,
        "b": .blur, "x": .pixelate, "c": .crop,
    ]

    // MARK: - View-space chrome (crisp at any zoom)

    private func drawChrome(_ context: GraphicsContext, size: CGSize,
                            transform: CanvasTransform, selected: Annotation?,
                            editingID: UUID?, cropRect: CGRect?) {
        if let selected, selected.id != editingID {
            let bounds = transform.toView(selected.bounds).insetBy(dx: -3, dy: -3)
            context.stroke(Path(bounds), with: .color(.white.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 3))
            context.stroke(Path(bounds), with: .color(.accentColor),
                           style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            for (_, position) in selected.handles {
                let p = transform.toView(position)
                let handleRect = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: handleRect), with: .color(.white))
                context.stroke(Path(ellipseIn: handleRect), with: .color(.accentColor),
                               style: StrokeStyle(lineWidth: 1.5))
            }
        }

        if let cropRect {
            let viewRect = transform.toView(cropRect)
            var dimmed = Path(CGRect(origin: .zero, size: size))
            dimmed.addRect(viewRect)
            context.fill(dimmed, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
            context.stroke(Path(viewRect), with: .color(.white),
                           style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            let hint = Text("Return to crop · Esc to cancel")
                .font(.caption).foregroundStyle(.white)
            context.draw(hint, at: CGPoint(x: viewRect.midX,
                                           y: max(viewRect.minY - 14, 10)))
        }
    }

    // MARK: - Text editing overlay

    @ViewBuilder
    private func textEditingOverlay(transform: CanvasTransform) -> some View {
        if let id = viewModel.editingTextID,
           let annotation = viewModel.document.annotation(with: id),
           case .text(let payload) = annotation.kind {
            let position = transform.toView(payload.origin)
            TextField("Text", text: $viewModel.draftText)
                .textFieldStyle(.plain)
                .font(.system(size: payload.fontSizePx * transform.scale, weight: .semibold))
                .foregroundStyle(Color(cgColor: annotation.style.color.cgColor))
                .background(Color.black.opacity(0.2))
                .fixedSize()
                .frame(minWidth: 40, alignment: .topLeading)
                .offset(x: position.x, y: position.y)
                .focused($textFieldFocused)
                .onSubmit { viewModel.commitTextEdit() }
                .onExitCommand { viewModel.cancelTextEdit() }
                .onAppear { textFieldFocused = true }
        }
    }
}
