// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CultureMemoji",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CultureMemoji",
            targets: ["CultureMemoji"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "CultureMemoji",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
