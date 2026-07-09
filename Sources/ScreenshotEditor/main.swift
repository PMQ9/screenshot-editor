import AppKit

// Headless render mode for scripted verification; exits before AppKit starts.
if CommandLine.arguments.contains("--test-render") {
    exit(TestRenderMode.run(arguments: CommandLine.arguments))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
