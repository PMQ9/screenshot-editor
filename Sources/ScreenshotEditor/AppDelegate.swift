import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var clipboardMonitor: ClipboardMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set in code as well as LSUIElement so the bare `swift run` binary
        // behaves like the bundled app during development.
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.build()

        statusItemController = StatusItemController()

        HotkeyManager.shared.onHotkey = { [weak self] in
            self?.openEditorFromClipboard()
        }
        HotkeyManager.shared.registerFromSettings()

        let monitor = ClipboardMonitor()
        monitor.onNewImage = { [weak self] in
            self?.openEditorFromClipboard()
        }
        clipboardMonitor = monitor
        AppSettings.shared.onAutoPopChanged = { enabled in
            enabled ? monitor.start() : monitor.stop()
        }
        if AppSettings.shared.autoPopEnabled {
            monitor.start()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Entry points

    @objc func newFromClipboard(_ sender: Any?) {
        openEditorFromClipboard()
    }

    @objc func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    func openEditorFromClipboard() {
        guard let base = PasteboardReader.readImage() else {
            NSSound.beep()
            statusItemController?.flashNoImageHint()
            return
        }
        openEditor(with: Document(base: base))
    }

    func openEditor(with document: Document) {
        let controller = EditorWindowController(document: document)
        WindowRegistry.shared.add(controller)   // switches policy to .regular
        controller.showWindow(nil)
        // Deprecated but still the reliable way to steal focus from a hotkey;
        // the modern cooperative call follows as a forward-compatibility hedge.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.activate()
        controller.window?.makeKeyAndOrderFront(nil)
    }
}
