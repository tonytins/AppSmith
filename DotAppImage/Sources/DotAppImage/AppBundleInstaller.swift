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
            "No DotAppImage-managed desktop entry was found at \(path)."
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

        let manifestURL = resolvedBundleURL.appendingPathComponent("Contents/Manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw AppBundleInstallError.invalidBundle(
                "metadata is missing at \(manifestURL.path)"
            )
        }
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(BundleManifest.self, from: manifestData)
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
