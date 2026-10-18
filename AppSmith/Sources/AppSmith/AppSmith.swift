import ArgumentParser
import Configuration
import Foundation

/// Creates `.app` bundles around prebuilt AppImages without rebuilding their payloads.
@main
struct AppSmith: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appsmith",
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

extension AppSmith {
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
        var name: String?

        @Option(name: .long, help: "Reverse-domain identifier for the app.")
        var identifier: String?

        @Option(name: .long, help: "App version to record in the bundle manifest.")
        var version: String?

        @Option(name: .customLong("appimage"), help: "Path to an existing AppImage payload.")
        var appImage: String?

        @Option(name: .long, help: "Optional icon file to include in the bundle.")
        var icon: String?

        @Option(name: .long, help: "Asset file to include. Repeat to add multiple assets.")
        var asset: [String] = []

        @Option(name: .long, help: "Destination path ending in .app.")
        var output: String?

        mutating func run() throws {
            let config = try Self.loadConfiguration()

            let name = self.name ?? config.string(forKey: ["bundle", "name"], default: "")
            let identifier = self.identifier
                ?? config.string(forKey: ["bundle", "identifier"], default: "")
            let version = self.version ?? config.string(forKey: ["bundle", "version"], default: "")
            let appImage = self.appImage ?? config.string(forKey: ["bundle", "appImage"], default: "")
            let icon = self.icon ?? config.string(forKey: ["bundle", "icon"])
            let asset = self.asset.isEmpty
                ? config.stringArray(forKey: ["bundle", "asset"], default: [])
                : self.asset
            let output = self.output ?? config.string(forKey: ["bundle", "output"], default: "")

            guard !name.isEmpty else {
                throw BundleError.invalidValue(
                    "Name is required (--name or bundle.name in config file)."
                )
            }
            guard !identifier.isEmpty else {
                throw BundleError.invalidValue(
                    "Identifier is required (--identifier or bundle.identifier in config file)."
                )
            }
            guard !version.isEmpty else {
                throw BundleError.invalidValue(
                    "Version is required (--version or bundle.version in config file)."
                )
            }
            guard !appImage.isEmpty else {
                throw BundleError.invalidValue(
                    "AppImage path is required (--appimage or bundle.appImage in config file)."
                )
            }
            guard !output.isEmpty else {
                throw BundleError.invalidValue(
                    "Output path is required (--output or bundle.output in config file)."
                )
            }

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

        /// Loads configuration layered from config file (lowest priority), environment
        /// variables, and finally CLI arguments (highest priority, resolved by ArgumentParser).
        ///
        /// Config file path defaults to `~/.config/appsmith/config.json` and can be
        /// overridden with the `APPSMITH_CONFIG` environment variable. A missing config
        /// file is not an error.
        static func loadConfiguration() throws -> ConfigReader {
            let configFileURL: URL
            if let envPath = ProcessInfo.processInfo.environment["APPSMITH_CONFIG"] {
                configFileURL = URL(fileURLWithPath: envPath)
            } else {
                configFileURL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".config/appsmith/config.json")
            }

            var providers: [any ConfigProvider] = [EnvironmentVariablesProvider()]

            if FileManager.default.fileExists(atPath: configFileURL.path),
               let data = try? Data(contentsOf: configFileURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var flatValues: [String: ConfigContent] = [:]
                flattenJSON(json, prefix: "", into: &flatValues)
                let configValues: [AbsoluteConfigKey: ConfigValue] = flatValues.reduce(into: [:]) { result, item in
                    let key = AbsoluteConfigKey(item.key.components(separatedBy: "."))
                    result[key] = ConfigValue(item.value, isSecret: false)
                }
                providers.append(InMemoryProvider(values: configValues))
            }

            return ConfigReader(providers: providers)
        }

        /// Recursively flattens a JSON object into dot-keyed `ConfigContent` values.
        private static func flattenJSON(
            _ value: Any,
            prefix: String,
            into result: inout [String: ConfigContent]
        ) {
            switch value {
            case let dict as [String: Any]:
                for (key, val) in dict {
                    let newKey = prefix.isEmpty ? key : "\(prefix).\(key)"
                    flattenJSON(val, prefix: newKey, into: &result)
                }
            case let str as String where !prefix.isEmpty:
                result[prefix] = .string(str)
            case let array as [Any] where !prefix.isEmpty:
                result[prefix] = .stringArray(array.compactMap { $0 as? String })
            default:
                break
            }
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
