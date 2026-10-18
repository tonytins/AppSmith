// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TestApp",
    dependencies: [
        .package(url: "https://github.com/ShaftUI/Shaft", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "TestApp",
            dependencies: [
                .product(name: "Shaft", package: "Shaft"),
                .product(name: "ShaftSetup", package: "Shaft"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .unsafeFlags(
                    ["-Xfrontend", "-enable-private-imports"],
                    .when(configuration: .debug)
                ),
                .unsafeFlags(
                    ["-Xfrontend", "-enable-implicit-dynamic"],
                    .when(configuration: .debug)
                ),
            ],
            linkerSettings: [
                .unsafeFlags(
                    ["-Xlinker", "--export-dynamic"],
                    .when(platforms: [.linux, .android], configuration: .debug)
                ),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
