@preconcurrency import Foundation
import XCTest
@testable import UsageBoardApp
import UsageBoardCore

@MainActor
final class UsageBoardAppSchedulerTests: XCTestCase {
    func testEmptyCachedSnapshotStaysHiddenDuringRefresh() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-empty-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let plugin = PluginConfiguration(name: "Empty", executablePath: "/bin/echo")
        let state = BlockingExecutorState()
        let store = UsageBoardStore(
            configStore: TestConfigStore(configuration: AppConfiguration(plugins: [plugin]), pluginsURL: root.appendingPathComponent("plugins")),
            stateStore: CachedEmptyStateStore(),
            executor: BlockingExecutor(state: state),
            updateChecker: NoopUpdateChecker()
        )
        defer {
            store.setPluginEnabled(id: plugin.id, enabled: false)
            state.releaseAll()
        }
        XCTAssertEqual(store.snapshot(for: plugin).state, .ready)
        XCTAssertFalse(store.snapshot(for: plugin).isVisibleOnDashboard)
        store.refresh(pluginID: plugin.id, force: true)
        try await state.waitForRunCount(1)
        XCTAssertEqual(store.snapshot(for: plugin).state, .loading)
        XCTAssertFalse(store.snapshot(for: plugin).isVisibleOnDashboard)
        state.releaseAll()
        for _ in 0..<100 where store.snapshot(for: plugin).state != .ready {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.snapshot(for: plugin).state, .ready)
        XCTAssertFalse(store.snapshot(for: plugin).isVisibleOnDashboard)
    }

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
        guard case .failed = store.snapshots[plugin.id]?.state else {
            return XCTFail("Missing parameters should show an actionable error, not a spinner")
        }
        store.setPluginEnabled(id: plugin.id, enabled: false)
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

    func testForcedRefreshCoalescesAndConfigurationChangeWaitsForPreviousRun() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-race-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("test.py")
        try "print('{}')".write(to: script, atomically: true, encoding: .utf8)
        let plugin = PluginConfiguration(name: "Test", enabled: false, executablePath: script.path,
                                         parameterValues: ["ACCOUNT": "old"])
        let state = BlockingExecutorState()
        defer { state.releaseAll() }
        let store = UsageBoardStore(
            configStore: TestConfigStore(configuration: AppConfiguration(plugins: [plugin]),
                                         pluginsURL: root.appendingPathComponent("plugins")),
            stateStore: EmptyStateStore(), executor: BlockingExecutor(state: state),
            updateChecker: NoopUpdateChecker())
        store.setPluginEnabled(id: plugin.id, enabled: true)
        try await state.waitForRunCount(1)
        store.refreshAll()
        store.refresh(pluginID: plugin.id, force: true)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(state.runCount, 1)
        var draft = store.configuration.plugins[0]
        draft.parameterValues["ACCOUNT"] = "new"
        XCTAssertTrue(store.updatePlugin(draft))
        XCTAssertNotEqual(store.configuration.plugins[0].stateID, plugin.stateID)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(state.runCount, 1, "The old process must finish before the new one starts")
        state.releaseAll()
        try await state.waitForRunCount(2)
        for _ in 0..<100 where store.snapshots[plugin.id]?.state != .ready {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.snapshots[plugin.id]?.badge, "new")
        draft.name = "Renamed"
        XCTAssertTrue(store.updatePlugin(draft))
        XCTAssertEqual(store.snapshots[plugin.id]?.displayName, "Renamed")
        XCTAssertEqual(state.runCount, 2, "Renaming should not rerun a plugin")
        store.setPluginEnabled(id: plugin.id, enabled: false)
        await store.flushConfiguration()
    }

    func testSavingEnabledPluginWithMissingRequiredValueIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-validation-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("test.py")
        try "print('{}')".write(to: script, atomically: true, encoding: .utf8)
        let plugin = PluginConfiguration(name: "Test", enabled: false, executablePath: script.path)
        let store = UsageBoardStore(configStore: TestConfigStore(configuration: AppConfiguration(plugins: [plugin]),
                                    pluginsURL: root.appendingPathComponent("plugins")),
                                    stateStore: EmptyStateStore(), executor: FailingExecutor(),
                                    updateChecker: NoopUpdateChecker())
        store.configuration.plugins[0].enabled = true
        var draft = store.configuration.plugins[0]
        draft.metadata = PluginMetadata(parameters: [.init(name: "KEY", required: true)])
        XCTAssertFalse(store.updatePlugin(draft))
        XCTAssertNotNil(store.lastError)
        XCTAssertNil(store.configuration.plugins[0].metadata)
        draft.executablePath = ""
        XCTAssertFalse(store.updatePlugin(draft))
    }

    func testChangingScriptPathLoadsNewMetadataBeforeValidation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-metadata-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldScript = root.appendingPathComponent("old.py")
        let newScript = root.appendingPathComponent("new.py")
        try "print('{}')".write(to: oldScript, atomically: true, encoding: .utf8)
        try """
        # UsageBoardPlugin:
        # {"name":"New", "parameters":[
        # {"name":"NEW_KEY", "required":true},
        # {"name":"PERIOD", "defaultValue":"7d"}]}
        # /UsageBoardPlugin
        """.write(to: newScript, atomically: true, encoding: .utf8)
        let plugin = PluginConfiguration(name: "Test", enabled: false, executablePath: oldScript.path)
        let store = UsageBoardStore(configStore: TestConfigStore(configuration: AppConfiguration(plugins: [plugin]),
                                    pluginsURL: root.appendingPathComponent("plugins")),
                                    stateStore: EmptyStateStore(), executor: FailingExecutor(),
                                    updateChecker: NoopUpdateChecker())
        store.configuration.plugins[0].enabled = true
        var draft = store.configuration.plugins[0]
        draft.executablePath = newScript.path
        XCTAssertFalse(store.updatePlugin(draft), "New script's required fields must be checked")
        XCTAssertEqual(store.configuration.plugins[0].executablePath, oldScript.path)
        store.configuration.plugins[0].enabled = false
        XCTAssertTrue(store.updatePlugin(draft))
        XCTAssertEqual(store.configuration.plugins[0].metadata?.name, "New")
        XCTAssertEqual(store.configuration.plugins[0].parameterValues["PERIOD"], "7d")
    }

    func testFlushWaitsForWritesScheduledWhileItIsWaiting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-flush-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = BlockingSaveRecorder()
        defer { recorder.releaseAll() }
        let store = UsageBoardStore(configStore: BlockingSaveConfigStore(recorder: recorder, root: root),
                                    stateStore: EmptyStateStore(), executor: FailingExecutor(),
                                    updateChecker: NoopUpdateChecker())
        recorder.enableBlocking()
        store.configuration.chartMode = .bar
        store.persistConfiguration()
        try await waitForSaveCount(1, recorder: recorder)
        var didFlush = false
        let flush = Task { await store.flushConfiguration(); didFlush = true }
        await Task.yield()
        store.configuration.chartMode = .line
        store.persistConfiguration()
        recorder.releaseOne()
        try await waitForSaveCount(2, recorder: recorder)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertFalse(didFlush, "Flush must include the second pending write")
        recorder.releaseOne()
        await flush.value
        XCTAssertEqual(recorder.savedChartMode, .line)
    }

    func testFlushConfigurationBlockingPersistsPendingWrite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-flush-blocking-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = BlockingSaveRecorder()
        let store = UsageBoardStore(configStore: BlockingSaveConfigStore(recorder: recorder, root: root),
                                    stateStore: EmptyStateStore(), executor: FailingExecutor(),
                                    updateChecker: NoopUpdateChecker())
        store.configuration.chartMode = .bar
        store.persistConfiguration()
        // Termination path: main thread blocks here, so the pending save must
        // complete on background threads.
        XCTAssertTrue(store.flushConfigurationBlocking(timeout: 5))
        XCTAssertEqual(recorder.savedChartMode, .bar)
    }

    func testBlockingFlushTimeoutKeepsPendingWriteForRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-flush-timeout-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = BlockingSaveRecorder()
        defer { recorder.releaseAll() }
        let store = UsageBoardStore(configStore: BlockingSaveConfigStore(recorder: recorder, root: root),
                                    stateStore: EmptyStateStore(), executor: FailingExecutor(),
                                    updateChecker: NoopUpdateChecker())
        recorder.enableBlocking()
        store.configuration.chartMode = .bar
        store.persistConfiguration()
        try await waitForSaveCount(1, recorder: recorder)

        XCTAssertFalse(store.flushConfigurationBlocking(timeout: 0.05),
                       "A pending write must prevent termination when the wait times out")
        XCTAssertEqual(recorder.savedChartMode, .line)

        recorder.releaseOne()
        XCTAssertTrue(store.flushConfigurationBlocking(timeout: 5))
        XCTAssertEqual(recorder.savedChartMode, .bar,
                       "Cancelling termination must leave the pending write able to finish")
    }

    private func waitForSaveCount(_ count: Int, recorder: BlockingSaveRecorder) async throws {
        for _ in 0..<100 where recorder.startedCount < count {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(recorder.startedCount, count)
    }

}

@MainActor
final class UpdateReminderTests: XCTestCase {
    private func makeStore(root: URL, checker: any UpdateChecking) -> UsageBoardStore {
        UsageBoardStore(
            configStore: TestConfigStore(configuration: AppConfiguration(), pluginsURL: root.appendingPathComponent("plugins")),
            stateStore: EmptyStateStore(),
            executor: FailingExecutor(),
            updateChecker: checker
        )
    }

    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-update-\(UUID().uuidString)", isDirectory: true)
    }

    private func waitForCheck(_ store: UsageBoardStore) async throws {
        for _ in 0..<100 where store.isCheckingForUpdates {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(store.isCheckingForUpdates)
    }

    func testPendingUpdateHidesAfterDismissAndReappearsForNewerVersion() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(root: root, checker: NoopUpdateChecker())

        store.availableUpdate = UpdateInfo(latestVersion: "9.9.9", downloadURL: "https://example.com/u.zip")
        XCTAssertNotNil(store.pendingUpdate)

        store.dismissUpdate(version: "9.9.9")
        XCTAssertNil(store.pendingUpdate)
        XCTAssertEqual(store.availableUpdate?.latestVersion, "9.9.9", "Later must retain the manual update entry")
        XCTAssertEqual(store.configuration.dismissedUpdateVersion, "9.9.9")

        store.availableUpdate = UpdateInfo(latestVersion: "9.9.10", downloadURL: "https://example.com/u.zip")
        XCTAssertNotNil(store.pendingUpdate, "A newer version must become visible again")
    }

    func testAutomaticPromptDeduplicatesByVersionAndHonorsLater() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(root: root, checker: NoopUpdateChecker())
        let first = UpdateInfo(latestVersion: "9.9.9", downloadURL: "https://example.com/u.zip")
        let second = UpdateInfo(latestVersion: "9.9.10", downloadURL: "https://example.com/u.zip")
        store.availableUpdate = first
        XCTAssertEqual(store.takePendingUpdatePrompt(), first)
        XCTAssertNil(store.takePendingUpdatePrompt())
        store.dismissUpdate(version: first.latestVersion)
        XCTAssertNil(store.takePendingUpdatePrompt())

        store.availableUpdate = second
        XCTAssertEqual(store.takePendingUpdatePrompt(), second, "A later release must prompt without restarting")
        XCTAssertNil(store.takePendingUpdatePrompt())
        store.availableUpdate = first
        XCTAssertNil(store.takePendingUpdatePrompt())
    }

    func testUpdateInProgressDoesNotConsumeAutomaticPrompt() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(root: root, checker: NoopUpdateChecker())
        let info = UpdateInfo(latestVersion: "9.9.9", downloadURL: "https://example.com/u.zip")
        store.availableUpdate = info
        store.isUpdating = true
        XCTAssertNil(store.takePendingUpdatePrompt())
        store.isUpdating = false
        XCTAssertEqual(store.takePendingUpdatePrompt(), info)
    }

    func testAutomaticCheckSuccessSetsUpdateWithoutTouchingMessage() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let info = UpdateInfo(latestVersion: "9.9.9", downloadURL: "https://example.com/u.zip")
        let store = makeStore(root: root, checker: StubUpdateChecker(info: info, hasUpdate: true))
        store.updateMessage = "preset"

        store.runUpdateCheck(url: URL(string: "https://example.com/version.json")!, automatic: true)
        try await waitForCheck(store)

        XCTAssertEqual(store.availableUpdate, info)
        XCTAssertNotNil(store.pendingUpdate)
        XCTAssertEqual(store.updateMessage, "preset", "Automatic checks must stay silent")
    }

    func testAutomaticCheckFailureKeepsExistingUpdateAndStaysSilent() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(root: root, checker: StubUpdateChecker(info: nil, hasUpdate: false))
        let info = UpdateInfo(latestVersion: "9.9.9", downloadURL: "https://example.com/u.zip")
        store.availableUpdate = info

        store.runUpdateCheck(url: URL(string: "https://example.com/version.json")!, automatic: true)
        try await waitForCheck(store)

        XCTAssertEqual(store.availableUpdate, info, "A transient failure must not hide the update badge")
        XCTAssertNil(store.updateMessage)
    }

    func testAutomaticCheckWithoutUpdateClearsAvailableUpdate() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let info = UpdateInfo(latestVersion: "9.9.9", downloadURL: "https://example.com/u.zip")
        let store = makeStore(root: root, checker: StubUpdateChecker(info: info, hasUpdate: false))
        store.availableUpdate = info

        store.runUpdateCheck(url: URL(string: "https://example.com/version.json")!, automatic: true)
        try await waitForCheck(store)

        XCTAssertNil(store.availableUpdate)
        XCTAssertNil(store.pendingUpdate)
        XCTAssertNil(store.updateMessage)
    }

    func testManualCheckFailureReportsMessage() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(root: root, checker: StubUpdateChecker(info: nil, hasUpdate: false))

        store.runUpdateCheck(url: URL(string: "https://example.com/version.json")!, automatic: false)
        try await waitForCheck(store)

        XCTAssertNil(store.availableUpdate)
        XCTAssertNotNil(store.updateMessage)
    }

    func testAutoUpdateCheckDefaultsToEnabledAndIsConfigurable() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(root: root, checker: NoopUpdateChecker())

        XCTAssertTrue(store.configuration.autoUpdateCheck)
        XCTAssertNil(store.updateMessage, "Startup automatic check must stay silent without a configured URL")

        store.setAutoUpdateCheck(false)
        XCTAssertFalse(store.configuration.autoUpdateCheck)
        store.setAutoUpdateCheck(true)
        XCTAssertTrue(store.configuration.autoUpdateCheck)
    }
}

private struct StubUpdateChecker: UpdateChecking {
    let info: UpdateInfo?
    let hasUpdate: Bool

    func check(currentVersion: String, url: URL) async throws -> UpdateCheckResult {
        guard let info else { throw URLError(.cannotConnectToHost) }
        return UpdateCheckResult(info: info, hasUpdate: hasUpdate)
    }
}

private final class BlockingSaveRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var blocking = false
    private var started = 0
    private var savedMode: ChartMode?
    var startedCount: Int { lock.withLock { started } }
    var savedChartMode: ChartMode? { lock.withLock { savedMode } }
    func enableBlocking() { lock.withLock { blocking = true } }
    func releaseOne() { semaphore.signal() }
    func releaseAll() { for _ in 0..<4 { semaphore.signal() } }
    func save(_ configuration: AppConfiguration) {
        let shouldWait = lock.withLock {
            if blocking { started += 1 }
            return blocking
        }
        if shouldWait { _ = semaphore.wait(timeout: .now() + 5) }
        lock.withLock { savedMode = configuration.chartMode }
    }
}

private struct BlockingSaveConfigStore: ConfigStoring {
    let recorder: BlockingSaveRecorder
    let root: URL
    func loadOrCreate() throws -> AppConfiguration { AppConfiguration() }
    func load() throws -> AppConfiguration { AppConfiguration() }
    func save(_ configuration: AppConfiguration) throws { recorder.save(configuration) }
    func pluginsDirectoryURL() -> URL { root.appendingPathComponent("plugins") }
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

private struct CachedEmptyStateStore: PluginStateStoring {
    func load(stateID: String) -> PluginCachedState? {
        PluginCachedState(updatedAt: Date(), items: [])
    }
    func save(stateID: String, state: PluginCachedState) throws {}
    func needsRefresh(stateID: String, intervalSeconds: Int) -> Bool { false }
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
            updatedAt: Date(),
            badge: configuration.parameterValues["ACCOUNT"]
        )
    }
}
