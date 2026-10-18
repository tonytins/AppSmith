import Foundation

struct BundleOptions {
    let name: String
    let identifier: String
    let version: String
    let appImagePath: URL
    let iconPath: URL?
    let assetPaths: [URL]
    let outputPath: URL
}

/// Bundle paths are relative to the `.app` directory so the manifest stays portable.
struct BundleManifest: Codable, Equatable {
    let formatVersion: Int
    let identifier: String
    let name: String
    let version: String
    let executable: String
    let icon: String?
    let assets: [String]
}

enum BundleError: LocalizedError {
    case invalidArguments(String)
    case invalidValue(String)
    case inputNotFound(String)
    case outputAlreadyExists(String)
    case cleanupFailed(primaryError: String, cleanupError: String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message), .invalidValue(let message):
            message
        case .inputNotFound(let path):
            "Input file does not exist: \(path)"
        case .outputAlreadyExists(let path):
            "Output already exists: \(path)"
        case .cleanupFailed(let primaryError, let cleanupError):
            "\(primaryError) Bundle cleanup also failed: \(cleanupError)"
        }
    }
}

struct AppBundleBuilder {
    private let fileManager = FileManager.default

    func createBundle(_ options: BundleOptions) throws -> URL {
        try validate(options)

        let outputURL = options.outputPath.standardizedFileURL
        let parentURL = outputURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

        guard !fileManager.fileExists(atPath: outputURL.path) else {
            throw BundleError.outputAlreadyExists(outputURL.path)
        }

        // Build beside the destination so a completed bundle can be published with one rename.
        let stagingURL = parentURL.appendingPathComponent(".\(outputURL.lastPathComponent).\(UUID().uuidString).staging")
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        do {
            try populateBundle(options, outputURL: outputURL, stagingURL: stagingURL)
            try fileManager.moveItem(at: stagingURL, to: outputURL)
            return outputURL
        } catch {
            let primaryError = error.localizedDescription
            do {
                try fileManager.removeItem(at: stagingURL)
            } catch {
                throw BundleError.cleanupFailed(
                    primaryError: primaryError,
                    cleanupError: error.localizedDescription
                )
            }
            throw error
        }
    }

    private func populateBundle(_ options: BundleOptions, outputURL: URL, stagingURL: URL) throws {
        let contentsURL = stagingURL.appendingPathComponent("Contents", isDirectory: true)
        let linuxURL = contentsURL.appendingPathComponent("Linux", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let assetsURL = resourcesURL.appendingPathComponent("Assets", isDirectory: true)
        try fileManager.createDirectory(at: linuxURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)

        let executableRelativePath = "Contents/Linux/AppImage"
        let appImageURL = linuxURL.appendingPathComponent("AppImage")
        try fileManager.copyItem(at: options.appImagePath.standardizedFileURL, to: appImageURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appImageURL.path)

        let iconRelativePath: String?
        if let iconPath = options.iconPath?.standardizedFileURL {
            let fileName = iconFileName(for: iconPath)
            let destination = resourcesURL.appendingPathComponent(fileName)
            try fileManager.copyItem(at: iconPath, to: destination)
            iconRelativePath = "Contents/Resources/\(fileName)"
        } else {
            iconRelativePath = nil
        }

        let assetRelativePaths = try copyAssets(options.assetPaths, to: assetsURL)
        let manifest = BundleManifest(
            formatVersion: 1,
            identifier: options.identifier,
            name: options.name,
            version: options.version,
            executable: executableRelativePath,
            icon: iconRelativePath,
            assets: assetRelativePaths
        )
        try writeManifest(manifest, to: contentsURL.appendingPathComponent("Manifest.toml"))

        let launcherURL = stagingURL.appendingPathComponent("AppRun")
        try writeLauncher(to: launcherURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)

        let desktopURL = stagingURL.appendingPathComponent("\(options.identifier).desktop")
        try writeDesktopEntry(
            options: options,
            bundleURL: outputURL,
            iconURL: iconRelativePath.map { outputURL.appendingPathComponent($0) },
            to: desktopURL
        )
    }

    private func validate(_ options: BundleOptions) throws {
        guard !options.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !options.name.containsNewline else {
            throw BundleError.invalidValue("Name must not be empty or contain a newline.")
        }
        guard !options.version.isEmpty, !options.version.containsNewline else {
            throw BundleError.invalidValue("Version must not be empty or contain a newline.")
        }
        guard options.identifier.range(
            of: #"^[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*$"#,
            options: .regularExpression
        ) != nil else {
            throw BundleError.invalidValue("Identifier must contain dot- or hyphen-separated letters and numbers.")
        }
        guard options.outputPath.pathExtension == "app" else {
            throw BundleError.invalidValue("Output path must end in .app.")
        }
        for inputURL in [options.appImagePath] + (options.iconPath.map { [$0] } ?? []) + options.assetPaths {
            guard fileManager.fileExists(atPath: inputURL.path) else {
                throw BundleError.inputNotFound(inputURL.path)
            }
        }
        guard try isRegularFile(at: options.appImagePath) else {
            throw BundleError.invalidValue("AppImage input must be a regular file.")
        }
        if let iconPath = options.iconPath, try !isRegularFile(at: iconPath) {
            throw BundleError.invalidValue("Icon input must be a regular file.")
        }

        let assetNames = options.assetPaths.map(\.lastPathComponent)
        guard Set(assetNames).count == assetNames.count else {
            throw BundleError.invalidValue("Asset paths must have unique file names.")
        }
    }

    private func isRegularFile(at url: URL) throws -> Bool {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return attributes[.type] as? FileAttributeType == .typeRegular
    }

    private func copyAssets(_ assetPaths: [URL], to assetsURL: URL) throws -> [String] {
        try assetPaths.map { assetPath in
            let sourceURL = assetPath.standardizedFileURL
            let destinationURL = assetsURL.appendingPathComponent(sourceURL.lastPathComponent)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return "Contents/Resources/Assets/\(sourceURL.lastPathComponent)"
        }
    }

    private func writeManifest(_ manifest: BundleManifest, to url: URL) throws {
        let data = encodeManifestTOML(manifest)
        try data.write(to: url, options: .atomic)
    }

    private func writeLauncher(to url: URL) throws {
        let contents = """
        #!/bin/sh
        set -eu
        APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
        exec "$APP_DIR/Contents/Linux/AppImage" "$@"
        """
        try Data((contents + "\n").utf8).write(to: url, options: .atomic)
    }

    private func writeDesktopEntry(
        options: BundleOptions,
        bundleURL: URL,
        iconURL: URL?,
        to url: URL
    ) throws {
        var lines = [
            "[Desktop Entry]",
            "Type=Application",
            "Name=\(desktopString(options.name))",
            "Comment=\(desktopString("Launch \(options.name)"))",
            "TryExec=appsmith",
            "Exec=appsmith open \(desktopCommand(bundleURL.path)) %U",
            "Terminal=false",
            "Categories=Utility;"
        ]
        if let iconURL {
            lines.append("Icon=\(desktopString(iconURL.path))")
        }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
    }

    private func iconFileName(for iconURL: URL) -> String {
        let extensionName = iconURL.pathExtension
        return extensionName.isEmpty ? "AppIcon" : "AppIcon.\(extensionName)"
    }

    private func desktopString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private func desktopCommand(_ path: String) -> String {
        let escaped = path
            .replacingOccurrences(of: "%", with: "%%")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        return "\"\(escaped)\""
    }
}

private extension String {
    var containsNewline: Bool {
        contains("\n") || contains("\r")
    }
}

/// Encodes a BundleManifest into TOML-formatted data.
func encodeManifestTOML(_ manifest: BundleManifest) -> Data {
    var lines = [String]()
    lines.append("formatVersion = \(manifest.formatVersion)")
    lines.append("identifier = \(tomlString(manifest.identifier))")
    lines.append("name = \(tomlString(manifest.name))")
    lines.append("version = \(tomlString(manifest.version))")
    lines.append("executable = \(tomlString(manifest.executable))")
    if let icon = manifest.icon {
        lines.append("icon = \(tomlString(icon))")
    }
    let assets = manifest.assets.map { tomlString($0) }.joined(separator: ", ")
    lines.append("assets = [\(assets)]")
    return Data((lines.joined(separator: "\n") + "\n").utf8)
}

/// Decodes TOML-formatted data into a BundleManifest.
func decodeManifestTOML(_ data: Data) throws -> BundleManifest {
    let text = String(decoding: data, as: UTF8.self)
    var values = [String: String]()
    var assets = [String]()

    for line in text.split(whereSeparator: { $0.isNewline }) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.first != "#",
              trimmed.first != "[",
              let eqIndex = trimmed.firstIndex(of: "=") else {
            continue
        }
        let key = String(trimmed[..<eqIndex]).trimmingCharacters(in: .whitespaces)
        let value = String(trimmed[trimmed.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)

        if key == "assets" {
            assets = parseTOMLArray(value)
        } else {
            values[key] = tomlUnescape(value)
        }
    }

    return BundleManifest(
        formatVersion: Int(values["formatVersion"] ?? "0") ?? 0,
        identifier: values["identifier"] ?? "",
        name: values["name"] ?? "",
        version: values["version"] ?? "",
        executable: values["executable"] ?? "",
        icon: values["icon"],
        assets: assets
    )
}

/// Escapes a Swift string for a TOML basic string literal.
private func tomlString(_ value: String) -> String {
    var result = "\""
    for scalar in value.unicodeScalars {
        switch scalar {
        case "\"": result += "\\\""
        case "\\": result += "\\\\"
        case "\n": result += "\\n"
        case "\r": result += "\\r"
        case "\t": result += "\\t"
        case "\u{0000}"..."\u{001F}":
            result += String(format: "\\u%04X", scalar.value)
        default:
            result.append(Character(scalar))
        }
    }
    result += "\""
    return result
}

/// Unescapes a TOML basic string literal back into a Swift string.
private func tomlUnescape(_ value: String) -> String {
    guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else {
        return value
    }
    let inner = String(value.dropFirst().dropLast())
    var result = ""
    var i = inner.startIndex
    while i < inner.endIndex {
        let char = inner[i]
        if char == "\\", inner.index(after: i) < inner.endIndex {
            let next = inner[inner.index(after: i)]
            switch next {
            case "\"": result.append("\""); i = inner.index(after: i)
            case "\\": result.append("\\"); i = inner.index(after: i)
            case "n": result.append("\n"); i = inner.index(after: i)
            case "r": result.append("\r"); i = inner.index(after: i)
            case "t": result.append("\t"); i = inner.index(after: i)
            default: result.append(char)
            }
        } else {
            result.append(char)
        }
        i = inner.index(after: i)
    }
    return result
}

/// Parses a TOML array of strings like `[ "a", "b" ]`.
private func parseTOMLArray(_ value: String) -> [String] {
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), trimmed.count > 2 else {
        return []
    }
    let inner = String(trimmed.dropFirst().dropLast())
    return inner.split(whereSeparator: { $0 == "," }).map { element in
        let item = element.trimmingCharacters(in: .whitespaces)
        return tomlUnescape(item)
    }
}
