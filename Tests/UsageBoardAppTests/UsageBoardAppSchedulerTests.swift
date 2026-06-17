@preconcurrency import Foundation
import XCTest
@testable import UsageBoardApp
import UsageBoardCore

@MainActor
final class UsageBoardAppSchedulerTests: XCTestCase {
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
