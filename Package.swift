// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Momiji",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MomijiCore", targets: ["MomijiCore"]),
        .library(name: "MomijiSystem", targets: ["MomijiSystem"]),
        // Keep the SwiftPM executable distinct from the Momiji.app Xcode
        // product so UI tests always resolve the application bundle.
        .executable(name: "MomijiSwiftPM", targets: ["MomijiExecutable"]),
        .executable(name: "MomijiHelper", targets: ["MomijiHelperExecutable"]),
    ],
    targets: [
        .target(
            name: "MomijiCore",
            path: "Sources/MomijiCore"
        ),
        .target(
            name: "MomijiSystemBridge",
            path: "Sources/MomijiSystemBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .target(
            name: "MomijiSystem",
            dependencies: ["MomijiCore", "MomijiSystemBridge"],
            path: "Sources/MomijiSystem"
        ),
        .executableTarget(
            name: "MomijiExecutable",
            dependencies: ["MomijiCore", "MomijiSystem"],
            path: "MomijiApp",
            exclude: ["Info.plist"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "MomijiHelperExecutable",
            dependencies: ["MomijiCore", "MomijiSystem"],
            path: "MomijiHelper",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "MomijiCoreTests",
            dependencies: ["MomijiCore"],
            path: "Tests/MomijiCoreTests"
        ),
        .testTarget(
            name: "MomijiSystemIntegrationTests",
            dependencies: ["MomijiCore", "MomijiSystem"],
            path: "Tests/MomijiSystemIntegrationTests"
        ),
    ]
)
