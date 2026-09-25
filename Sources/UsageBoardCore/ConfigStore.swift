@preconcurrency import Foundation
import Darwin

public struct ConfigStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL = ConfigStore.defaultConfigURL()) {
        self.fileURL = fileURL
    }

    public static func defaultConfigURL() -> URL {
        defaultConfigurationDirectoryURL().appendingPathComponent("config.json")
    }

    public static func defaultConfigurationDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("UsageBoard", isDirectory: true)
    }

    /// 静态便捷方法基于默认配置目录，仅供无自定义 fileURL 的默认初始化使用
    /// （BundledPluginInstaller / PluginStateStore 的默认参数）；自定义路径时以实例推导为准。
    public static func statesDirectoryURL() -> URL {
        defaultConfigurationDirectoryURL().appendingPathComponent("states", isDirectory: true)
    }

    public static func pluginsDirectoryURL() -> URL {
        defaultConfigurationDirectoryURL().appendingPathComponent("plugins", isDirectory: true)
    }

    public func pluginsDirectoryURL() -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("plugins", isDirectory: true)
    }

    public func loadOrCreate() throws -> AppConfiguration {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return try load()
        }
        let configuration = AppConfiguration()
        try save(configuration)
        return configuration
    }

    public func load() throws -> AppConfiguration {
        let data = try Data(contentsOf: fileURL)
        return try UsageBoardJSON.decoder().decode(AppConfiguration.self, from: data)
    }

    public func save(_ configuration: AppConfiguration) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try UsageBoardJSON.encoder().encode(configuration)
        let temporaryURL = directory.appendingPathComponent(".config-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard FileManager.default.createFile(atPath: temporaryURL.path, contents: nil,
                                            attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: temporaryURL)
        guard rename(temporaryURL.path, fileURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
