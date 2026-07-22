// swift-tools-version: 6.2
// Copyright 2026 Kaizōsha. Developed by Kaizō Konpaku.

import PackageDescription

let package = Package(
    name: "SekaiKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "SekaiKit", targets: ["SekaiKit"]),
        .library(name: "SekaiGeoJSON", targets: ["SekaiGeoJSON"]),
        .library(name: "SekaiLocation", targets: ["SekaiLocation"]),
        .library(name: "SekaiInspector", targets: ["SekaiInspector"])
    ],
    targets: [
        .target(
            name: "SekaiKit",
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "SekaiGeoJSON",
            dependencies: ["SekaiKit"]
        ),
        .target(
            name: "SekaiLocation",
            dependencies: ["SekaiKit"]
        ),
        .target(
            name: "SekaiInspector",
            dependencies: ["SekaiKit", "SekaiGeoJSON", "SekaiLocation"]
        ),
        .testTarget(
            name: "SekaiKitTests",
            dependencies: ["SekaiKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
