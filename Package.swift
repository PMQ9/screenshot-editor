// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScreenshotEditor",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "ScreenshotEditor",
            path: "Sources/ScreenshotEditor",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "ScreenshotEditorTests",
            dependencies: ["ScreenshotEditor"],
            path: "Tests/ScreenshotEditorTests",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
