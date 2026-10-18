import ArgumentParser
import Foundation

/// Creates `.app` bundles around prebuilt AppImages without rebuilding their payloads.
@main
struct DotAppImage: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dotappimage",
        abstract: "Create Linux .app bundles that carry AppImage payloads.",
        subcommands: [Create.self]
    )

    mutating func run() throws {
        print(Self.helpMessage())
    }
}

extension DotAppImage {
    /// Wraps an AppImage with bundle metadata and optional resources.
    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a Linux .app directory bundle around an existing AppImage."
        )

        @Option(name: .long, help: "Display name for the app.")
        var name: String

        @Option(name: .long, help: "Reverse-domain identifier for the app.")
        var identifier: String

        @Option(name: .long, help: "App version to record in the bundle manifest.")
        var version: String

        @Option(name: .customLong("appimage"), help: "Path to an existing AppImage payload.")
        var appImage: String

        @Option(name: .long, help: "Optional icon file to include in the bundle.")
        var icon: String?

        @Option(name: .long, help: "Asset file to include. Repeat to add multiple assets.")
        var asset: [String] = []

        @Option(name: .long, help: "Destination path ending in .app.")
        var output: String

        mutating func run() throws {
            let options = BundleOptions(
                name: name,
                identifier: identifier,
                version: version,
                appImagePath: URL(fileURLWithPath: appImage),
                iconPath: icon.map(URL.init(fileURLWithPath:)),
                assetPaths: asset.map(URL.init(fileURLWithPath:)),
                outputPath: URL(fileURLWithPath: output)
            )
            let bundleURL = try AppBundleBuilder().createBundle(options)
            print("Created \(bundleURL.path)")
        }
    }
}
