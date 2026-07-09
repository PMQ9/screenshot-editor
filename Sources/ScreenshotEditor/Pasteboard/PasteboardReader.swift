import AppKit
import UniformTypeIdentifiers

extension BaseImage {
    /// Imports an NSImage, preferring the largest bitmap representation, and
    /// derives pixelsPerPoint from actual pixels vs the image's point size —
    /// the single place the Retina 2x relationship is established.
    init?(nsImage: NSImage) {
        var best: CGImage?
        for rep in nsImage.representations {
            if let bitmap = rep as? NSBitmapImageRep, let cg = bitmap.cgImage,
               cg.width > (best?.width ?? 0) {
                best = cg
            }
        }
        let cgImage = best ?? nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        guard let cgImage, cgImage.width > 0, cgImage.height > 0 else { return nil }
        let ppp = nsImage.size.width > 0
            ? CGFloat(cgImage.width) / nsImage.size.width : 1
        self.init(cgImage: cgImage, pixelsPerPoint: max(1, ppp))
    }

    init?(data: Data) {
        guard let nsImage = NSImage(data: data) else { return nil }
        self.init(nsImage: nsImage)
    }
}

/// Content reads happen ONLY on explicit user actions (hotkey, menu click,
/// Cmd+V) or the auto-pop open — never from the background poller.
enum PasteboardReader {
    /// Narrow screenshot check (png/tiff) — used by the auto-pop monitor so
    /// copying image *files* in Finder doesn't pop the editor.
    static func hasImage(_ pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.availableType(from: [.png, .tiff]) != nil
    }

    /// Broad check mirroring everything readImage can open — used to validate ⌘V.
    static func canReadImage(_ pasteboard: NSPasteboard = .general) -> Bool {
        if hasImage(pasteboard) { return true }
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil) {
            return true
        }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: options)
    }

    static func readImage(from pasteboard: NSPasteboard = .general) -> BaseImage? {
        if let type = pasteboard.availableType(from: [.png, .tiff]),
           let data = pasteboard.data(forType: type),
           let base = BaseImage(data: data) {
            return base
        }
        // Covers promised/other image flavors.
        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           let image = images.first,
           let base = BaseImage(nsImage: image) {
            return base
        }
        // A copied image *file* (e.g. from Finder).
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: options) as? [URL],
           let url = urls.first,
           let data = try? Data(contentsOf: url),
           let base = BaseImage(data: data) {
            return base
        }
        return nil
    }
}
