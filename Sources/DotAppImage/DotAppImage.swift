import ArgumentParser
import Foundation

/// Creates `.app` bundles around prebuilt AppImages without rebuilding their payloads.
@main
struct DotAppImage: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dotappimage",
        abstract: "Build AppImages and create Linux .app bundles for them.",
        subcommands: [Build.self, Bundle.self]
    )

    mutating func run() throws {
        print(Self.helpMessage())
    }
}

extension DotAppImage {
    /// Builds a Type 2 AppImage from an AppDir using `mksquashfs` and a supplied runtime.
    struct Build: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Build a Type 2 AppImage from an existing AppDir."
        )

        @Option(name: .long, help: "Path to a prepared AppDir containing an executable AppRun.")
        var appdir: String

        @Option(name: .long, help: "Path to the AppImage Type 2 runtime ELF for the target architecture.")
        var runtime: String

        @Option(name: .long, help: "Destination path ending in .AppImage.")
        var output: String

        mutating func run() throws {
            let options = AppImageOptions(
                appDirPath: URL(fileURLWithPath: appdir),
                runtimePath: URL(fileURLWithPath: runtime),
                outputPath: URL(fileURLWithPath: output)
            )
            let appImageURL = try AppImageBuilder().build(options)
            print("Created \(appImageURL.path)")
        }
    }

    /// Wraps an existing AppImage with bundle metadata and optional resources.
    struct Bundle: ParsableCommand {
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
