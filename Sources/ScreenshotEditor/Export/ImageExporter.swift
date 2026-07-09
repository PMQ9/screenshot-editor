import AppKit
import UniformTypeIdentifiers

enum ImageExporter {
    static func copyToClipboard(_ viewModel: EditorViewModel) {
        guard let image = viewModel.renderImage() else {
            NSSound.beep()
            return
        }
        PasteboardWriter.write(image: image, pixelsPerPoint: viewModel.pixelsPerPoint)
    }

    static func save(_ viewModel: EditorViewModel, in window: NSWindow) {
        guard let png = viewModel.renderPNG() else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = AppSettings.shared.saveFolderURL
        panel.nameFieldStringValue = defaultFileName()
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try png.write(to: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not save the image"
                alert.informativeText = error.localizedDescription
                alert.beginSheetModal(for: window)
            }
        }
    }

    /// Temp file for drag-out: Finder needs a file URL, and Slack/browsers
    /// accept one too.
    static func writeTempPNG(_ viewModel: EditorViewModel) -> URL? {
        guard let png = viewModel.renderPNG() else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotEditorDrags", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(defaultFileName())
        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    static func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Annotated \(formatter.string(from: Date())).png"
    }
}
