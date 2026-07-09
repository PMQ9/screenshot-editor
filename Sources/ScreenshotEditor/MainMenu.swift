import AppKit

/// Programmatic main menu. Key equivalents resolve through NSApp.mainMenu and
/// dispatch down the responder chain even while the menu bar is hidden
/// (accessory mode) — this is what makes Cmd+Z/C/V/S work everywhere.
@MainActor enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Screenshot Editor",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…",
                        action: #selector(AppDelegate.openSettings(_:)),
                        keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Screenshot Editor",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "Screenshot Editor")

        // File
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New from Clipboard",
                         action: #selector(AppDelegate.newFromClipboard(_:)),
                         keyEquivalent: "n")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close",
                         action: #selector(NSWindow.performClose(_:)),
                         keyEquivalent: "w")
        fileMenu.addItem(withTitle: "Save…",
                         action: #selector(EditorWindowController.saveDocument(_:)),
                         keyEquivalent: "s")
        main.addItem(submenu: fileMenu, title: "File")

        // Edit — standard selectors go through the responder chain; the editor
        // window controller implements copy/paste/undo/redo/delete.
        let editMenu = NSMenu(title: "Edit")
        // Custom selectors: NSWindow's built-in undo:/redo: would otherwise
        // swallow Cmd+Z before it reaches EditorWindowController.
        editMenu.addItem(withTitle: "Undo",
                         action: #selector(EditorWindowController.performUndo(_:)),
                         keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo",
                              action: #selector(EditorWindowController.performRedo(_:)),
                              keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)),
                         keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Delete",
                         action: #selector(EditorWindowController.delete(_:)),
                         keyEquivalent: "")
        main.addItem(submenu: editMenu, title: "Edit")

        // View
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Zoom to Fit",
                         action: #selector(EditorWindowController.zoomToFit(_:)),
                         keyEquivalent: "0")
        viewMenu.addItem(withTitle: "Actual Size",
                         action: #selector(EditorWindowController.zoomActualSize(_:)),
                         keyEquivalent: "1")
        main.addItem(submenu: viewMenu, title: "View")

        // Window
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        main.addItem(submenu: windowMenu, title: "Window")
        NSApp.windowsMenu = windowMenu

        return main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
