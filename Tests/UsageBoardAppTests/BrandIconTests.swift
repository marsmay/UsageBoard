import AppKit
import XCTest
import UsageBoardCore
@testable import UsageBoardApp

final class BrandIconTests: XCTestCase {
    private var resources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
    }

    func testEveryBundledPluginHasDecodableLightAndDarkLocalIcons() throws {
        let plugins = try FileManager.default.contentsOfDirectory(
            at: resources.appendingPathComponent("BundledPlugins"), includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "py" && !$0.lastPathComponent.hasPrefix("_") }
        XCTAssertEqual(plugins.count, 8)
        for plugin in plugins {
            let metadata = try XCTUnwrap(PluginMetadataParser.parse(fileURL: plugin))
            let path = try XCTUnwrap(metadata.icon)
            XCTAssertTrue(path.hasPrefix("icons/light/"), plugin.lastPathComponent)
            for isDark in [false, true] {
                let url = try XCTUnwrap(BrandIconSource.url(
                    for: path, isDark: isDark, resourceDirectoryURL: resources
                ))
                XCTAssertTrue(url.isFileURL)
                XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, isDark ? "dark" : "light")
                let image = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
                XCTAssertGreaterThanOrEqual(image.pixelsWide, 44)
                XCTAssertGreaterThanOrEqual(image.pixelsHigh, 44)
                if plugin.lastPathComponent == "codex-usage-plugin.py" {
                    XCTAssertTrue(image.hasAlpha)
                    XCTAssertEqual(image.colorAt(x: 0, y: 0)?.alphaComponent, 0)
                    XCTAssertEqual(image.pixelsWide, 640)
                    XCTAssertEqual(image.pixelsHigh, 640)
                    XCTAssertEqual(image.colorAt(x: 320, y: 60)?.alphaComponent, 1)
                    let glyph = try XCTUnwrap(image.colorAt(x: 400, y: 405)?.usingColorSpace(.deviceRGB))
                    XCTAssertEqual(glyph.alphaComponent, 1)
                    XCTAssertGreaterThan(glyph.redComponent, 0.98)
                    XCTAssertGreaterThan(glyph.greenComponent, 0.98)
                    XCTAssertGreaterThan(glyph.blueComponent, 0.98)
                }
            }
        }
    }

    func testMissingDarkVariantFallsBackToConfiguredLightPath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let light = root.appendingPathComponent("icons/light/example.png")
        let dark = root.appendingPathComponent("icons/dark/example.png")
        try FileManager.default.createDirectory(at: light.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(contentsOf: resources.appendingPathComponent("icons/light/kimi.png")).write(to: light)
        XCTAssertEqual(BrandIconSource.url(for: "icons/light/example.png", isDark: true, resourceDirectoryURL: root), light)
        try FileManager.default.createDirectory(at: dark.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: resources.appendingPathComponent("icons/dark/kimi.png")).write(to: dark)
        XCTAssertEqual(BrandIconSource.url(for: "icons/light/example.png", isDark: true, resourceDirectoryURL: root), dark)
        XCTAssertEqual(BrandIconSource.url(for: "icons/light/example.png", isDark: false, resourceDirectoryURL: root), light)
    }

    func testRemoteAndAbsoluteFilePathsRemainCompatible() {
        let remote = "https://example.com/light/icon.png"
        let local = resources.appendingPathComponent("icons/light/kimi.png")
        for isDark in [false, true] {
            XCTAssertEqual(BrandIconSource.url(for: remote, isDark: isDark)?.absoluteString, remote)
            XCTAssertEqual(BrandIconSource.url(for: local.path, isDark: isDark), local)
            XCTAssertEqual(BrandIconSource.url(for: local.absoluteString, isDark: isDark), local)
        }
        XCTAssertNil(BrandIconSource.url(for: nil, isDark: false))
        XCTAssertNil(BrandIconSource.url(for: "", isDark: false))
        XCTAssertNil(BrandIconSource.url(for: "ftp://example.com/icon.png", isDark: false))
    }

    @MainActor
    func testLocalLoaderDecodesCachesAndKeepsThemeVariantsSeparate() async throws {
        let cache = BrandIconCache()
        let lightURL = resources.appendingPathComponent("icons/light/kimi.png")
        let darkURL = resources.appendingPathComponent("icons/dark/kimi.png")
        let lightResult = await cache.image(for: lightURL)
        let light = try XCTUnwrap(lightResult)
        let cached = await cache.image(for: lightURL)
        XCTAssertTrue(light === cached)
        let darkResult = await cache.image(for: darkURL)
        let dark = try XCTUnwrap(darkResult)
        XCTAssertFalse(light === dark)
        XCTAssertNotEqual(light.tiffRepresentation, dark.tiffRepresentation)
        let missing = await cache.image(for: resources.appendingPathComponent("missing.png"))
        XCTAssertNil(missing)
    }

    // MARK: - Remote download limits (M10)

    private struct StubResponse {
        var statusCode: Int = 200
        var body = Data()
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
                headers["Content-Length"] = String(stub.body.count)
            }
            let response = HTTPURLResponse(url: url, statusCode: stub.statusCode,
                                           httpVersion: nil, headerFields: headers)!
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: stub.body)
            if !stub.keepsOpen { client.urlProtocolDidFinishLoading(self) }
        }

        override func stopLoading() {}
    }

    private func makeRemoteCache() -> BrandIconCache {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 2
        return BrandIconCache(session: URLSession(configuration: config))
    }

    private let remoteURL = URL(string: "https://example.com/icon.png")!

    func testRemoteIconWithinLimitLoads() async throws {
        StubURLProtocol.response = StubResponse(
            body: try Data(contentsOf: resources.appendingPathComponent("icons/light/kimi.png"))
        )
        let image = await makeRemoteCache().image(for: remoteURL)
        XCTAssertNotNil(image)
    }

    func testRemoteIconOverDeclaredLimitFallsBackToPlaceholder() async throws {
        StubURLProtocol.response = StubResponse(body: Data(repeating: 0x61, count: BrandIconCache.maxRemoteBytes + 1))
        let image = await makeRemoteCache().image(for: remoteURL)
        XCTAssertNil(image)
    }

    func testRemoteIconUnknownLengthStreamingOverLimitFails() async throws {
        StubURLProtocol.response = StubResponse(
            body: Data(repeating: 0x61, count: BrandIconCache.maxRemoteBytes + 1),
            declaresLength: false
        )
        let image = await makeRemoteCache().image(for: remoteURL)
        XCTAssertNil(image)
    }

    func testRemoteIconHTTPFailureFallsBackToPlaceholder() async throws {
        StubURLProtocol.response = StubResponse(statusCode: 404, body: Data("nope".utf8))
        let image = await makeRemoteCache().image(for: remoteURL)
        XCTAssertNil(image)
    }

    func testRemoteIconCancellationKeepsPlaceholder() async throws {
        StubURLProtocol.response = StubResponse(hangs: true)
        let cache = makeRemoteCache()
        let url = remoteURL
        let task = Task { await cache.image(for: url) }
        task.cancel()
        let image = await task.value
        XCTAssertNil(image)
    }

    func testOversizedOpenStreamIsCancelledInsteadOfOnlyDiscarded() async throws {
        for declaresLength in [true, false] {
            StubURLProtocol.response = StubResponse(
                body: Data(repeating: 0x61, count: BrandIconCache.maxRemoteBytes + 1),
                declaresLength: declaresLength, keepsOpen: true)
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [StubURLProtocol.self]
            config.timeoutIntervalForResource = 5
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            let cache = BrandIconCache(session: session)
            let start = Date()
            let image = await cache.image(for: remoteURL)
            XCTAssertNil(image)
            XCTAssertLessThan(Date().timeIntervalSince(start), 3, "must reject before the resource timeout")
            try await Task.sleep(for: .milliseconds(100))
            let tasks = await withCheckedContinuation { continuation in
                session.getAllTasks { continuation.resume(returning: $0) }
            }
            XCTAssertTrue(tasks.isEmpty, "discarded icon must not keep downloading")
        }
    }

    func testRemoteIconTimeoutKeepsPlaceholder() async throws {
        StubURLProtocol.response = StubResponse(hangs: true)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.timeoutIntervalForResource = 0.2
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let start = Date()
        let image = await BrandIconCache(session: session).image(for: remoteURL)
        XCTAssertNil(image)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
}
