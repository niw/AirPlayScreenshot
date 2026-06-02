// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AirPlayScreenshot",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "AirPlayScreenshot",
            targets: [
                "AirPlayScreenshot"
            ]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/niw/UxPlaySwift.git", branch: "master"),
    ],
    targets: [
        .binaryTarget(
            name: "OpenH264",
            path: "Sources/OpenH264.xcframework"
        ),
        .target(
            name: "AirPlayScreenshot",
            dependencies: [
                .product(name: "UxPlay", package: "UxPlaySwift"),
                .target(name: "OpenH264"),
            ],
            linkerSettings: [
                // libopenh264_dec.a is built from C++ but exposes a C API, so
                // nothing else pulls in the C++ runtime it needs.
                .linkedLibrary("c++"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
