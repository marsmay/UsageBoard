import AppKit
import SwiftUI
import UsageBoardCore
import XCTest
@testable import UsageBoardApp

@MainActor
final class PluginOrderingTests: XCTestCase {
    private func makeStore(root: URL) throws -> (UsageBoardStore, ConfigStore) {
        let config = ConfigStore(fileURL: root.appendingPathComponent("config.json"))
        let plugins = ["A", "Hidden", "B", "C"].map {
            PluginConfiguration(name: $0, enabled: false, executablePath: "/not-a-real-plugin/\($0).py")
        }
        try config.save(AppConfiguration(plugins: plugins))
        return (UsageBoardStore(configStore: config,
                                stateStore: PluginStateStore(directoryURL: root.appendingPathComponent("states"))), config)
    }

    func testMoveBothDirectionsPersistsWithoutChangingPluginValues() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-order-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (store, config) = try makeStore(root: root)
        let original = store.configuration.plugins
        store.movePlugins(fromOffsets: [0], toOffset: 4, visibleIDs: original.map(\.id))
        XCTAssertEqual(store.configuration.plugins.map(\.name), ["Hidden", "B", "C", "A"])
        await store.flushConfiguration()
        XCTAssertEqual(try config.load().plugins.map(\.stateID), store.configuration.plugins.map(\.stateID))
        store.movePlugins(fromOffsets: [3], toOffset: 0, visibleIDs: store.configuration.plugins.map(\.id))
        await store.flushConfiguration()
        XCTAssertEqual(store.configuration.plugins, original)
        XCTAssertEqual(try config.load().plugins.map(\.stateID), original.map(\.stateID))
    }

    func testFilteredMoveKeepsHiddenSlotsAndSupportsMultipleRows() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-order-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (store, config) = try makeStore(root: root)
        let visible = store.configuration.plugins.filter { $0.name != "Hidden" }.map(\.id)
        store.movePlugins(fromOffsets: [1, 2], toOffset: 0, visibleIDs: visible)
        XCTAssertEqual(store.configuration.plugins.map(\.name), ["B", "Hidden", "C", "A"])
        await store.flushConfiguration()
        XCTAssertEqual(try config.load().plugins.map(\.name), ["B", "Hidden", "C", "A"])
    }

    func testStaleOrInvalidMoveCannotCorruptOrder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-order-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (store, _) = try makeStore(root: root)
        let original = store.configuration.plugins
        let ids = original.map(\.id)
        store.movePlugins(fromOffsets: [0], toOffset: 1, visibleIDs: ids)
        store.movePlugins(fromOffsets: [4], toOffset: 0, visibleIDs: ids)
        store.movePlugins(fromOffsets: [0], toOffset: 5, visibleIDs: ids)
        store.movePlugins(fromOffsets: [0], toOffset: 2, visibleIDs: Array(ids.reversed()))
        store.movePlugins(fromOffsets: [0], toOffset: 1, visibleIDs: [UUID()])
        XCTAssertEqual(store.configuration.plugins, original)
        await store.flushConfiguration()
    }

    func testSettingsRegistersNativeListDragSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-order-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (store, _) = try makeStore(root: root)
        let host = NSHostingView(rootView: PluginSettingsView(store: store, draft: .constant(nil), unsavedChanges: UnsavedChangesBroker()))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 612, height: 460),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        try await Task.sleep(for: .milliseconds(200))
        let table = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTableView }.first)
        XCTAssertEqual(table.numberOfRows, 4)
        XCTAssertFalse(table.registeredDraggedTypes.isEmpty)
        await store.flushConfiguration()
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
