// swift-tools-version: 6.2
// The Logsperity engine: taxonomy, calculations (design §9–§13), reports and HERB's dialog policy.
// Pure Swift with no SwiftData or SwiftUI, so it builds and tests on any Mac with `swift test`.
import PackageDescription

let package = Package(
    name: "LogsperityCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LogsperityCore", targets: ["LogsperityCore"]),
    ],
    targets: [
        .target(name: "LogsperityCore"),
        .testTarget(name: "LogsperityCoreTests", dependencies: ["LogsperityCore"]),
    ]
)
