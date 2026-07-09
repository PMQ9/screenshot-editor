import AppKit

/// Keeps editor window controllers alive and drives the activation-policy
/// dance: .regular while any editor window is open (menu bar + Cmd-Tab),
/// .accessory when only the status item remains.
@MainActor final class WindowRegistry {
    static let shared = WindowRegistry()

    private var controllers: [EditorWindowController] = []

    private init() {}

    func add(_ controller: EditorWindowController) {
        controllers.append(controller)
        if let window = controller.window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification, object: window)
        }
        NSApp.setActivationPolicy(.regular)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.willCloseNotification, object: window)
        controllers.removeAll { $0.window === window }
        // Keep the menu bar while the Settings window is still up.
        if controllers.isEmpty,
           SettingsWindowController.shared.window?.isVisible != true {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
