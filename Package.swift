// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "ow",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "ow",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "owTests",
            dependencies: ["ow"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
