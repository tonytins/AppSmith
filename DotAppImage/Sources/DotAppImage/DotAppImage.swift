import ArgumentParser
import Foundation

/// Creates `.app` bundles around prebuilt AppImages without rebuilding their payloads.
@main
struct DotAppImage: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dotappimage",
        abstract: "Build AppImages and create Linux .app bundles for them.",
        subcommands: [
            Build.self,
            Bundle.self,
            Dependencies.self,
            Open.self,
            Install.self,
            Uninstall.self
        ]
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

    /// Reports the dynamic dependencies of an ELF executable in an AppDir.
    struct Dependencies: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "dependencies",
            abstract: "Report ELF dependencies resolved from an AppDir and the host."
        )

        @Option(name: .long, help: "Path to the prepared AppDir.")
        var appdir: String

        @Option(name: .long, help: "Executable path, relative to the AppDir or an absolute path inside it.")
        var executable: String

        mutating func run() throws {
            let report = try AppDependencyReporter().report(
                appDirURL: URL(fileURLWithPath: appdir),
                executablePath: executable
            )
            print(report.description)
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

    /// Launches an existing `.app` bundle through its `AppRun` script.
    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Launch a Linux .app directory bundle."
        )

        @Argument(help: "Path to the .app directory bundle.")
        var app: String

        @Argument(parsing: .remaining, help: "Arguments to pass to the app.")
        var arguments: [String] = []

        mutating func run() throws {
            let bundleURL = URL(fileURLWithPath: app)
            try AppBundleOpener().open(bundleURL, arguments: arguments)
            print("Launched \(bundleURL.standardizedFileURL.path)")
        }
    }

    /// Adds a bundle's desktop entry to the current user's applications.
    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Register a .app bundle in the current user's applications."
        )

        @Argument(help: "Path to the .app directory bundle.")
        var app: String

        mutating func run() throws {
            let desktopURL = try AppBundleInstaller().install(URL(fileURLWithPath: app))
            print("Installed desktop entry at \(desktopURL.path)")
        }
    }

    /// Removes a bundle's desktop entry from the current user's applications.
    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove a .app bundle's registration from the current user."
        )

        @Argument(help: "Path to the .app directory bundle.")
        var app: String

        mutating func run() throws {
            let desktopURL = try AppBundleInstaller().uninstall(URL(fileURLWithPath: app))
            print("Removed desktop entry at \(desktopURL.path)")
        }
    }
}
