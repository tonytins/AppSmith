import Foundation

enum AppBundleInstallError: LocalizedError {
    case invalidBundle(String)
    case invalidApplicationsDirectory(String)
    case desktopEntryAlreadyExists(String)
    case desktopEntryNotInstalled(String)
    case desktopEntryOwnedByAnotherBundle(String)

    var errorDescription: String? {
        switch self {
        case .invalidBundle(let reason):
            "Cannot register app bundle: \(reason)"
        case .invalidApplicationsDirectory(let path):
            "Applications data directory must be an absolute path: \(path)"
        case .desktopEntryAlreadyExists(let path):
            "A desktop entry already exists at \(path). It was not replaced."
        case .desktopEntryNotInstalled(let path):
            "No AppSmith-managed desktop entry was found at \(path)."
        case .desktopEntryOwnedByAnotherBundle(let path):
            "The desktop entry at \(path) points to a different bundle."
        }
    }
}

struct AppBundleInstaller {
    private let fileManager = FileManager.default
    private let applicationsDirectory: URL

    init(applicationsDirectory: URL? = nil) throws {
        self.applicationsDirectory = try applicationsDirectory
            ?? Self.userApplicationsDirectory()
    }

    func install(_ bundleURL: URL) throws -> URL {
        let (resolvedBundleURL, desktopURL) = try bundleContents(for: bundleURL)
        try fileManager.createDirectory(
            at: applicationsDirectory,
            withIntermediateDirectories: true
        )

        let installedDesktopURL = applicationsDirectory
            .appendingPathComponent(desktopURL.lastPathComponent)
        if let existingDestination = symbolicLinkDestination(at: installedDesktopURL) {
            guard existingDestination == desktopURL else {
                throw AppBundleInstallError.desktopEntryAlreadyExists(installedDesktopURL.path)
            }
            return installedDesktopURL
        }
        guard !fileManager.fileExists(atPath: installedDesktopURL.path) else {
            throw AppBundleInstallError.desktopEntryAlreadyExists(installedDesktopURL.path)
        }

        try fileManager.createSymbolicLink(
            at: installedDesktopURL,
            withDestinationURL: resolvedBundleURL.appendingPathComponent(desktopURL.lastPathComponent)
        )
        return installedDesktopURL
    }

    func uninstall(_ bundleURL: URL) throws -> URL {
        let (_, desktopURL) = try bundleContents(for: bundleURL)
        let installedDesktopURL = applicationsDirectory
            .appendingPathComponent(desktopURL.lastPathComponent)
        guard let existingDestination = symbolicLinkDestination(at: installedDesktopURL) else {
            if fileManager.fileExists(atPath: installedDesktopURL.path) {
                throw AppBundleInstallError.desktopEntryOwnedByAnotherBundle(installedDesktopURL.path)
            }
            throw AppBundleInstallError.desktopEntryNotInstalled(installedDesktopURL.path)
        }
        guard existingDestination == desktopURL else {
            throw AppBundleInstallError.desktopEntryOwnedByAnotherBundle(installedDesktopURL.path)
        }

        try fileManager.removeItem(at: installedDesktopURL)
        return installedDesktopURL
    }

    private func bundleContents(for bundleURL: URL) throws -> (URL, URL) {
        let resolvedBundleURL = bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedBundleURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw AppBundleInstallError.invalidBundle(
                "the path is not an existing directory: \(resolvedBundleURL.path)"
            )
        }

        let manifestURL = resolvedBundleURL.appendingPathComponent("Contents/Manifest.toml")
        let legacyJSONURL = resolvedBundleURL.appendingPathComponent("Contents/Manifest.json")
        let legacyPlistURL = resolvedBundleURL.appendingPathComponent("Contents/Manifest.plist")
        let manifestURLs = [manifestURL, legacyJSONURL, legacyPlistURL]
        var manifestData: Data?
        var usedURL: URL?
        for url in manifestURLs {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            manifestData = try? Data(contentsOf: url)
            usedURL = url
            break
        }
        guard let manifestData, let usedURL else {
            throw AppBundleInstallError.invalidBundle(
                "metadata is missing at \(resolvedBundleURL.appendingPathComponent("Contents/Manifest.toml").path)"
            )
        }
        let manifest: BundleManifest
        switch usedURL.pathExtension {
        case "toml":
            manifest = try decodeManifestTOML(manifestData)
        case "json":
            manifest = try JSONDecoder().decode(BundleManifest.self, from: manifestData)
        case "plist":
            guard let plist = try PropertyListSerialization.propertyList(
                from: manifestData,
                options: [],
                format: nil
            ) as? [String: Any] else {
                throw AppBundleInstallError.invalidBundle(
                    "malformed property list metadata at \(usedURL.path)"
                )
            }
            manifest = try self.decodePlistManifest(plist)
        default:
            throw AppBundleInstallError.invalidBundle(
                "unsupported manifest format at \(usedURL.path)"
            )
        }
        guard manifest.identifier.range(
            of: #"^[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*$"#,
            options: .regularExpression
        ) != nil else {
            throw AppBundleInstallError.invalidBundle("metadata contains an invalid identifier.")
        }

        let desktopURL = resolvedBundleURL
            .appendingPathComponent("\(manifest.identifier).desktop")
        guard fileManager.fileExists(atPath: desktopURL.path),
              try fileManager.attributesOfItem(atPath: desktopURL.path)[.type] as? FileAttributeType == .typeRegular else {
            throw AppBundleInstallError.invalidBundle(
                "the desktop entry is missing at \(desktopURL.path)"
            )
        }

        return (resolvedBundleURL, desktopURL)
    }

    private func decodePlistManifest(_ plist: [String: Any]) throws -> BundleManifest {
        guard let formatVersion = plist["formatVersion"] as? Int else {
            throw AppBundleInstallError.invalidBundle("metadata is missing formatVersion.")
        }
        guard let identifier = plist["identifier"] as? String else {
            throw AppBundleInstallError.invalidBundle("metadata is missing identifier.")
        }
        guard let name = plist["name"] as? String else {
            throw AppBundleInstallError.invalidBundle("metadata is missing name.")
        }
        guard let version = plist["version"] as? String else {
            throw AppBundleInstallError.invalidBundle("metadata is missing version.")
        }
        guard let executable = plist["executable"] as? String else {
            throw AppBundleInstallError.invalidBundle("metadata is missing executable.")
        }
        let icon = plist["icon"] as? String
        let assets = (plist["assets"] as? [String]) ?? []
        return BundleManifest(
            formatVersion: formatVersion,
            identifier: identifier,
            name: name,
            version: version,
            executable: executable,
            icon: icon,
            assets: assets
        )
    }

    private func symbolicLinkDestination(at linkURL: URL) -> URL? {
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: linkURL.path) else {
            return nil
        }
        return URL(
            fileURLWithPath: destination,
            relativeTo: linkURL.deletingLastPathComponent()
        )
        .standardizedFileURL
        .resolvingSymlinksInPath()
    }

    private static func userApplicationsDirectory() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let dataDirectory: String
        if let xdgDataHome = environment["XDG_DATA_HOME"], !xdgDataHome.isEmpty {
            dataDirectory = xdgDataHome
        } else if let homeDirectory = environment["HOME"], !homeDirectory.isEmpty {
            dataDirectory = "\(homeDirectory)/.local/share"
        } else {
            throw AppBundleInstallError.invalidApplicationsDirectory("$HOME is not set.")
        }

        guard dataDirectory.hasPrefix("/") else {
            throw AppBundleInstallError.invalidApplicationsDirectory(dataDirectory)
        }
        return URL(fileURLWithPath: dataDirectory, isDirectory: true)
            .appendingPathComponent("applications", isDirectory: true)
    }
}
