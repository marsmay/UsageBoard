import AppKit
import SwiftUI
import UsageBoardCore
import XCTest
@testable import UsageBoardApp

@MainActor
final class OptimizationRegressionTests: XCTestCase {
    func testChartRendersNonemptyFirstFrameAndUpdatesInBothModes() async throws {
        for mode in [ChartMode.line, .bar] {
            let chart = PluginChart(period: "7d", bucketUnit: "day", buckets: [
                PluginChartBucket(id: "today", label: "Today", segments: [.init(model: "test", tokens: 42)])
            ])
            let host = NSHostingView(rootView: TokenUsageChartView(chart: chart, language: .zhHans, chartMode: mode).frame(width: 380, height: 300))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            var changed = chart
            changed.buckets = []
            host.rootView = TokenUsageChartView(chart: changed, language: .zhHans, chartMode: mode).frame(width: 380, height: 300)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            host.rootView = TokenUsageChartView(chart: chart, language: .zhHans, chartMode: mode).frame(width: 380, height: 300)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertGreaterThan(host.fittingSize.height, 0)
        }
    }

    func testPlotIsolationStillRepaintsHoverAndChangedData() async throws {
        for mode in [ChartMode.line, .bar] {
            let buckets = (0..<3).map { PluginChartBucket(id: String($0), label: String($0), segments: []) }
            func plot(tokens: Double, hover: Int?) -> AnyView {
                let series = [TokenChartSeries(name: "test", color: .blue, values: [tokens, 20, 30])]
                switch mode {
                case .line:
                    return AnyView(TokenLineChartPlot(buckets: buckets, series: series, maxValue: 100,
                                                      hoverIndex: hover, onHover: { _ in }).frame(width: 380, height: 170))
                case .bar:
                    return AnyView(TokenBarChartPlot(buckets: buckets, series: series, maxValue: 100,
                                                     hoverIndex: hover, onHover: { _ in }).frame(width: 380, height: 170))
                }
            }
            let host = NSHostingView(rootView: plot(tokens: 10, hover: nil))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 170), styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            defer { window.contentView = nil }
            func pixels() async throws -> Data {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            }
            let initial = try await pixels()
            host.rootView = plot(tokens: 10, hover: 0)
            let hovered = try await pixels()
            XCTAssertNotEqual(initial, hovered, "Hover overlay and bar dimming must still update")
            host.rootView = plot(tokens: 80, hover: 0)
            let changed = try await pixels()
            XCTAssertNotEqual(hovered, changed, "Equatable drawing must invalidate when data changes")
        }
    }

    func testDraftProtectionSurvivesLeavingPluginPageAndHandlesChoices() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-draft-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = ConfigStore(fileURL: root.appendingPathComponent("config.json"))
        try config.save(AppConfiguration())
        let script = root.appendingPathComponent("test.py")
        try "print('{}')".write(to: script, atomically: true, encoding: .utf8)
        let store = UsageBoardStore(configStore: config, stateStore: PluginStateStore(directoryURL: root.appendingPathComponent("states")))
        store.configuration.plugins = [.init(name: "Original", enabled: false, executablePath: script.path)]
        var draft = store.configuration.plugins.first
        let binding = Binding(get: { draft }, set: { draft = $0 })
        let broker = UnsavedChangesBroker()
        // Like SettingsView, the parent owns the handler and draft across tab changes.
        broker.handler = { broker.resolve(binding, store: store, choose: { .cancel }) }
        defer { broker.handler = nil }
        let host = NSHostingView(rootView: AnyView(PluginSettingsView(store: store, draft: binding, unsavedChanges: broker)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 520), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        draft?.name = "Edited"
        host.rootView = AnyView(Text("Other settings tab"))
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNotNil(broker.handler)
        XCTAssertEqual(broker.handler?(), false)
        XCTAssertEqual(draft?.name, "Edited")
        XCTAssertTrue(broker.resolve(binding, store: store, choose: { .discard }))
        XCTAssertEqual(draft?.name, "Original")
        draft?.executablePath = root.appendingPathComponent("missing.py").path
        XCTAssertFalse(broker.resolve(binding, store: store, choose: { .save }))
        draft?.executablePath = script.path
        draft?.name = "Saved"
        XCTAssertTrue(broker.resolve(binding, store: store, choose: { .save }))
        XCTAssertEqual(store.configuration.plugins.first?.name, "Saved")
        XCTAssertFalse(UnsavedChangesBroker.hasChanges(draft, store: store))
        await store.flushConfiguration()
    }

    func testCacheCleanupWaitsForInflightSaveOnRemovalAndRotation() async throws {
        for rotate in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-cache-race-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let config = ConfigStore(fileURL: root.appendingPathComponent("config.json"))
            try config.save(AppConfiguration())
            let script = root.appendingPathComponent("test.py")
            try "print('{}')".write(to: script, atomically: true, encoding: .utf8)
            let states = GatedCache(directory: root.appendingPathComponent("states"))
            let store = UsageBoardStore(configStore: config, stateStore: states, executor: ImmediateReadyExecutor())
            let plugin = PluginConfiguration(name: "Test", executablePath: script.path)
            store.configuration.plugins = [plugin]
            store.refresh(pluginID: plugin.id, force: true)
            let entered = await Task.detached { states.waitForSave() }.value
            XCTAssertTrue(entered)
            defer { states.release.signal() }
            if rotate {
                // Keep the test focused on the old in-flight write, without starting a new refresh.
                store.configuration.plugins[0].enabled = false
                var draft = store.configuration.plugins[0]
                draft.parameterValues["test"] = "changed"
                XCTAssertTrue(store.updatePlugin(draft))
            } else {
                store.removePlugin(id: plugin.id)
            }
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertFalse(states.didRemove, "Cleanup must not overtake the already-started save")
            states.release.signal()
            let removed = await Task.detached { states.waitForRemoval() }.value
            XCTAssertTrue(removed)
            XCTAssertNil(states.real.load(stateID: plugin.stateID))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("states/\(plugin.stateID).json").path))
            await store.flushConfiguration()
        }
    }
}

private final class GatedCache: PluginStateStoring, @unchecked Sendable {
    let real: PluginStateStore
    let release = DispatchSemaphore(value: 0)
    private let entered = DispatchSemaphore(value: 0)
    private let removed = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var removalCompleted = false
    init(directory: URL) { real = PluginStateStore(directoryURL: directory) }
    var didRemove: Bool { lock.lock(); defer { lock.unlock() }; return removalCompleted }
    func waitForSave() -> Bool { entered.wait(timeout: .now() + 5) == .success }
    func waitForRemoval() -> Bool { removed.wait(timeout: .now() + 5) == .success }
    func load(stateID: String) -> PluginCachedState? { real.load(stateID: stateID) }
    func needsRefresh(stateID: String, intervalSeconds: Int) -> Bool { true }
    func save(stateID: String, state: PluginCachedState) throws {
        entered.signal()
        _ = release.wait(timeout: .now() + 5)
        try real.save(stateID: stateID, state: state)
    }
    func remove(stateID: String) {
        real.remove(stateID: stateID)
        lock.lock(); removalCompleted = true; lock.unlock()
        removed.signal()
    }
}
private struct ImmediateReadyExecutor: PluginExecuting {
    func run(configuration: PluginConfiguration, displayName: String, language: AppLanguage) -> PluginSnapshot {
        PluginSnapshot(id: configuration.id, displayName: displayName, state: .ready, items: [], updatedAt: Date())
    }
}
