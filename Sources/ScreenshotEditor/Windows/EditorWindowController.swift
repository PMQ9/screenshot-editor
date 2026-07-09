import AppKit
import SwiftUI

/// One editor window per image. Also the responder-chain target for the
/// main menu's Undo/Redo/Copy/Paste/Save/zoom items.
final class EditorWindowController: NSWindowController, NSMenuItemValidation {
    let viewModel: EditorViewModel

    init(document: Document) {
        viewModel = EditorViewModel(document: document)

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Screenshot \(document.base.cgImage.width)×\(document.base.cgImage.height)"
        window.tabbingMode = .disallowed
        super.init(window: window)

        window.contentView = NSHostingView(rootView: EditorRootView(viewModel: viewModel))
        window.setContentSize(Self.initialContentSize(for: document))
        window.center()
        window.contentMinSize = CGSize(width: 480, height: 320)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    private static func initialContentSize(for document: Document) -> CGSize {
        let toolbarHeight: CGFloat = 52
        let pointSize = CGSize(
            width: document.base.pixelSize.width / document.base.pixelsPerPoint,
            height: document.base.pixelSize.height / document.base.pixelsPerPoint + toolbarHeight)
        let available = NSScreen.main?.visibleFrame.size
            ?? CGSize(width: 1440, height: 900)
        return CGSize(width: min(max(pointSize.width, 480), available.width * 0.9),
                      height: min(max(pointSize.height, 320), available.height * 0.9))
    }

    // MARK: - Menu actions (responder chain)

    @objc func copy(_ sender: Any?) {
        ImageExporter.copyToClipboard(viewModel)
    }

    @objc func paste(_ sender: Any?) {
        guard let base = PasteboardReader.readImage() else {
            NSSound.beep()
            return
        }
        viewModel.replaceDocument(with: base)
        window?.title = "Screenshot \(base.cgImage.width)×\(base.cgImage.height)"
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let window else { return }
        ImageExporter.save(viewModel, in: window)
    }

    @objc func undo(_ sender: Any?) {
        viewModel.undo()
    }

    @objc func redo(_ sender: Any?) {
        viewModel.redo()
    }

    @objc func delete(_ sender: Any?) {
        viewModel.deleteSelection()
    }

    @objc func zoomToFit(_ sender: Any?) {
        viewModel.zoomMode = .fit
    }

    @objc func zoomActualSize(_ sender: Any?) {
        viewModel.zoomMode = .actualSize
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)):
            return viewModel.canUndo
        case #selector(redo(_:)):
            return viewModel.canRedo
        case #selector(paste(_:)):
            return PasteboardReader.hasImage()
        case #selector(delete(_:)):
            return viewModel.selectedID != nil
        default:
            return true
        }
    }
}
