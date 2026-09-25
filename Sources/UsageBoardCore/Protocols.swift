@preconcurrency import Foundation

// MARK: - ConfigStoring

public protocol ConfigStoring: Sendable {
    func loadOrCreate() throws -> AppConfiguration
    func load() throws -> AppConfiguration
    func save(_ configuration: AppConfiguration) throws
    func pluginsDirectoryURL() -> URL
}

extension ConfigStore: ConfigStoring {}

// MARK: - PluginStateStoring

public protocol PluginStateStoring: Sendable {
    func load(stateID: String) -> PluginCachedState?
    func save(stateID: String, state: PluginCachedState) throws
    func remove(stateID: String)
    func needsRefresh(stateID: String, intervalSeconds: Int) -> Bool
}

extension PluginStateStore: PluginStateStoring {}

// MARK: - PluginExecuting

public protocol PluginExecuting: Sendable {
    func run(configuration: PluginConfiguration, displayName: String, language: AppLanguage) -> PluginSnapshot
}

extension PluginExecutor: PluginExecuting {}

// MARK: - UpdateChecking

public protocol UpdateChecking: Sendable {
    func check(currentVersion: String, currentBuild: Int?, url: URL) async throws -> UpdateCheckResult
}

extension UpdateChecker: UpdateChecking {}
