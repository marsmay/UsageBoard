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
        XCTAssertEqual(plugins.count, 7)
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
}
