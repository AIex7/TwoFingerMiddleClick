// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TwoFingerMiddleClick",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TwoFingerMiddleClick", targets: ["TwoFingerMiddleClick"])
    ],
    targets: [
        .target(
            name: "TouchBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreFoundation")
            ]
        ),
        .executableTarget(
            name: "TwoFingerMiddleClick",
            dependencies: ["TouchBridge"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics")
            ]
        )
    ]
)
