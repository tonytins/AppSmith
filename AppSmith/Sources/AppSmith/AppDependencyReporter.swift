import Foundation

struct DependencyFinding: Equatable, Hashable {
    let name: String
    let path: String
}

struct AppDependencyReport: Equatable {
    let executable: String
    let bundled: [DependencyFinding]
    let hostProvided: [DependencyFinding]
    let unresolved: [String]
    let interpreter: String?

    var description: String {
        var sections = ["Dependency report for \(executable)"]
        sections.append(section("Present in AppDir", findings: bundled))
        sections.append(section("Resolved from this host", findings: hostProvided))
        sections.append(section("Unresolved", names: unresolved))
        if let interpreter {
            sections.append("ELF interpreter: \(interpreter) (provided by the host)")
        }
        sections.append(
            "AppDir matches are based on dependency file names and may need launcher search-path configuration. Resolution uses this host's library search rules. Runtime-loaded plugins and libraries opened with dlopen are not detected."
        )
        return sections.joined(separator: "\n\n")
    }

    private func section(_ title: String, findings: [DependencyFinding]) -> String {
        let entries = findings.map { "  \($0.name) -> \($0.path)" }
        return ([ "\(title) (\(findings.count))" ] + entries).joined(separator: "\n")
    }

    private func section(_ title: String, names: [String]) -> String {
        let entries = names.map { "  \($0)" }
        return ([ "\(title) (\(names.count))" ] + entries).joined(separator: "\n")
    }
}

enum AppDependencyError: LocalizedError {
    case inputNotFound(String)
    case invalidAppDir(String)
    case executableOutsideAppDir(String)
    case invalidExecutable(String)
    case toolNotFound(String)
    case inspectionFailed(status: Int32, output: String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .inputNotFound(let path):
            "Input does not exist: \(path)"
        case .invalidAppDir(let path):
            "AppDir must be an existing directory: \(path)"
        case .executableOutsideAppDir(let path):
            "Executable must be inside the AppDir: \(path)"
        case .invalidExecutable(let path):
            "Executable must be a regular ELF file: \(path)"
        case .toolNotFound(let tool):
            "Required tool '\(tool)' was not found in PATH. Install pax-utils to provide lddtree."
        case .inspectionFailed(let status, let output):
            output.isEmpty
                ? "lddtree failed with exit status \(status)."
                : "lddtree failed with exit status \(status):\n\(output)"
        case .invalidOutput(let output):
            "Could not parse lddtree output:\n\(output)"
        }
    }
}

struct AppDependencyReporter {
    private let fileManager = FileManager.default
    private let lddtreeURL: URL?

    init(lddtreeURL: URL? = nil) {
        self.lddtreeURL = lddtreeURL
    }

    func report(appDirURL: URL, executablePath: String) throws -> AppDependencyReport {
        let resolvedAppDirURL = appDirURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedAppDirURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw AppDependencyError.invalidAppDir(resolvedAppDirURL.path)
        }

        let requestedExecutableURL = URL(
            fileURLWithPath: executablePath,
            relativeTo: resolvedAppDirURL
        ).standardizedFileURL
        let resolvedExecutableURL = requestedExecutableURL.resolvingSymlinksInPath()
        guard isInside(resolvedExecutableURL, directory: resolvedAppDirURL) else {
            throw AppDependencyError.executableOutsideAppDir(requestedExecutableURL.path)
        }
        guard fileManager.fileExists(atPath: requestedExecutableURL.path) else {
            throw AppDependencyError.inputNotFound(requestedExecutableURL.path)
        }
        guard try isRegularFile(requestedExecutableURL),
              try isELFFile(requestedExecutableURL) else {
            throw AppDependencyError.invalidExecutable(requestedExecutableURL.path)
        }

        let toolURL = try lddtreeURL ?? executableURL(named: "lddtree")
        let relativeExecutablePath = String(
            resolvedExecutableURL.path.dropFirst(resolvedAppDirURL.path.count)
        )
        let rootedExecutablePath = relativeExecutablePath.hasPrefix("/")
            ? relativeExecutablePath
            : "/\(relativeExecutablePath)"
        let process = Process()
        process.executableURL = toolURL
        process.arguments = ["-R", resolvedAppDirURL.path, rootedExecutablePath]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(decoding: outputData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw AppDependencyError.inspectionFailed(
                status: process.terminationStatus,
                output: output
            )
        }

        let appDirLibraries = try libraryPaths(in: resolvedAppDirURL)
        return try parse(
            output,
            executable: resolvedExecutableURL,
            appDirURL: resolvedAppDirURL,
            appDirLibraries: appDirLibraries
        )
    }

    private func parse(
        _ output: String,
        executable: URL,
        appDirURL: URL,
        appDirLibraries: [String: [URL]]
    ) throws -> AppDependencyReport {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard let rootLine = lines.first else {
            throw AppDependencyError.invalidOutput(output)
        }
        let interpreter = interpreterPath(in: rootLine, appDirURL: appDirURL)
        let interpreterName = interpreter.map { URL(fileURLWithPath: $0).lastPathComponent }

        var bundled = Set<DependencyFinding>()
        var hostProvided = Set<DependencyFinding>()
        var unresolved = Set<String>()
        for line in lines.dropFirst() {
            guard let separator = line.range(of: " => ") else {
                continue
            }
            let name = line[..<separator.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            let resolvedPath = line[separator.upperBound...]
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                continue
            }
            if resolvedPath == "not found" {
                guard name != interpreterName else {
                    continue
                }
                unresolved.insert(name)
                continue
            }
            guard resolvedPath.hasPrefix("/") else {
                continue
            }

            let dependencyURL = URL(fileURLWithPath: resolvedPath)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            if isInside(dependencyURL, directory: appDirURL) {
                bundled.insert(DependencyFinding(
                    name: name,
                    path: relativePath(of: dependencyURL, to: appDirURL)
                ))
            } else {
                hostProvided.insert(DependencyFinding(name: name, path: resolvedPath))
            }
            for candidateURL in appDirLibraries[name, default: []] {
                bundled.insert(DependencyFinding(
                    name: name,
                    path: relativePath(of: candidateURL, to: appDirURL)
                ))
            }
        }
        for name in unresolved {
            for candidateURL in appDirLibraries[name, default: []] {
                bundled.insert(DependencyFinding(
                    name: name,
                    path: relativePath(of: candidateURL, to: appDirURL)
                ))
            }
        }

        return AppDependencyReport(
            executable: executable.path,
            bundled: bundled.sorted(by: findingOrder),
            hostProvided: hostProvided.sorted(by: findingOrder),
            unresolved: unresolved.sorted(),
            interpreter: interpreter
        )
    }

    private func interpreterPath(in rootLine: String, appDirURL: URL) -> String? {
        guard let start = rootLine.range(of: "(interpreter => ") else {
            return nil
        }
        let interpreterStart = start.upperBound
        guard let end = rootLine[interpreterStart...].firstIndex(of: ")") else {
            return nil
        }
        let path = String(rootLine[interpreterStart..<end])
        let appDirPrefix = appDirURL.path + "/"
        guard path.hasPrefix(appDirPrefix) else {
            return path
        }
        return "/" + path.dropFirst(appDirPrefix.count)
    }

    private func isInside(_ url: URL, directory: URL) -> Bool {
        let path = url.standardizedFileURL.pathComponents
        let parent = directory.standardizedFileURL.pathComponents
        return path.count > parent.count && path.prefix(parent.count).elementsEqual(parent)
    }

    private func isRegularFile(_ url: URL) throws -> Bool {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return attributes[.type] as? FileAttributeType == .typeRegular
    }

    private func libraryPaths(in appDirURL: URL) throws -> [String: [URL]] {
        guard let enumerator = fileManager.enumerator(
            at: appDirURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ) else {
            throw AppDependencyError.invalidAppDir(appDirURL.path)
        }

        var pathsByName: [String: [URL]] = [:]
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true || values.isSymbolicLink == true else {
                continue
            }
            pathsByName[fileURL.lastPathComponent, default: []].append(fileURL)
        }
        return pathsByName
    }

    private func relativePath(of url: URL, to directory: URL) -> String {
        String(url.path.dropFirst(directory.path.count + 1))
    }

    private func isELFFile(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        let header = try handle.read(upToCount: 4)
        try handle.close()
        return header?.elementsEqual([0x7F, 0x45, 0x4C, 0x46]) == true
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
        throw AppDependencyError.toolNotFound(name)
    }

    private func findingOrder(_ lhs: DependencyFinding, _ rhs: DependencyFinding) -> Bool {
        (lhs.name, lhs.path) < (rhs.name, rhs.path)
    }
}
