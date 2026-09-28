// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MemojiStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MemojiStudio",
            targets: ["MemojiStudio"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MemojiStudio",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
