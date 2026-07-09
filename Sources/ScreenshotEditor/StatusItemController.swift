import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let autoPopItem: NSMenuItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        autoPopItem = NSMenuItem(title: "Open Editor on New Screenshot",
                                 action: #selector(toggleAutoPop(_:)), keyEquivalent: "")
        super.init()

        statusItem.button?.image = Self.normalIcon
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

    /// The menu-bar glyph: the custom "Focus" brackets template (a vector PDF that AppKit
    /// auto-tints for light/dark menu bars). Falls back to an SF Symbol if the bundled asset
    /// is ever missing (e.g. running the raw binary outside the assembled .app bundle).
    private static func makeStatusIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            image.accessibilityDescription = "Screenshot Editor"
            return image
        }
        return NSImage(systemSymbolName: "photo.badge.plus",
                       accessibilityDescription: "Screenshot Editor")
    }

    private static let normalIcon = makeStatusIcon()
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
