import AppKit
import Carbon.HIToolbox

/// Global hotkey via Carbon RegisterEventHotKey — the one API that needs no
/// Accessibility/Input Monitoring permission. The handler fires on the main
/// run loop (dispatcher target), so MainActor.assumeIsolated is legitimate.
@MainActor final class HotkeyManager {
    static let shared = HotkeyManager()

    var onHotkey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    /// Default: ⌘⇧E. Stored in UserDefaults for future configurability.
    func registerFromSettings() {
        let defaults = UserDefaults.standard
        let keyCode = defaults.object(forKey: "hotkeyKeyCode") as? Int ?? kVK_ANSI_E
        let modifiers = defaults.object(forKey: "hotkeyModifiers") as? Int
            ?? (cmdKey | shiftKey)
        register(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        if handlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                          eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(
                GetEventDispatcherTarget(),
                { _, _, _ -> OSStatus in
                    // C callback: cannot capture context; fires on the main run loop.
                    MainActor.assumeIsolated {
                        HotkeyManager.shared.onHotkey?()
                    }
                    return noErr
                },
                1, &eventType, nil, &handlerRef)
            if status != noErr {
                NSLog("HotkeyManager: InstallEventHandler failed (\(status))")
                return
            }
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x5345_4454), id: 1) // 'SEDT'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetEventDispatcherTarget(), 0, &hotKeyRef)
        if status != noErr {
            // eventHotKeyExistsErr and friends: another app owns the combo.
            NSLog("HotkeyManager: RegisterEventHotKey failed (\(status))")
            hotKeyRef = nil
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    var isRegistered: Bool { hotKeyRef != nil }
}
