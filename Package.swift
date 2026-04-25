// swift-tools-version: 6.0
// This Package.swift defines the SPM dependencies only.
// The actual app targets are declared inside the Xcode project (.xcodeproj).
// Add this package to your Xcode project via: File > Add Package Dependencies > Add Local…

import PackageDescription

let package = Package(
    name: "OllamaSearch",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    dependencies: [
        .package(
            url: "https://github.com/gonzalezreal/swift-markdown-ui",
            .upToNextMajor(from: "2.4.0")
        ),
        .package(
            url: "https://github.com/raspu/Highlightr",
            .upToNextMajor(from: "2.2.0")
        ),
    ],
    targets: [
        // Placeholder target — actual targets are in the Xcode project.
        // This file exists so Xcode can resolve SPM dependencies.
        .target(
            name: "OllamaSearchShared",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Highlightr", package: "Highlightr"),
            ],
            path: "Shared"
        ),
    ]
)
