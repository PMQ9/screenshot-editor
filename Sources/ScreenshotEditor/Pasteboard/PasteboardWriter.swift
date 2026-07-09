import AppKit

enum PasteboardWriter {
    /// Writes PNG + TIFF (some paste targets only accept TIFF) and tells the
    /// clipboard monitor to ignore our own change so auto-pop doesn't loop.
    static func write(image: CGImage, pixelsPerPoint: CGFloat,
                      to pasteboard: NSPasteboard = .general) {
        let png = ExportService.pngData(image, pixelsPerPoint: pixelsPerPoint)
        let bitmap = NSBitmapImageRep(cgImage: image)
        // Point size so paste targets show the natural (non-2x-blown-up) size.
        bitmap.size = CGSize(width: CGFloat(image.width) / pixelsPerPoint,
                             height: CGFloat(image.height) / pixelsPerPoint)
        let tiff = bitmap.tiffRepresentation

        pasteboard.clearContents()
        if let png {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff {
            pasteboard.setData(tiff, forType: .tiff)
        }
        ClipboardMonitor.shared?.noteOwnWrite(changeCount: pasteboard.changeCount)
    }
}
