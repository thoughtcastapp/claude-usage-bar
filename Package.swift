// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [
        // macOS 14+ required for `Color.gradient` on ShapeStyle (Components.swift) and other
        // SwiftUI affordances used in the popover redesign.
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeUsageBar",
            path: "Sources/ClaudeUsageBar",
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"], .when(configuration: .release))
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
