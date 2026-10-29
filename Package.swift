// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GrammarCheck",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "GrammarCheck",
            path: "Sources/GrammarCheck",
            // Swift 5 language mode: avoids strict-concurrency compile errors around
            // Process/Carbon/AppKit APIs that are not yet annotated as Sendable.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
