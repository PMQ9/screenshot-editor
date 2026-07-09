import AppKit

/// Auto-pop: polls NSPasteboard.changeCount (metadata — never content) and
/// opens the editor when a new image lands. Content bytes are read only at
/// editor-open time. Skips our own writes, copies made while the app is
/// active, and concealed/transient pasteboards (password managers).
@MainActor final class ClipboardMonitor {
    static private(set) var shared: ClipboardMonitor?

    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    var onNewImage: (() -> Void)?

    private var timer: Timer?
    private var lastSeenChangeCount: Int
    private var lastOwnChangeCount: Int = -1

    init() {
        lastSeenChangeCount = NSPasteboard.general.changeCount
        ClipboardMonitor.shared = self
    }

    func noteOwnWrite(changeCount: Int) {
        lastOwnChangeCount = changeCount
    }

    func start() {
        guard timer == nil else { return }
        // Skip whatever is already on the clipboard when the toggle flips on.
        lastSeenChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                ClipboardMonitor.shared?.tick()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != lastSeenChangeCount else { return }
        lastSeenChangeCount = count
        guard count != lastOwnChangeCount else { return }
        // Copies made while our editor is frontmost shouldn't re-pop.
        guard !NSApp.isActive else { return }
        let types = pasteboard.types ?? []
        guard !types.contains(Self.concealedType),
              !types.contains(Self.transientType) else { return }
        guard PasteboardReader.hasImage(pasteboard) else { return }
        onNewImage?()
    }
}
