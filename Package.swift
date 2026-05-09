// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OpenCodeTray",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OpenCodeTray", targets: ["OpenCodeTray"]),
    ],
    targets: [
        .executableTarget(
            name: "OpenCodeTray",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreImage"),
                .linkedFramework("Security"),
            ]
        ),
    ]
)
