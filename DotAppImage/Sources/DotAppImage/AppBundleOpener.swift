import Foundation

enum AppBundleOpenError: LocalizedError {
    case bundleNotFound(String)
    case appRunNotExecutable(String)
    case launchFailed(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .bundleNotFound(let path):
            "App bundle does not exist or is not a directory: \(path)"
        case .appRunNotExecutable(let path):
            "App bundle must contain an executable AppRun file: \(path)"
        case .launchFailed(let path, let reason):
            "Could not launch app bundle at \(path): \(reason)"
        }
    }
}

struct AppBundleOpener {
    private let fileManager = FileManager.default

    func open(_ bundleURL: URL) throws {
        let standardizedBundleURL = bundleURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardizedBundleURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw AppBundleOpenError.bundleNotFound(standardizedBundleURL.path)
        }

        let appRunURL = standardizedBundleURL.appendingPathComponent("AppRun")
        var isDirectoryAppRun: ObjCBool = false
        guard fileManager.fileExists(atPath: appRunURL.path, isDirectory: &isDirectoryAppRun),
              !isDirectoryAppRun.boolValue,
              fileManager.isExecutableFile(atPath: appRunURL.path) else {
            throw AppBundleOpenError.appRunNotExecutable(appRunURL.path)
        }

        let process = Process()
        process.executableURL = appRunURL
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw AppBundleOpenError.launchFailed(
                path: standardizedBundleURL.path,
                reason: error.localizedDescription
            )
        }
    }
}
