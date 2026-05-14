// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OpenCodeTray",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OpenCodeTray", targets: ["OpenCodeTray"]),
        .executable(name: "OpenCodeTrayHelper", targets: ["OpenCodeTrayHelper"]),
    ],
    targets: [
        .target(
            name: "HelperProtocol"
        ),
        .executableTarget(
            name: "OpenCodeTray",
            dependencies: ["HelperProtocol"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreImage"),
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(
            name: "OpenCodeTrayHelper",
            dependencies: ["HelperProtocol"]
        ),
    ]
)
