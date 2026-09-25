@preconcurrency import Foundation

private final class StateCache: @unchecked Sendable {
    private var store: [String: PluginCachedState] = [:]
    private let lock = NSLock()

    func get(_ key: String) -> PluginCachedState? {
        lock.lock()
        defer { lock.unlock() }
        return store[key]
    }

    func set(_ key: String, _ value: PluginCachedState) {
        lock.lock()
        defer { lock.unlock() }
        store[key] = value
    }

    func remove(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        store.removeValue(forKey: key)
    }
}

public struct PluginStateStore: Sendable {
    public var directoryURL: URL
    private let cache = StateCache()

    public init(directoryURL: URL = ConfigStore.statesDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    public func load(stateID: String) -> PluginCachedState? {
        if let cached = cache.get(stateID) { return cached }
        let fileURL = fileURL(for: stateID)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let state = try? UsageBoardJSON.decoder().decode(PluginCachedState.self, from: data) else { return nil }
        cache.set(stateID, state)
        return state
    }

    public func save(stateID: String, state: PluginCachedState) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = fileURL(for: stateID)
        let data = try UsageBoardJSON.encoder().encode(state)
        try data.write(to: fileURL, options: [.atomic])
        cache.set(stateID, state)
    }

    /// Removes the cached state (memory + disk). stateID 轮换或删除插件后调用，
    /// 防止 states/ 目录累积孤儿文件；清理失败静默——残留文件无害，不阻断配置变更。
    public func remove(stateID: String) {
        cache.remove(stateID)
        try? FileManager.default.removeItem(at: fileURL(for: stateID))
    }

    public func needsRefresh(stateID: String, intervalSeconds: Int) -> Bool {
        guard let cached = load(stateID: stateID) else { return true }
        let interval = max(intervalSeconds, 5)
        return Date().timeIntervalSince(cached.updatedAt) > Double(interval)
    }

    private func fileURL(for stateID: String) -> URL {
        directoryURL.appendingPathComponent("\(safeFileStem(for: stateID)).json")
    }

    private func safeFileStem(for stateID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let sanitizedScalars = stateID.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let sanitized = String(sanitizedScalars)
        return sanitized.isEmpty ? "_" : sanitized
    }
}
