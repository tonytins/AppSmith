// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AppSmith",
    products: [
        .executable(name: "appsmith", targets: ["AppSmith"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-configuration.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "AppSmith",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "AppSmithTests",
            dependencies: ["AppSmith"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
