import SwiftUI

struct ToolbarView: View {
    @Bindable var viewModel: EditorViewModel

    private static let tools: [(tool: Tool, symbol: String, help: String)] = [
        (.select, "cursorarrow", "Select (V)"),
        (.rectangle, "rectangle", "Rectangle (R)"),
        (.ellipse, "circle", "Ellipse (O)"),
        (.arrow, "arrow.up.right", "Arrow (A)"),
        (.pen, "scribble", "Pen (P)"),
        (.highlighter, "highlighter", "Highlighter (H)"),
        (.text, "textformat", "Text (T)"),
        (.badge, "1.circle", "Number badge (N)"),
        (.blur, "drop.halffull", "Blur (B)"),
        (.pixelate, "squareshape.split.3x3", "Pixelate (X)"),
        (.crop, "crop", "Crop (C)"),
    ]

    private static let palette: [RGBAColor] = [
        .red, .orange, .yellow, .green, .blue, .black, .white,
    ]

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(Self.tools, id: \.tool) { entry in
                    toolButton(entry.tool, symbol: entry.symbol, help: entry.help)
                }
            }

            Divider().frame(height: 22)

            HStack(spacing: 5) {
                ForEach(Self.palette, id: \.self) { color in
                    colorSwatch(color)
                }
            }

            if viewModel.tool == .text || selectedIsText {
                Divider().frame(height: 22)
                fontSizePicker
            } else {
                Divider().frame(height: 22)
                strokeWidthPicker
            }

            Spacer(minLength: 8)

            Button {
                viewModel.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .help("Undo (⌘Z)")
            .disabled(!viewModel.canUndo)

            Button {
                viewModel.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .help("Redo (⇧⌘Z)")
            .disabled(!viewModel.canRedo)

            Divider().frame(height: 22)

            zoomToggle

            Divider().frame(height: 22)

            Image(systemName: "hand.draw")
                .help("Drag the annotated image into another app")
                .onDrag {
                    if let url = ImageExporter.writeTempPNG(viewModel) {
                        return NSItemProvider(contentsOf: url) ?? NSItemProvider()
                    }
                    return NSItemProvider()
                }

            // No .keyboardShortcut here: ⌘C routes through the Edit menu and
            // responder chain, so copy still works inside the text editor.
            Button("Copy") {
                ImageExporter.copyToClipboard(viewModel)
            }
            .help("Copy the annotated image to the clipboard (⌘C)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var selectedIsText: Bool {
        guard let id = viewModel.selectedID,
              let annotation = viewModel.document.annotation(with: id),
              case .text = annotation.kind else { return false }
        return true
    }

    private func toolButton(_ tool: Tool, symbol: String, help: String) -> some View {
        Button {
            viewModel.tool = tool
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(viewModel.tool == tool
                              ? Color.accentColor.opacity(0.25) : .clear))
        }
        .help(help)
    }

    private func colorSwatch(_ color: RGBAColor) -> some View {
        Button {
            viewModel.strokeColor = color
        } label: {
            Circle()
                .fill(Color(cgColor: color.cgColor))
                .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentColor,
                                      lineWidth: viewModel.strokeColor == color ? 2 : 0)
                        .padding(-2))
                .frame(width: 14, height: 14)
        }
    }

    private var strokeWidthPicker: some View {
        HStack(spacing: 4) {
            ForEach([2, 3, 5], id: \.self) { (width: CGFloat) in
                Button {
                    viewModel.strokeWidthPt = width
                } label: {
                    Circle()
                        .fill(.primary)
                        .frame(width: width * 2 + 2, height: width * 2 + 2)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle().fill(viewModel.strokeWidthPt == width
                                          ? Color.accentColor.opacity(0.25) : .clear))
                }
                .help("\(Int(width)) pt stroke")
            }
        }
    }

    private var fontSizePicker: some View {
        HStack(spacing: 4) {
            ForEach([(14, "S"), (20, "M"), (28, "L")], id: \.0) { (size: Int, label: String) in
                Button {
                    viewModel.fontSizePt = CGFloat(size)
                } label: {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(viewModel.fontSizePt == CGFloat(size)
                                      ? Color.accentColor.opacity(0.25) : .clear))
                }
                .help("\(size) pt text")
            }
        }
    }

    private var zoomToggle: some View {
        HStack(spacing: 2) {
            Button("Fit") {
                viewModel.zoomMode = .fit
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(viewModel.zoomMode == .fit
                          ? Color.accentColor.opacity(0.25) : .clear))
            .help("Zoom to fit (⌘0)")
            Button("100%") {
                viewModel.zoomMode = .actualSize
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(viewModel.zoomMode == .actualSize
                          ? Color.accentColor.opacity(0.25) : .clear))
            .help("Actual size (⌘1)")
        }
        .font(.caption)
    }
}
