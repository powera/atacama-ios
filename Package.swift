// swift-tools-version: 5.9
// SwiftPM manifest, used for command-line builds and editor diagnostics. The iOS
// app itself is built via Atacama.xcodeproj (see AGENTS.md). This mirrors the
// dual Package.swift + .xcodeproj setup used by the trakaido SwiftApp.

import PackageDescription

let package = Package(
    name: "Atacama",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Atacama", targets: ["Atacama"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Atacama",
            path: "Atacama",
            exclude: [
                "Info.plist",
            ],
            sources: [
                "AtacamaApp.swift",
                "Models",
                "Services",
                "Managers",
                "Storage",
                "Views",
            ]
        ),
    ]
)
