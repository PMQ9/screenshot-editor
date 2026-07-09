import SwiftUI

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Toggle("Open editor when a screenshot is copied",
                   isOn: $settings.autoPopEnabled)
            LabeledContent("Global hotkey", value: settings.hotkeyDescription)
            LabeledContent("Save folder") {
                HStack {
                    Text(settings.saveFolderPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") { chooseFolder() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = settings.saveFolderURL
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveFolderPath = url.path
        }
    }
}
