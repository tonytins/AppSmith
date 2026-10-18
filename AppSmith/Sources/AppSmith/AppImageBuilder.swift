import Foundation

struct AppImageOptions {
    let appDirPath: URL
    let runtimePath: URL
    let outputPath: URL
}

enum AppImageError: LocalizedError {
    case invalidValue(String)
    case inputNotFound(String)
    case outputAlreadyExists(String)
    case outputInsideAppDir(String)
    case toolNotFound(String)
    case packagingFailed(status: Int32, output: String)
    case cleanupFailed(primaryError: String, cleanupError: String)

    var errorDescription: String? {
        switch self {
        case .invalidValue(let message):
            message
        case .inputNotFound(let path):
            "Input does not exist: \(path)"
        case .outputAlreadyExists(let path):
            "Output already exists: \(path)"
        case .outputInsideAppDir(let path):
            "Output must be outside the AppDir: \(path)"
        case .toolNotFound(let tool):
            "Required tool '\(tool)' was not found in PATH."
        case .packagingFailed(let status, let output):
            output.isEmpty
                ? "mksquashfs failed with exit status \(status)."
                : "mksquashfs failed with exit status \(status):\n\(output)"
        case .cleanupFailed(let primaryError, let cleanupError):
            "\(primaryError) Temporary-file cleanup also failed: \(cleanupError)"
        }
    }
}

struct AppImageBuilder {
    private let fileManager = FileManager.default

    func build(_ options: AppImageOptions) throws -> URL {
        try validate(options)

        let outputURL = options.outputPath.standardizedFileURL
        let appDirURL = options.appDirPath.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedOutputURL = outputURL.resolvingSymlinksInPath()
        let appDirComponents = appDirURL.pathComponents
        let outputComponents = resolvedOutputURL.pathComponents
        guard outputComponents.count < appDirComponents.count
                || !outputComponents.prefix(appDirComponents.count).elementsEqual(appDirComponents) else {
            throw AppImageError.outputInsideAppDir(outputURL.path)
        }
        let parentURL = outputURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: outputURL.path) else {
            throw AppImageError.outputAlreadyExists(outputURL.path)
        }

        let mksquashfsURL = try executableURL(named: "mksquashfs")
        let stagingURL = parentURL.appendingPathComponent(".\(outputURL.lastPathComponent).\(UUID().uuidString).staging")
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)

        do {
            let imageURL = stagingURL.appendingPathComponent(outputURL.lastPathComponent)
            let squashFSURL = stagingURL.appendingPathComponent("rootfs.squashfs")
            let logURL = stagingURL.appendingPathComponent("mksquashfs.log")
            try createSquashFS(
                from: options.appDirPath.standardizedFileURL,
                at: squashFSURL,
                using: mksquashfsURL,
                loggingTo: logURL
            )
            try assembleImage(
                runtimeURL: options.runtimePath.standardizedFileURL,
                squashFSURL: squashFSURL,
                outputURL: imageURL
            )
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: imageURL.path)
            try fileManager.moveItem(at: imageURL, to: outputURL)
            try fileManager.removeItem(at: stagingURL)
            return outputURL
        } catch {
            let primaryError = error.localizedDescription
            do {
                try fileManager.removeItem(at: stagingURL)
            } catch {
                throw AppImageError.cleanupFailed(
                    primaryError: primaryError,
                    cleanupError: error.localizedDescription
                )
            }
            throw error
        }
    }

    private func validate(_ options: AppImageOptions) throws {
        let appDirURL = options.appDirPath.standardizedFileURL
        let runtimeURL = options.runtimePath.standardizedFileURL
        guard fileManager.fileExists(atPath: appDirURL.path) else {
            throw AppImageError.inputNotFound(appDirURL.path)
        }
        guard fileManager.fileExists(atPath: runtimeURL.path) else {
            throw AppImageError.inputNotFound(runtimeURL.path)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: appDirURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AppImageError.invalidValue("AppDir input must be a directory.")
        }
        let appRunURL = appDirURL.appendingPathComponent("AppRun")
        guard try isRegularFile(at: appRunURL), fileManager.isExecutableFile(atPath: appRunURL.path) else {
            throw AppImageError.invalidValue("AppDir must contain an executable AppRun file.")
        }
        guard try isRegularFile(at: runtimeURL) else {
            throw AppImageError.invalidValue("AppImage runtime must be a regular ELF file.")
        }
        let runtimeHeader = try Data(contentsOf: runtimeURL, options: .mappedIfSafe).prefix(4)
        guard runtimeHeader.elementsEqual([0x7F, 0x45, 0x4C, 0x46]) else {
            throw AppImageError.invalidValue("AppImage runtime does not have an ELF header.")
        }
        guard options.outputPath.pathExtension == "AppImage" else {
            throw AppImageError.invalidValue("Output path must end in .AppImage.")
        }
    }

    private func isRegularFile(at url: URL) throws -> Bool {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return attributes[.type] as? FileAttributeType == .typeRegular
    }

    private func executableURL(named name: String) throws -> URL {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw AppImageError.toolNotFound(name)
    }

    private func createSquashFS(
        from appDirURL: URL,
        at squashFSURL: URL,
        using mksquashfsURL: URL,
        loggingTo logURL: URL
    ) throws {
        let logHandle = try FileHandle(forWritingTo: createEmptyFile(at: logURL))
        let process = Process()
        process.executableURL = mksquashfsURL
        process.arguments = [appDirURL.path, squashFSURL.path, "-noappend", "-all-root"]
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
        process.waitUntilExit()
        try logHandle.close()

        guard process.terminationStatus == 0 else {
            let output = try String(contentsOf: logURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppImageError.packagingFailed(status: process.terminationStatus, output: output)
        }
    }

    private func createEmptyFile(at url: URL) throws -> URL {
        guard fileManager.createFile(atPath: url.path, contents: Data()) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    private func assembleImage(runtimeURL: URL, squashFSURL: URL, outputURL: URL) throws {
        try fileManager.copyItem(at: runtimeURL, to: outputURL)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let squashFSHandle = try FileHandle(forReadingFrom: squashFSURL)

        try outputHandle.seekToEnd()
        while let data = try squashFSHandle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try outputHandle.write(contentsOf: data)
        }
        try outputHandle.synchronize()
    }
}
