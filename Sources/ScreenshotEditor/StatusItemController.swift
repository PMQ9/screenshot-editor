import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let autoPopItem: NSMenuItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        autoPopItem = NSMenuItem(title: "Open Editor on New Screenshot",
                                 action: #selector(toggleAutoPop(_:)), keyEquivalent: "")
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "photo.badge.plus",
            accessibilityDescription: "Screenshot Editor")
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let edit = NSMenuItem(title: "Edit Clipboard Image",
                              action: #selector(AppDelegate.newFromClipboard(_:)),
                              keyEquivalent: "e")
        edit.keyEquivalentModifierMask = [.command, .shift]   // hint: matches the global hotkey
        menu.addItem(edit)

        autoPopItem.target = self
        menu.addItem(autoPopItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…",
                                action: #selector(AppDelegate.openSettings(_:)),
                                keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Screenshot Editor",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        autoPopItem.state = AppSettings.shared.autoPopEnabled ? .on : .off
    }

    @objc private func toggleAutoPop(_ sender: Any?) {
        AppSettings.shared.autoPopEnabled.toggle()
    }

    private static let normalIcon = NSImage(
        systemSymbolName: "photo.badge.plus",
        accessibilityDescription: "Screenshot Editor")
    private var hintRestore: DispatchWorkItem?

    /// Brief "nothing to edit" affordance when the hotkey fires on an empty
    /// clipboard. Restores to a constant icon so re-entry can't stick the warning.
    func flashNoImageHint() {
        guard let button = statusItem.button else { return }
        hintRestore?.cancel()
        button.image = NSImage(systemSymbolName: "exclamationmark.triangle",
                               accessibilityDescription: "No image on clipboard")
        let restore = DispatchWorkItem { [weak self] in
            self?.statusItem.button?.image = Self.normalIcon
        }
        hintRestore = restore
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: restore)
    }
}
