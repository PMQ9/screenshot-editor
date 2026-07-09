import SwiftUI

/// Contextual property inspector. When a shape is selected it edits that shape;
/// with nothing selected it edits the "next shape" defaults for the active tool.
/// All controls funnel through EditorViewModel's style state / mutateSelected so
/// edits are per-shape and undoable (sliders coalesce to one undo entry).
struct InspectorView: View {
    @Bindable var viewModel: EditorViewModel

    private static let palette: [RGBAColor] = [
        .red, .orange, .yellow, .green, .blue, .black, .white,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(contextTitle).font(.headline)
                Spacer()
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    let c = caps
                    if c.color { colorSection }
                    if c.stroke { strokeSection }
                    if c.corner { cornerSection }
                    if c.fill { fillSection }
                    if c.redaction { redactionSection }
                    if c.arrow { arrowSection }
                    if c.font { textSection }
                    if selectedAnnotation != nil { geometrySection }
                    if selectedAnnotation == nil {
                        Text("Select a shape to edit it, or pick a tool to set defaults for the next shape.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 244)
        .background(.bar)
    }

    // MARK: - Context

    private var selectedAnnotation: Annotation? {
        viewModel.selectedID.flatMap { viewModel.document.annotation(with: $0) }
    }

    private var contextTitle: String {
        if let a = selectedAnnotation { return kindTitle(a.kind) }
        switch viewModel.tool {
        case .select, .crop: return "Defaults"
        case .rectangle: return "New Rectangle"
        case .ellipse: return "New Ellipse"
        case .arrow: return "New Arrow"
        case .pen: return "New Pen"
        case .highlighter: return "New Highlighter"
        case .text: return "New Text"
        case .badge: return "New Badge"
        case .blur: return "New Blur"
        case .pixelate: return "New Pixelate"
        }
    }

    private func kindTitle(_ kind: AnnotationKind) -> String {
        switch kind {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .arrow: return "Arrow"
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .text: return "Text"
        case .badge: return "Badge"
        case .blur(_, let mode):
            if case .pixelate = mode { return "Pixelate" }
            return "Blur"
        }
    }

    private struct Caps {
        var color = false, stroke = false, fill = false, corner = false
        var font = false, redaction = false, arrow = false
    }

    /// Which sections apply to the current context (selected shape, else tool).
    private var caps: Caps {
        if let a = selectedAnnotation { return caps(forKind: a.kind) }
        switch viewModel.tool {
        case .rectangle: return caps(forKind: .rectangle(rect: .zero))
        case .ellipse: return caps(forKind: .ellipse(rect: .zero))
        case .arrow: return caps(forKind: .arrow(start: .zero, end: .zero))
        case .pen: return caps(forKind: .pen(points: []))
        case .highlighter: return caps(forKind: .highlighter(points: []))
        case .text: return caps(forKind: .text(TextPayload(string: "", origin: .zero, fontSizePx: 0)))
        case .badge: return caps(forKind: .badge(center: .zero, number: 0, radiusPx: 0))
        case .blur: return caps(forKind: .blur(rect: .zero, mode: .gaussian(radiusPx: 0)))
        case .pixelate: return caps(forKind: .blur(rect: .zero, mode: .pixelate(blockPx: 0)))
        case .select, .crop: return Caps(color: true, stroke: true)
        }
    }

    private func caps(forKind kind: AnnotationKind) -> Caps {
        switch kind {
        case .rectangle: return Caps(color: true, stroke: true, fill: true, corner: true)
        case .ellipse: return Caps(color: true, stroke: true, fill: true)
        case .arrow: return Caps(color: true, stroke: true, arrow: true)
        case .pen, .highlighter: return Caps(color: true, stroke: true)
        case .text: return Caps(color: true, font: true)
        case .badge: return Caps(color: true)
        case .blur: return Caps(redaction: true)
        }
    }

    // MARK: - Sections

    private var colorSection: some View {
        section("Color") {
            HStack(spacing: 6) {
                ForEach(Self.palette, id: \.self) { swatch($0) }
            }
            ColorPicker("Custom", selection: colorBinding(\.strokeColor), supportsOpacity: true)
                .font(.caption)
        }
    }

    private var strokeSection: some View {
        section("Stroke") {
            sliderRow("Width", value: $viewModel.strokeWidthPt, range: 0...40)
        }
    }

    private var cornerSection: some View {
        section("Corners") {
            sliderRow("Radius", value: $viewModel.cornerRadiusPt, range: 0...120)
        }
    }

    private var fillSection: some View {
        section("Fill") {
            Toggle("Fill shape", isOn: fillToggleBinding)
                .toggleStyle(.switch).controlSize(.mini).font(.caption)
            if viewModel.fillEnabled {
                ColorPicker("Fill color", selection: colorBinding(\.fillColor),
                            supportsOpacity: true).font(.caption)
            }
        }
    }

    private var redactionSection: some View {
        section("Redaction") {
            Picker("", selection: $viewModel.redactionMode) {
                Text("Blur").tag(RedactionKind.gaussian)
                Text("Pixelate").tag(RedactionKind.pixelate)
            }
            .pickerStyle(.segmented).labelsHidden()
            if viewModel.redactionMode == .gaussian {
                sliderRow("Blur radius", value: $viewModel.blurRadiusPt, range: 1...80)
            } else {
                sliderRow("Block size", value: $viewModel.pixelateBlockPt, range: 2...100)
            }
        }
    }

    private var arrowSection: some View {
        section("Arrow head") {
            sliderRow("Size", value: $viewModel.arrowHeadScale, range: 0.3...3,
                      step: 0.1, format: "%.1f", suffix: "×")
        }
    }

    private var textSection: some View {
        section("Text") {
            sliderRow("Font size", value: $viewModel.fontSizePt, range: 8...140)
        }
    }

    private enum FrameField { case x, y, w, h }

    private var geometrySection: some View {
        section("Geometry") {
            HStack(spacing: 6) {
                numField("X", .x)
                numField("Y", .y)
            }
            if geometryResizable {
                HStack(spacing: 6) {
                    numField("W", .w)
                    numField("H", .h)
                }
            }
            if geometryRotatable { rotationRow }
            HStack(spacing: 4) {
                zButton("square.3.layers.3d.top.filled", "Bring to front") {
                    viewModel.bringSelectionToFront() }
                zButton("chevron.up", "Bring forward") {
                    viewModel.bringSelectionForward() }
                zButton("chevron.down", "Send backward") {
                    viewModel.sendSelectionBackward() }
                zButton("square.3.layers.3d.bottom.filled", "Send to back") {
                    viewModel.sendSelectionToBack() }
            }
        }
    }

    private var geometryResizable: Bool {
        guard let a = selectedAnnotation else { return false }
        switch a.kind {
        case .rectangle, .ellipse, .blur: return true
        default: return false
        }
    }

    private var geometryRotatable: Bool {
        selectedAnnotation?.isRotatable ?? false
    }

    private var rotationRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Rotation").font(.caption)
                Spacer()
                Text(String(format: "%.0f°", rotationDegrees.wrappedValue))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: rotationDegrees, in: -180...180, step: 1) { editing in
                if editing { viewModel.beginInteractiveEdit() }
                else { viewModel.endInteractiveEdit() }
            }
        }
    }

    private var rotationDegrees: Binding<CGFloat> {
        Binding(
            get: { (selectedAnnotation?.rotation ?? 0) * 180 / .pi },
            set: { deg in viewModel.mutateSelected { $0.rotation = deg * .pi / 180 } })
    }

    // MARK: - Reusable controls

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func sliderRow(_ title: String, value: Binding<CGFloat>,
                           range: ClosedRange<CGFloat>, step: CGFloat = 1,
                           format: String = "%.0f", suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format: format, value.wrappedValue) + suffix)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step) { editing in
                if editing { viewModel.beginInteractiveEdit() }
                else { viewModel.endInteractiveEdit() }
            }
        }
    }

    private func numField(_ label: String, _ field: FrameField) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .frame(width: 12, alignment: .leading)
            TextField("", value: frameBinding(field),
                      format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospacedDigit())
                .frame(width: 62)
        }
    }

    private func zButton(_ symbol: String, _ help: String,
                         _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(help)
    }

    private func swatch(_ color: RGBAColor) -> some View {
        Button {
            viewModel.strokeColor = color
        } label: {
            Circle()
                .fill(color.swiftUIColor)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))
                .overlay(Circle()
                    .strokeBorder(Color.accentColor,
                                  lineWidth: viewModel.strokeColor == color ? 2 : 0)
                    .padding(-2))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bindings

    private func frameBinding(_ field: FrameField) -> Binding<Double> {
        Binding(
            get: {
                guard let f = viewModel.selectedFrame else { return 0 }
                switch field {
                case .x: return Double(f.minX)
                case .y: return Double(f.minY)
                case .w: return Double(f.width)
                case .h: return Double(f.height)
                }
            },
            set: { v in
                let c = CGFloat(v)
                switch field {
                case .x: viewModel.updateSelectedFrame(x: c)
                case .y: viewModel.updateSelectedFrame(y: c)
                case .w: viewModel.updateSelectedFrame(width: c)
                case .h: viewModel.updateSelectedFrame(height: c)
                }
            })
    }

    private func colorBinding(_ keyPath: ReferenceWritableKeyPath<EditorViewModel, RGBAColor>)
        -> Binding<Color> {
        Binding(get: { viewModel[keyPath: keyPath].swiftUIColor },
                set: { viewModel[keyPath: keyPath] = RGBAColor($0) })
    }

    /// Toggling fill on seeds a sensible fill color (stroke color, low opacity)
    /// the first time, and coalesces the color+flag change into one undo entry.
    private var fillToggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.fillEnabled },
            set: { on in
                viewModel.beginInteractiveEdit()
                if on, viewModel.fillColor == RGBAColor(r: 1, g: 1, b: 1, a: 0.25) {
                    var seeded = viewModel.strokeColor
                    seeded.a = 0.3
                    viewModel.fillColor = seeded
                }
                viewModel.fillEnabled = on
                viewModel.endInteractiveEdit()
            })
    }
}
