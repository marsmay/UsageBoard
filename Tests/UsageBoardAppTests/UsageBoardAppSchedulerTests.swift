@preconcurrency import Foundation
import XCTest
@testable import UsageBoardApp
import UsageBoardCore

@MainActor
final class UsageBoardAppSchedulerTests: XCTestCase {
    func testStoreDoesNotOverwriteConfigurationAfterLoadFailure() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("usageboard-app-tests-\(UUID().uuidString)", isDirectory: true)
        let plugins = root.appendingPathComponent("plugins", isDirectory: true)
        let recorder = SaveCallRecorder()
        let store = UsageBoardStore(
            configStore: FailingLoadConfigStore(recorder: recorder, pluginsURL: plugins),
            stateStore: EmptyStateStore(),
            executor: FailingExecutor(),
            updateChecker: NoopUpdateChecker()
        )

        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(recorder.saveCount, 0)
    }

    func testSchedulerBacksOffWhenEnabledPluginIsNotReady() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("usageboard-app-tests-\(UUID().uuidString)", isDirectory: true)
        let plugins = root.appendingPathComponent("plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pluginURL = root.appendingPathComponent("missing-param.py")
        try """
        # UsageBoardPlugin:
        # {
        #   "name": "Needs Key",
        #   "parameters": [
        #     {"name": "API_KEY", "label": "API Key", "type": "secret", "required": true}
        #   ]
        # }
        # /UsageBoardPlugin
        print("{}")
        """.write(to: pluginURL, atomically: true, encoding: .utf8)

        let plugin = PluginConfiguration(
            name: "Needs Key",
            enabled: true,
            executablePath: pluginURL.path,
            refreshIntervalSeconds: 5
        )
        let store = UsageBoardStore(
            configStore: TestConfigStore(configuration: AppConfiguration(plugins: [plugin]), pluginsURL: plugins),
            stateStore: EmptyStateStore(),
            executor: FailingExecutor(),
            updateChecker: NoopUpdateChecker()
        )

        try await Task.sleep(for: .milliseconds(100))

        let nextRefresh = try XCTUnwrap(store.nextRefreshAt[plugin.id])
        XCTAssertGreaterThan(nextRefresh.timeIntervalSince(Date()), 4.0)
    }

    func testNonForcedRefreshDoesNotStartDuplicateWhileRefreshIsInflight() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("usageboard-app-tests-\(UUID().uuidString)", isDirectory: true)
        let plugins = root.appendingPathComponent("plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pluginURL = root.appendingPathComponent("slow-plugin.py")
        try "print('{}')".write(to: pluginURL, atomically: true, encoding: .utf8)
        let plugin = PluginConfiguration(
            name: "Slow",
            enabled: false,
            executablePath: pluginURL.path,
            refreshIntervalSeconds: 5
        )
        let executorState = BlockingExecutorState()
        let store = UsageBoardStore(
            configStore: TestConfigStore(configuration: AppConfiguration(plugins: [plugin]), pluginsURL: plugins),
            stateStore: EmptyStateStore(),
            executor: BlockingExecutor(state: executorState),
            updateChecker: NoopUpdateChecker()
        )
        defer { executorState.releaseAll() }

        store.setPluginEnabled(id: plugin.id, enabled: true)
        try await executorState.waitForRunCount(1)

        store.refresh(pluginID: plugin.id)
        store.refresh(pluginID: plugin.id)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(executorState.runCount, 1)
    }
}

private struct TestConfigStore: ConfigStoring {
    var configuration: AppConfiguration
    var pluginsURL: URL

    func loadOrCreate() throws -> AppConfiguration {
        configuration
    }

    func load() throws -> AppConfiguration {
        configuration
    }

    func save(_ configuration: AppConfiguration) throws {}

    func pluginsDirectoryURL() -> URL {
        pluginsURL
    }
}

private final class SaveCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _saveCount = 0

    var saveCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _saveCount
    }

    func recordSave() {
        lock.lock()
        _saveCount += 1
        lock.unlock()
    }
}

private struct FailingLoadConfigStore: ConfigStoring {
    let recorder: SaveCallRecorder
    var pluginsURL: URL

    func loadOrCreate() throws -> AppConfiguration {
        throw CocoaError(.fileReadCorruptFile)
    }

    func load() throws -> AppConfiguration {
        throw CocoaError(.fileReadCorruptFile)
    }

    func save(_ configuration: AppConfiguration) throws {
        recorder.recordSave()
    }

    func pluginsDirectoryURL() -> URL {
        pluginsURL
    }
}

private struct EmptyStateStore: PluginStateStoring {
    func load(stateID: String) -> PluginCachedState? {
        nil
    }

    func save(stateID: String, state: PluginCachedState) throws {}

    func needsRefresh(stateID: String, intervalSeconds: Int) -> Bool {
        true
    }
}

private struct FailingExecutor: PluginExecuting {
    func run(configuration: PluginConfiguration, displayName: String, language: AppLanguage) -> PluginSnapshot {
        XCTFail("Plugin should not run while required parameters are missing")
        return PluginSnapshot(id: configuration.id, displayName: displayName)
    }
}

private struct NoopUpdateChecker: UpdateChecking {
    func check(currentVersion: String, url: URL) async throws -> UpdateCheckResult {
        throw URLError(.badURL)
    }
}

private final class BlockingExecutorState: @unchecked Sendable {
    private let lock = NSLock()
    private var _runCount = 0
    private let releaseSemaphore = DispatchSemaphore(value: 0)

    var runCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _runCount
    }

    func markRunStarted() {
        lock.lock()
        _runCount += 1
        lock.unlock()
    }

    func waitUntilReleased() {
        _ = releaseSemaphore.wait(timeout: .now() + 5)
    }

    func releaseAll() {
        for _ in 0..<8 {
            releaseSemaphore.signal()
        }
    }

    func waitForRunCount(_ expected: Int) async throws {
        let deadline = Date().addingTimeInterval(2)
        while runCount < expected && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThanOrEqual(runCount, expected)
    }
}

private struct BlockingExecutor: PluginExecuting {
    let state: BlockingExecutorState

    func run(configuration: PluginConfiguration, displayName: String, language: AppLanguage) -> PluginSnapshot {
        state.markRunStarted()
        state.waitUntilReleased()
        return PluginSnapshot(
            id: configuration.id,
            displayName: displayName,
            state: .ready,
            items: [],
            updatedAt: Date()
        )
    }
}
