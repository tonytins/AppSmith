// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DotAppImage",
    products: [
        .executable(name: "dotappimage", targets: ["DotAppImage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "DotAppImage",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "DotAppImageTests",
            dependencies: ["DotAppImage"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
