@preconcurrency import Foundation
import XCTest
@testable import UsageBoardCore

/// H1a: download resource limits for update packages. All responses come from
/// a URLProtocol stub; no real network is used.
final class UpdateDownloaderLimitTests: XCTestCase {
    /// Stubbed responses. `chunks` are delivered in order; when `hangs` is
    /// true the request never completes (used for timeout/cancellation).
    private struct StubResponse {
        var statusCode: Int = 200
        var chunks: [Data] = []
        var declaresLength: Bool = true
        var hangs: Bool = false
        var keepsOpen: Bool = false
    }

    private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var response = StubResponse()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let stub = Self.response
            guard !stub.hangs, let client, let url = request.url else { return }
            var headers: [String: String] = [:]
            if stub.declaresLength {
                headers["Content-Length"] = String(stub.chunks.reduce(0) { $0 + $1.count })
            }
            let response = HTTPURLResponse(url: url, statusCode: stub.statusCode,
                                           httpVersion: nil, headerFields: headers)!
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in stub.chunks {
                client.urlProtocol(self, didLoad: chunk)
            }
            if !stub.keepsOpen { client.urlProtocolDidFinishLoading(self) }
        }

        override func stopLoading() {}
    }

    private func makeDownloader(maxBytes: Int64 = 1024, resourceTimeout: TimeInterval = 5) -> UpdateDownloader {
        UpdateDownloader(maxDownloadBytes: maxBytes) {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [StubURLProtocol.self]
            config.timeoutIntervalForRequest = 2
            config.timeoutIntervalForResource = resourceTimeout
            return config
        }
    }

    private let url = URL(string: "https://example.com/update.zip")!

    private func updateTempURLs() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? []
        return Set(names.filter { $0.hasPrefix("usageboard-download-") || $0.hasPrefix("usageboard-update-") })
    }

    /// Builds a zip containing a minimal valid UsageBoard.app (ditto, like release.sh).
    private func makeUpdateZip(version: String = "9.9.9") throws -> Data {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-fixture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("UsageBoard.app/Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let binary = macOS.appendingPathComponent("UsageBoard")
        try "#!/bin/sh\nexit 0".write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let plist = ["CFBundleIdentifier": "ltd.may.UsageBoard", "CFBundleExecutable": "UsageBoard",
                     "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let zipURL = root.appendingPathComponent("update.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent",
                             root.appendingPathComponent("UsageBoard.app").path, zipURL.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return try Data(contentsOf: zipURL)
    }

    func testSuccessfulDownloadWithinLimit() async throws {
        StubURLProtocol.response = StubResponse(chunks: [try makeUpdateZip()])
        let before = updateTempURLs()
        let result = try await makeDownloader(maxBytes: 8 * 1024 * 1024).download(from: url, expectedVersion: "9.9.9")
        defer { try? FileManager.default.removeItem(at: result.cleanupDirectoryURL) }
        XCTAssertEqual(result.appURL.lastPathComponent, "UsageBoard.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.appURL.path))
        XCTAssertEqual(before.union([result.cleanupDirectoryURL.lastPathComponent]), updateTempURLs(),
                       "only the returned extraction directory may remain after success")
    }

    func testDeclaredLengthOverLimitFailsBeforeTransferCompletes() async throws {
        StubURLProtocol.response = StubResponse(chunks: [Data(repeating: 0x61, count: 4096)], keepsOpen: true)
        let before = updateTempURLs()
        let start = Date()
        await assertThrowsDownloadTooLarge(try await makeDownloader().download(from: url))
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        XCTAssertEqual(before, updateTempURLs())
    }

    func testUnknownLengthStreamingOverLimitFailsMidTransfer() async throws {
        // Chunks arrive without a declared length; the running byte count must
        // still enforce the cap rather than checking size after completion.
        StubURLProtocol.response = StubResponse(
            chunks: [Data(repeating: 0x61, count: 700), Data(repeating: 0x62, count: 700)],
            declaresLength: false, keepsOpen: true
        )
        let before = updateTempURLs()
        let start = Date()
        await assertThrowsDownloadTooLarge(try await makeDownloader().download(from: url))
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        XCTAssertEqual(before, updateTempURLs())
    }

    func testHangingTransferHitsTotalTimeBudget() async throws {
        StubURLProtocol.response = StubResponse(hangs: true)
        let before = updateTempURLs()
        let start = Date()
        do {
            _ = try await makeDownloader(resourceTimeout: 0.5).download(from: url)
            XCTFail("hanging download must fail")
        } catch {
            XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        }
        XCTAssertEqual(before, updateTempURLs())
    }

    func testCallerCancellationAbortsDownload() async throws {
        StubURLProtocol.response = StubResponse(hangs: true)
        let before = updateTempURLs()
        let downloader = makeDownloader(resourceTimeout: 60)
        let downloadURL = url
        let task = Task {
            try await downloader.download(from: downloadURL)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("cancelled download must throw")
        } catch {
            XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled,
                          "unexpected error: \(error)")
        }
        XCTAssertEqual(before, updateTempURLs())
    }

    func testMalformedZipFailsExtractionAndCleansUp() async throws {
        StubURLProtocol.response = StubResponse(chunks: [Data("not a zip".utf8)])
        let before = updateTempURLs()
        do {
            _ = try await makeDownloader().download(from: url)
            XCTFail("malformed zip must fail")
        } catch let error as UpdateError {
            guard case .extractionFailed = error else {
                return XCTFail("expected extractionFailed, got \(error)")
            }
        }
        XCTAssertEqual(before, updateTempURLs())
    }

    func testHTTPFailureIsRejected() async throws {
        StubURLProtocol.response = StubResponse(statusCode: 500, chunks: [Data("oops".utf8)])
        let before = updateTempURLs()
        do {
            _ = try await makeDownloader().download(from: url)
            XCTFail("HTTP 500 must fail")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .badServerResponse)
        }
        XCTAssertEqual(before, updateTempURLs())
    }

    private func assertThrowsDownloadTooLarge(
        _ expression: @autoclosure () async throws -> DownloadedUpdate,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            let result = try await expression()
            try? FileManager.default.removeItem(at: result.cleanupDirectoryURL)
            XCTFail("expected downloadTooLarge", file: file, line: line)
        } catch let error as UpdateError {
            guard case .downloadTooLarge = error else {
                return XCTFail("expected downloadTooLarge, got \(error)", file: file, line: line)
            }
        } catch {
            XCTFail("expected downloadTooLarge, got \(error)", file: file, line: line)
        }
    }
}
