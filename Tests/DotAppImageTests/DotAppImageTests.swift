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
        .contains("Exec=\"\(bundleURL.path)/AppRun\" %U"))

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

@Test func parsesCreateCommandAndRepeatedAssets() throws {
    let command = try DotAppImage.parseAsRoot([
        "create",
        "--name", "Sample",
        "--identifier", "dev.example.sample",
        "--version", "1",
        "--appimage", "sample.AppImage",
        "--asset", "one.json",
        "--asset", "two.json",
        "--output", "Sample.app"
    ])

    let createCommand = try #require(command as? DotAppImage.Create)
    #expect(createCommand.name == "Sample")
    #expect(createCommand.appImage == "sample.AppImage")
    #expect(createCommand.asset == ["one.json", "two.json"])
    #expect(createCommand.output == "Sample.app")
}

@Test func rejectsUnknownCLIOptions() {
    #expect(throws: (any Error).self) {
        try DotAppImage.parseAsRoot(["create", "--unknown", "value"])
    }
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
