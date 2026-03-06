// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Batty",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Batty",
            path: "Sources/Batty",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
