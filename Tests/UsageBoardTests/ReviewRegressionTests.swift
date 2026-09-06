@preconcurrency import Foundation
import XCTest
@testable import UsageBoardCore

final class ReviewRegressionTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-review-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testConfigurationSecretsRemainOwnerOnlyAfterRepeatedSaves() throws {
        let url = try temporaryDirectory().appendingPathComponent("config.json")
        let store = ConfigStore(fileURL: url)
        for _ in 0..<2 {
            try store.save(AppConfiguration())
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            _ = try store.load()
        }
    }

    func testUsageFormattingHandlesValuesOutsideIntegerRange() {
        var item = UsageItem(id: "large", name: "Large", used: 1e30, limit: 2e30, displayStyle: .ratio)
        XCTAssertEqual(item.progress, 0.5)
        XCTAssertTrue(item.displayValue().contains(" / "))
        item.used = .infinity
        XCTAssertTrue(item.displayValue().hasPrefix("-- / "))
        item.displayStyle = .percent
        XCTAssertEqual(item.displayValue(), "0%")
    }

    func testExecutorHonorsErrorEvenWhenSuccessFieldsExist() throws {
        let root = try temporaryDirectory()
        let script = root.appendingPathComponent("error.py")
        try "print('{\"updatedAt\":\"2026-01-01T00:00:00Z\",\"items\":[],\"error\":\"expired\"}')"
            .write(to: script, atomically: true, encoding: .utf8)
        let snapshot = PluginExecutor().run(configuration: .init(name: "Test", executablePath: script.path),
                                            displayName: "Test", language: .en)
        XCTAssertEqual(snapshot.state, .failed("expired"))
    }

    func testExecutorBoundsOutputAndDoesNotWriteBytecode() throws {
        let root = try temporaryDirectory()
        try "value = 1".write(to: root.appendingPathComponent("helper.py"), atomically: true, encoding: .utf8)
        let script = root.appendingPathComponent("large.py")
        try "import helper\nprint('x' * (9 * 1024 * 1024))"
            .write(to: script, atomically: true, encoding: .utf8)
        let snapshot = PluginExecutor().run(configuration: .init(name: "Test", executablePath: script.path),
                                            displayName: "Test", language: .en)
        XCTAssertEqual(snapshot.state, .failed("Plugin output exceeds the 8 MiB limit"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("__pycache__").path))
    }

    func testExecutorCancellationStopsLongRunningProcess() async throws {
        let root = try temporaryDirectory()
        let script = root.appendingPathComponent("slow.py")
        let marker = root.appendingPathComponent("started")
        try "import pathlib, time\npathlib.Path(__file__).with_name('started').touch()\ntime.sleep(30)"
            .write(to: script, atomically: true, encoding: .utf8)
        let start = Date()
        let task = Task.detached {
            PluginExecutor(timeoutSeconds: 30).run(configuration: .init(name: "Test", executablePath: script.path),
                                                   displayName: "Test", language: .en)
        }
        defer { task.cancel() }
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: marker.path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "Process must start before cancellation")
        task.cancel()
        _ = await task.value
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testUpdateRejectsHTTPFailuresAndInsecureURLs() throws {
        let secure = URL(string: "https://example.com/update.zip")!
        XCTAssertNoThrow(try UpdateChecker.validateURL(secure))
        for url in ["http://example.com/update.zip", "file:///tmp/update.zip", "https://user:pass@example.com/update.zip"] {
            XCTAssertThrowsError(try UpdateChecker.validateURL(URL(string: url)!))
        }
        for code in [301, 404, 500] {
            let response = HTTPURLResponse(url: secure, statusCode: code, httpVersion: nil, headerFields: nil)!
            XCTAssertThrowsError(try UpdateChecker.validateResponse(response))
        }
    }

    func testUpdateValidatesBundleIdentityAndVersion() throws {
        let app = try temporaryDirectory().appendingPathComponent("UsageBoard.app")
        let contents = app.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let binary = macOS.appendingPathComponent("UsageBoard")
        try "#!/bin/sh\nexit 0".write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let plist = ["CFBundleIdentifier": "ltd.may.UsageBoard", "CFBundleExecutable": "UsageBoard",
                     "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.2.3"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        XCTAssertNoThrow(try UpdateDownloader.validateApp(at: app, expectedVersion: "1.2.3"))
        XCTAssertThrowsError(try UpdateDownloader.validateApp(at: app, expectedVersion: "1.2.4"))
        try FileManager.default.removeItem(at: binary)
        XCTAssertThrowsError(try UpdateDownloader.validateApp(at: app, expectedVersion: "1.2.3"))
        try FileManager.default.createDirectory(at: binary, withIntermediateDirectories: true)
        XCTAssertThrowsError(try UpdateDownloader.validateApp(at: app, expectedVersion: "1.2.3"))
    }

    func testReplacementRestoresOriginalWhenStagedMoveFails() throws {
        try runReplacement(stagedExists: false, openSucceeds: true)
    }

    func testReplacementRestoresOriginalWhenOpenFails() throws {
        try runReplacement(stagedExists: true, openSucceeds: false)
    }

    func testReplacementSucceedsWithQuotedPaths() throws {
        try runReplacement(stagedExists: true, openSucceeds: true)
    }

    private func runReplacement(stagedExists: Bool, openSucceeds: Bool) throws {
        let root = try temporaryDirectory()
        let current = root.appendingPathComponent("User's UsageBoard.app")
        let staged = root.appendingPathComponent("Staged App.app")
        let backup = root.appendingPathComponent("Backup.app")
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: current.appendingPathComponent("marker"))
        if stagedExists {
            try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
            try Data("new".utf8).write(to: staged.appendingPathComponent("marker"))
        }
        let open = root.appendingPathComponent("open")
        try "#!/bin/sh\nexit \(openSucceeds ? 0 : 1)".write(to: open, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: open.path)
        let script = root.appendingPathComponent("replace.sh")
        let logDirectory = root.appendingPathComponent("logs")
        try AppRelauncher.replacementScript(current: current, staged: staged, backup: backup, pid: Int32.max,
                                           logDirectoryURL: logDirectory)
            .write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        process.environment = ["PATH": "\(root.path):/usr/bin:/bin"]
        try process.run()
        process.waitUntilExit()
        let success = stagedExists && openSucceeds
        XCTAssertEqual(process.terminationStatus == 0, success)
        XCTAssertEqual(try String(contentsOf: current.appendingPathComponent("marker"), encoding: .utf8), success ? "new" : "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logDirectory.appendingPathComponent("relauncher.log").path))
    }
}
