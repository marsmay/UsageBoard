import UsageBoardCore
import XCTest
@testable import UsageBoardApp

@MainActor
final class PluginExecutablePathTests: XCTestCase {
    private var root: URL!
    private var pluginsDir: URL!
    private var bundlePluginsDir: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-path-\(UUID())")
        pluginsDir = root.appendingPathComponent("plugins")
        bundlePluginsDir = root.appendingPathComponent("UsageBoard.app/Contents/Resources/Plugins")
        try! FileManager.default.createDirectory(at: bundlePluginsDir, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func makeStore() -> UsageBoardStore {
        UsageBoardStore(
            configStore: ConfigStore(fileURL: root.appendingPathComponent("config.json")),
            stateStore: PluginStateStore(directoryURL: root.appendingPathComponent("states"))
        )
    }

    /// 在 app 包内创建真实插件文件，并在 plugins 目录建立同名链接，
    /// 返回（链接路径, 真实路径）。
    private func installLinkedPlugin(name: String = "demo-usage-plugin.py") throws -> (link: URL, real: URL) {
        let real = bundlePluginsDir.appendingPathComponent(name)
        try "# demo".write(to: real, atomically: true, encoding: .utf8)
        let link = pluginsDir.appendingPathComponent(name)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        return (link, real)
    }

    func testAddPluginStoresSymlinkPathWhenSelectionResolvesIntoPluginsDirectory() throws {
        let (link, real) = try installLinkedPlugin()
        // 模拟 NSOpenPanel 解析软链接后返回的真实路径
        let store = makeStore()
        store.addPlugin(fileURL: real)
        XCTAssertEqual(store.configuration.plugins.last?.executablePath, link.path)
    }

    func testAddPluginKeepsOriginalPathForFilesOutsidePluginsDirectory() throws {
        let outside = root.appendingPathComponent("standalone.py")
        try "# standalone".write(to: outside, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.addPlugin(fileURL: outside)
        XCTAssertEqual(store.configuration.plugins.last?.executablePath, outside.path)
    }

    func testAddPluginKeepsOriginalPathWhenLinkNameCollidesButTargetsDiffer() throws {
        _ = try installLinkedPlugin()
        let other = root.appendingPathComponent("demo-usage-plugin.py")
        try "# other".write(to: other, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.addPlugin(fileURL: other)
        XCTAssertEqual(store.configuration.plugins.last?.executablePath, other.path)
    }

    func testUpdatePluginNormalizesResolvedPathBackToSymlink() throws {
        let (link, real) = try installLinkedPlugin()
        let standalone = root.appendingPathComponent("standalone.py")
        try "# standalone".write(to: standalone, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.addPlugin(fileURL: standalone)

        var draft = try XCTUnwrap(store.configuration.plugins.last)
        draft.executablePath = real.path
        XCTAssertTrue(store.updatePlugin(draft))
        XCTAssertEqual(store.configuration.plugins.last?.executablePath, link.path)
    }
}
