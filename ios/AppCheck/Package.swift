// swift-tools-version: 6.2
// Type-checks the iPhone app's Swift code on a Mac without Xcode, by building it as a macOS app.
// iPhone-only APIs sit behind `#if os(iOS)` (see Logsperity/App/Compat.swift). Run: swift build
import PackageDescription

let package = Package(
    name: "AppCheck",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../LogsperityCore")],
    targets: [
        .executableTarget(name: "Logsperity", dependencies: ["LogsperityCore"], path: "Sources/Logsperity",
                          exclude: ["Info.plist", "Assets.xcassets", "PrivacyInfo.xcprivacy"]),
    ]
)
