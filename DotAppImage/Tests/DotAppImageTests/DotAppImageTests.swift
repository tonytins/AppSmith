import Foundation
import Testing
@testable import DotAppImage

@Test func createsBundleWithManifestLauncherDesktopEntryAndAssets() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("DotAppImageTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let appImageURL = rootURL.appendingPathComponent("sample.AppImage")
    let iconURL = rootURL.appendingPathComponent("icon.svg")
    let assetURL = rootURL.appendingPathComponent("data.json")
    try Data("fake appimage".utf8).write(to: appImageURL)
    try Data("<svg/>".utf8).write(to: iconURL)
    try Data("{\"ready\":true}".utf8).write(to: assetURL)

    let outputURL = rootURL.appendingPathComponent("Sample App.app", isDirectory: true)
    let options = BundleOptions(
        name: "Sample App",
        identifier: "dev.example.sample",
        version: "1.2.3",
        appImagePath: appImageURL,
        iconPath: iconURL,
        assetPaths: [assetURL],
        outputPath: outputURL
    )

    let bundleURL = try AppBundleBuilder().createBundle(options)
    let manifestData = try Data(contentsOf: bundleURL.appendingPathComponent("Contents/Manifest.json"))
    let manifest = try JSONDecoder().decode(BundleManifest.self, from: manifestData)

    #expect(manifest == BundleManifest(
        formatVersion: 1,
        identifier: "dev.example.sample",
        name: "Sample App",
        version: "1.2.3",
        executable: "Contents/Linux/AppImage",
        icon: "Contents/Resources/AppIcon.svg",
        assets: ["Contents/Resources/Assets/data.json"]
    ))
    #expect(try String(contentsOf: bundleURL.appendingPathComponent("AppRun"), encoding: .utf8)
        .contains("Contents/Linux/AppImage"))
    #expect(try Data(contentsOf: bundleURL.appendingPathComponent("Contents/Resources/Assets/data.json"))
        == Data("{\"ready\":true}".utf8))
    #expect(try String(contentsOf: bundleURL.appendingPathComponent("dev.example.sample.desktop"), encoding: .utf8)
        .contains("Name=Sample App"))
    #expect(try String(contentsOf: bundleURL.appendingPathComponent("dev.example.sample.desktop"), encoding: .utf8)
        .contains("Comment=Launch Sample App"))
    #expect(try String(contentsOf: bundleURL.appendingPathComponent("dev.example.sample.desktop"), encoding: .utf8)
        .contains("Exec=dotappimage open \"\(bundleURL.path)\" %U"))

    let executableAttributes = try FileManager.default.attributesOfItem(
        atPath: bundleURL.appendingPathComponent("Contents/Linux/AppImage").path
    )
    let permissions = executableAttributes[.posixPermissions] as? Int
    #expect(permissions == 0o755)
}

@Test func refusesToReplaceAnExistingBundle() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("DotAppImageTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let appImageURL = rootURL.appendingPathComponent("sample.AppImage")
    try Data("fake appimage".utf8).write(to: appImageURL)
    let outputURL = rootURL.appendingPathComponent("Existing.app", isDirectory: true)
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: false)
    let markerURL = outputURL.appendingPathComponent("keep.txt")
    try Data("keep".utf8).write(to: markerURL)

    let options = BundleOptions(
        name: "Sample",
        identifier: "dev.example.sample",
        version: "1",
        appImagePath: appImageURL,
        iconPath: nil,
        assetPaths: [],
        outputPath: outputURL
    )

    #expect(throws: BundleError.self) {
        try AppBundleBuilder().createBundle(options)
    }
    #expect(FileManager.default.fileExists(atPath: markerURL.path))
}

@Test func parsesBundleCommandAndRepeatedAssets() throws {
    let command = try DotAppImage.parseAsRoot([
        "bundle",
        "--name", "Sample",
        "--identifier", "dev.example.sample",
        "--version", "1",
        "--appimage", "sample.AppImage",
        "--asset", "one.json",
        "--asset", "two.json",
        "--output", "Sample.app"
    ])

    let bundleCommand = try #require(command as? DotAppImage.Bundle)
    #expect(bundleCommand.name == "Sample")
    #expect(bundleCommand.appImage == "sample.AppImage")
    #expect(bundleCommand.asset == ["one.json", "two.json"])
    #expect(bundleCommand.output == "Sample.app")
}

@Test func parsesBuildCommand() throws {
    let command = try DotAppImage.parseAsRoot([
        "build",
        "--appdir", "./Sample.AppDir",
        "--runtime", "./runtime-x86_64",
        "--output", "./Sample.AppImage"
    ])

    let buildCommand = try #require(command as? DotAppImage.Build)
    #expect(buildCommand.appdir == "./Sample.AppDir")
    #expect(buildCommand.runtime == "./runtime-x86_64")
    #expect(buildCommand.output == "./Sample.AppImage")
}

@Test func parsesOpenCommand() throws {
    let command = try DotAppImage.parseAsRoot([
        "open",
        "./Sample.app",
        "https://example.com/item"
    ])

    let openCommand = try #require(command as? DotAppImage.Open)
    #expect(openCommand.app == "./Sample.app")
    #expect(openCommand.arguments == ["https://example.com/item"])
}

@Test func parsesInstallAndUninstallCommands() throws {
    let install = try DotAppImage.parseAsRoot(["install", "./Sample.app"])
    let uninstall = try DotAppImage.parseAsRoot(["uninstall", "./Sample.app"])

    #expect((install as? DotAppImage.Install)?.app == "./Sample.app")
    #expect((uninstall as? DotAppImage.Uninstall)?.app == "./Sample.app")
}

@Test func rejectsUnknownCLIOptions() {
    #expect(throws: (any Error).self) {
        try DotAppImage.parseAsRoot(["bundle", "--unknown", "value"])
    }
}

@Test func opensBundleUsingItsAppRun() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("DotAppImageTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let markerURL = rootURL.appendingPathComponent("launched")
    let bundleURL = rootURL.appendingPathComponent("Sample.app", isDirectory: true)
    try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: false)
    let appRunURL = bundleURL.appendingPathComponent("AppRun")
    try Data("#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(markerURL.path)'\n".utf8).write(to: appRunURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appRunURL.path)

    try AppBundleOpener().open(bundleURL, arguments: ["argument with spaces", "https://example.com"])

    let expectedOutput = "argument with spaces\nhttps://example.com\n"
    var output = ""
    for _ in 0..<100 where output != expectedOutput {
        Thread.sleep(forTimeInterval: 0.01)
        output = (try? String(contentsOf: markerURL, encoding: .utf8)) ?? ""
    }
    #expect(output == expectedOutput)
}

@Test func refusesToOpenBundleWithoutExecutableAppRun() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("DotAppImageTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let bundleURL = rootURL.appendingPathComponent("Invalid.app", isDirectory: true)
    try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: false)

    #expect(throws: AppBundleOpenError.self) {
        try AppBundleOpener().open(bundleURL)
    }
}

@Test func installsAndUninstallsDesktopEntrySymlink() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("DotAppImageTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let appImageURL = rootURL.appendingPathComponent("sample.AppImage")
    let iconURL = rootURL.appendingPathComponent("icon.svg")
    try Data("fake appimage".utf8).write(to: appImageURL)
    try Data("<svg/>".utf8).write(to: iconURL)
    let bundleURL = rootURL.appendingPathComponent("Sample.app", isDirectory: true)
    _ = try AppBundleBuilder().createBundle(BundleOptions(
        name: "Sample",
        identifier: "dev.example.sample",
        version: "1",
        appImagePath: appImageURL,
        iconPath: iconURL,
        assetPaths: [],
        outputPath: bundleURL
    ))
    let applicationsURL = rootURL.appendingPathComponent("applications", isDirectory: true)
    let installer = try AppBundleInstaller(applicationsDirectory: applicationsURL)

    let installedEntryURL = try installer.install(bundleURL)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: installedEntryURL.path)
        == bundleURL.appendingPathComponent("dev.example.sample.desktop").path)
    #expect(try installer.install(bundleURL) == installedEntryURL)

    let desktopEntry = try String(contentsOf: installedEntryURL, encoding: .utf8)
    #expect(desktopEntry.contains("Name=Sample"))
    #expect(desktopEntry.contains("Exec=dotappimage open \"\(bundleURL.path)\" %U"))
    #expect(desktopEntry.contains("Icon=\(bundleURL.path)/Contents/Resources/AppIcon.svg"))

    #expect(try installer.uninstall(bundleURL) == installedEntryURL)
    #expect(!FileManager.default.fileExists(atPath: installedEntryURL.path))
    #expect(FileManager.default.fileExists(
        atPath: bundleURL.appendingPathComponent("dev.example.sample.desktop").path
    ))
}

@Test func refusesToReplaceAnUnmanagedDesktopEntry() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("DotAppImageTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let appImageURL = rootURL.appendingPathComponent("sample.AppImage")
    try Data("fake appimage".utf8).write(to: appImageURL)
    let bundleURL = rootURL.appendingPathComponent("Sample.app", isDirectory: true)
    _ = try AppBundleBuilder().createBundle(BundleOptions(
        name: "Sample",
        identifier: "dev.example.sample",
        version: "1",
        appImagePath: appImageURL,
        iconPath: nil,
        assetPaths: [],
        outputPath: bundleURL
    ))
    let applicationsURL = rootURL.appendingPathComponent("applications", isDirectory: true)
    try FileManager.default.createDirectory(at: applicationsURL, withIntermediateDirectories: true)
    let existingEntryURL = applicationsURL.appendingPathComponent("dev.example.sample.desktop")
    try Data("keep".utf8).write(to: existingEntryURL)
    let installer = try AppBundleInstaller(applicationsDirectory: applicationsURL)

    #expect(throws: AppBundleInstallError.self) {
        try installer.install(bundleURL)
    }
    #expect(try String(contentsOf: existingEntryURL, encoding: .utf8) == "keep")
}

@Test func buildsExecutableAppImageFromAppDir() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("DotAppImageTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let appDirURL = rootURL.appendingPathComponent("Sample.AppDir", isDirectory: true)
    try FileManager.default.createDirectory(at: appDirURL, withIntermediateDirectories: true)
    let appRunURL = appDirURL.appendingPathComponent("AppRun")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: appRunURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appRunURL.path)
    try Data("payload".utf8).write(to: appDirURL.appendingPathComponent("payload.txt"))

    let runtimeURL = rootURL.appendingPathComponent("runtime")
    let runtimePrefix = Data([0x7F, 0x45, 0x4C, 0x46, 0x01, 0x02, 0x03])
    try runtimePrefix.write(to: runtimeURL)
    let outputURL = rootURL.appendingPathComponent("Sample.AppImage")
    let options = AppImageOptions(appDirPath: appDirURL, runtimePath: runtimeURL, outputPath: outputURL)

    let imageURL = try AppImageBuilder().build(options)
    let imageData = try Data(contentsOf: imageURL, options: .mappedIfSafe)

    #expect(imageData.starts(with: runtimePrefix))
    #expect(imageData.range(of: Data([0x68, 0x73, 0x71, 0x73])) != nil)
    let attributes = try FileManager.default.attributesOfItem(atPath: imageURL.path)
    #expect(attributes[.posixPermissions] as? Int == 0o755)

    let nestedOutputURL = appDirURL.appendingPathComponent("Nested.AppImage")
    let nestedOptions = AppImageOptions(
        appDirPath: appDirURL,
        runtimePath: runtimeURL,
        outputPath: nestedOutputURL
    )
    #expect(throws: AppImageError.self) {
        try AppImageBuilder().build(nestedOptions)
    }
    #expect(!FileManager.default.fileExists(atPath: nestedOutputURL.path))
}

@Test func launcherRunsPayloadAndForwardsArguments() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("DotAppImageTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let appImageURL = rootURL.appendingPathComponent("sample.AppImage")
    try Data("#!/bin/sh\nprintf '<%s>\\n' \"$@\"\n".utf8).write(to: appImageURL)
    let outputURL = rootURL.appendingPathComponent("Sample.app", isDirectory: true)
    let options = BundleOptions(
        name: "Sample",
        identifier: "dev.example.sample",
        version: "1",
        appImagePath: appImageURL,
        iconPath: nil,
        assetPaths: [],
        outputPath: outputURL
    )
    let bundleURL = try AppBundleBuilder().createBundle(options)

    let process = Process()
    process.executableURL = bundleURL.appendingPathComponent("AppRun")
    process.arguments = ["argument with spaces", "--flag"]
    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    try process.run()
    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)

    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    #expect(output == "<argument with spaces>\n<--flag>\n")
}
