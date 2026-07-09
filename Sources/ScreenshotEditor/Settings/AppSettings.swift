import Foundation
import Observation

@MainActor @Observable final class AppSettings {
    static let shared = AppSettings()

    var autoPopEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoPopEnabled, forKey: "autoPopEnabled")
            onAutoPopChanged?(autoPopEnabled)
        }
    }

    var saveFolderPath: String {
        didSet { UserDefaults.standard.set(saveFolderPath, forKey: "saveFolderPath") }
    }

    /// Display-only in v1; change via `defaults write` and relaunch.
    let hotkeyDescription = "⌘⇧E"

    var onAutoPopChanged: ((Bool) -> Void)?

    private init() {
        let defaults = UserDefaults.standard
        autoPopEnabled = defaults.object(forKey: "autoPopEnabled") as? Bool ?? true
        saveFolderPath = defaults.string(forKey: "saveFolderPath")
            ?? NSHomeDirectory() + "/Desktop"
    }

    var saveFolderURL: URL {
        URL(fileURLWithPath: (saveFolderPath as NSString).expandingTildeInPath,
            isDirectory: true)
    }
}
