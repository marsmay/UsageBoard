import AppKit
import Foundation
import ServiceManagement
import UsageBoardCore

@MainActor
final class UsageBoardStore: ObservableObject {
    @Published var configuration: AppConfiguration
    @Published private(set) var snapshots: [UUID: PluginSnapshot] = [:]
    @Published var lastError: String?
    @Published var updateMessage: String?
    @Published var availableUpdate: UpdateInfo?
    @Published var isUpdating: Bool = false
    @Published var selectedTabID: UUID?
    @Published private(set) var nextRefreshAt: [UUID: Date] = [:]

    let activeLanguage: AppLanguage

    private let configStore: any ConfigStoring
    private let stateStore: any PluginStateStoring
    private let executor: any PluginExecuting
    private let updateChecker: any UpdateChecking
    private var refreshTasks: [UUID: Task<Void, Never>] = [:]
    private var inflightRefreshTasks: [UUID: Task<Void, Never>] = [:]
    private var schedulerKeys: [UUID: SchedulerKey] = [:]
    private var isSystemActive: Bool = true
    private var systemActivityObservers: [NSObjectProtocol] = []
    private var systemInactiveTimeout: Task<Void, Never>?
    private var configSaveTask: Task<Void, Never>?
    private var configSaveGeneration: Int = 0

    private struct SchedulerKey: Equatable {
        let refreshIntervalSeconds: Int
        let stateID: String
    }

    init(
        configStore: any ConfigStoring = ConfigStore(),
        stateStore: any PluginStateStoring = PluginStateStore(),
        executor: any PluginExecuting = PluginExecutor(),
        updateChecker: any UpdateChecking = UpdateChecker()
    ) {
        self.configStore = configStore
        self.stateStore = stateStore
        self.executor = executor
        self.updateChecker = updateChecker
        let loadedConfiguration: AppConfiguration
        var didLoadConfiguration = false
        do {
            loadedConfiguration = try configStore.loadOrCreate()
            didLoadConfiguration = true
        } catch {
            loadedConfiguration = AppConfiguration()
            lastError = "配置加载失败：\(error.localizedDescription)"
        }
        configuration = loadedConfiguration
        activeLanguage = loadedConfiguration.language
        AppLocalization.shared = AppLocalization(language: activeLanguage)
        if didLoadConfiguration {
            try? configStore.save(configuration) // persist generated stateIDs
        }
        do {
            try installBundledPlugins()
        } catch {
            lastError = activeLanguage == .en
                ? "Failed to install bundled plugins: \(error.localizedDescription)"
                : "内置插件安装失败：\(error.localizedDescription)"
        }
        reloadAllMetadata()
        if didLoadConfiguration {
            try? configStore.save(configuration)
        }
        rebuildSnapshots()
        loadCachedStates()
        startSchedulers()
        observeSystemActivity()
    }

    deinit {
        refreshTasks.values.forEach { $0.cancel() }
        inflightRefreshTasks.values.forEach { $0.cancel() }
        systemInactiveTimeout?.cancel()
        configSaveTask?.cancel()
        // NotificationCenter observers are intentionally not removed here:
        // they live in a MainActor-isolated non-Sendable array, and the
        // store is a long-lived singleton — observers are reclaimed at process exit.
    }

    private(set) var displayNames: [UUID: String] = [:]

    private func invalidateDisplayNames() {
        displayNames = PluginDisplayNames.make(for: configuration.plugins, language: activeLanguage)
    }

    var pluginsDirectoryURL: URL {
        configStore.pluginsDirectoryURL()
    }

    func snapshot(for plugin: PluginConfiguration) -> PluginSnapshot {
        if let snapshot = snapshots[plugin.id] {
            return snapshot
        }
        return makeSnapshot(for: plugin)
    }

    /// Full save: rebuild snapshots, restart schedulers, refresh due plugins, write to disk.
    func saveConfiguration() {
        lastError = nil
        rebuildSnapshots()
        startSchedulers()
        refreshPluginsAfterConfigurationChange()
        persistConfiguration()
    }

    /// Lightweight: only schedule a disk write (no snapshot/scheduler/refresh side effects).
    func persistConfiguration() {
        scheduleConfigurationWrite()
    }

    private func scheduleConfigurationWrite() {
        configSaveGeneration &+= 1
        let myGeneration = configSaveGeneration
        let snapshot = configuration
        let store = configStore
        let previous = configSaveTask
        configSaveTask = Task { [weak self] in
            _ = await previous?.value
            if Task.isCancelled { return }
            guard let self else { return }
            // Coalesce: skip if a newer save has been scheduled since
            if self.configSaveGeneration != myGeneration { return }
            do {
                try await Task.detached(priority: .utility) {
                    try store.save(snapshot)
                }.value
            } catch is CancellationError {
                return
            } catch {
                self.lastError = self.storeMessage(.configurationSaveFailed(error.localizedDescription))
            }
        }
    }

    func addPlugin(fileURL: URL) {
        let metadata = PluginMetadataParser.parse(fileURL: fileURL)
        let name = metadata?.name ?? fileURL.deletingPathExtension().lastPathComponent
        var values: [String: String] = [:]
        for parameter in metadata?.parameters ?? [] {
            if let defaultValue = parameter.defaultValue {
                values[parameter.name] = defaultValue
            }
        }

        let plugin = PluginConfiguration(
            name: name,
            enabled: false,
            executablePath: fileURL.path,
            refreshIntervalSeconds: 300,
            metadata: metadata,
            parameterValues: values
        )
        configuration.plugins.append(plugin)
        snapshots[plugin.id] = makeSnapshot(for: plugin)
        saveConfiguration()
    }

    func ensurePluginsDirectory() {
        do {
            try FileManager.default.createDirectory(at: pluginsDirectoryURL, withIntermediateDirectories: true)
        } catch {
            lastError = storeMessage(.pluginsDirectoryCreateFailed(error.localizedDescription))
        }
    }

    func setPluginEnabled(id: UUID, enabled: Bool) {
        guard let index = configuration.plugins.firstIndex(where: { $0.id == id }) else { return }
        let plugin = configuration.plugins[index]

        guard enabled else {
            configuration.plugins[index].enabled = false
            inflightRefreshTasks[id]?.cancel()
            inflightRefreshTasks.removeValue(forKey: id)
            nextRefreshAt.removeValue(forKey: id)
            rebuildSnapshots()
            startSchedulers()
            persistConfiguration()
            return
        }

        let missing = missingRequiredParameters(for: plugin)
        guard missing.isEmpty else {
            configuration.plugins[index].enabled = false
            lastError = storeMessage(.missingRequiredParameters(missing))
            return
        }

        configuration.plugins[index].enabled = true
        lastError = nil
        rebuildSnapshots()
        let enabledPlugin = configuration.plugins[index]
        snapshots[id] = makeSnapshot(
            for: enabledPlugin,
            state: .loading,
            items: snapshots[plugin.id]?.items ?? [],
            updatedAt: snapshots[plugin.id]?.updatedAt,
            chart: snapshots[plugin.id]?.chart
        )
        refresh(pluginID: id, force: true)
        startSchedulers()
        persistConfiguration()
    }

    func reloadMetadata(pluginID: UUID) {
        guard let index = configuration.plugins.firstIndex(where: { $0.id == pluginID }) else { return }
        let fileURL = URL(fileURLWithPath: configuration.plugins[index].executablePath)
        let metadata = PluginMetadataParser.parse(fileURL: fileURL)
        configuration.plugins[index].metadata = metadata

        for parameter in metadata?.parameters ?? [] where configuration.plugins[index].parameterValues[parameter.name] == nil {
            configuration.plugins[index].parameterValues[parameter.name] = parameter.defaultValue ?? ""
        }
    }

    private func reloadAllMetadata() {
        for plugin in configuration.plugins {
            reloadMetadata(pluginID: plugin.id)
        }
    }

    func removePlugin(id: UUID) {
        guard let index = configuration.plugins.firstIndex(where: { $0.id == id }) else { return }
        configuration.plugins.remove(at: index)
        snapshots.removeValue(forKey: id)
        refreshTasks[id]?.cancel()
        refreshTasks.removeValue(forKey: id)
        inflightRefreshTasks[id]?.cancel()
        inflightRefreshTasks.removeValue(forKey: id)
        schedulerKeys.removeValue(forKey: id)
        nextRefreshAt.removeValue(forKey: id)
        invalidateDisplayNames()
        persistConfiguration()
    }

    func refreshAll() {
        // User-initiated refresh implies the app is active — clear any stale gate.
        if !isSystemActive { setSystemActive(true) }
        for plugin in configuration.plugins where plugin.enabled {
            refresh(pluginID: plugin.id, force: true)
        }
    }

    func refresh(pluginID: UUID, force: Bool = false) {
        guard let plugin = configuration.plugins.first(where: { $0.id == pluginID }) else { return }
        guard plugin.enabled else { return }
        guard isPluginReadyToRun(plugin) else {
            snapshots[plugin.id] = makeSnapshot(
                for: plugin,
                state: .loading,
                items: snapshots[plugin.id]?.items ?? [],
                updatedAt: snapshots[plugin.id]?.updatedAt,
                chart: snapshots[plugin.id]?.chart
            )
            return
        }
        let refreshInterval = max(plugin.refreshIntervalSeconds, 5)
        if !force {
            if inflightRefreshTasks[plugin.id] != nil {
                return
            }
            if let updatedAt = snapshots[plugin.id]?.updatedAt,
               Date().timeIntervalSince(updatedAt) <= Double(refreshInterval) {
                return
            }
        }

        snapshots[plugin.id] = makeSnapshot(
            for: plugin,
            state: .loading,
            items: snapshots[plugin.id]?.items ?? [],
            updatedAt: snapshots[plugin.id]?.updatedAt,
            badge: snapshots[plugin.id]?.badge,
            chart: snapshots[plugin.id]?.chart
        )

        let executor = executor
        let stateStore = stateStore
        let displayName = displayNames[plugin.id] ?? PluginDisplayNames.displayName(for: plugin, language: activeLanguage)
        let language = activeLanguage
        let pluginID = plugin.id
        nextRefreshAt[pluginID] = Date().addingTimeInterval(TimeInterval(refreshInterval))
        inflightRefreshTasks[pluginID]?.cancel()
        inflightRefreshTasks[pluginID] = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                executor.run(configuration: plugin, displayName: displayName, language: language)
            }.value
            guard let self else { return }
            if Task.isCancelled { return }
            // Drop snapshot if the plugin was removed or disabled while in flight.
            guard let current = self.configuration.plugins.first(where: { $0.id == pluginID }),
                  current.enabled else {
                self.inflightRefreshTasks.removeValue(forKey: pluginID)
                return
            }
            self.snapshots[pluginID] = snapshot
            self.inflightRefreshTasks.removeValue(forKey: pluginID)
            if snapshot.state == .ready, let updatedAt = snapshot.updatedAt {
                let cached = PluginCachedState(
                    updatedAt: updatedAt,
                    items: snapshot.items,
                    badge: snapshot.badge,
                    chart: snapshot.chart
                )
                let stateID = current.stateID
                Task.detached(priority: .utility) {
                    do {
                        try stateStore.save(stateID: stateID, state: cached)
                    } catch {
                        await MainActor.run {
                            self.lastError = self.storeMessage(.cacheSaveFailed(error.localizedDescription))
                        }
                    }
                }
            }
        }
    }

    private static let updateCheckURL: URL? = {
        guard let string = Bundle.main.infoDictionary?["UBUpdateCheckURL"] as? String,
              !string.isEmpty else { return nil }
        return URL(string: string)
    }()

    func checkForUpdates(userInitiated: Bool = false) {
        guard let url = Self.updateCheckURL else {
            updateMessage = storeMessage(.updateCheckURLMissing)
            return
        }
        availableUpdate = nil
        Task {
            do {
                let result = try await updateChecker.check(currentVersion: currentVersion, url: url)
                if result.hasUpdate {
                    availableUpdate = result.info
                    updateMessage = nil
                } else {
                    availableUpdate = nil
                    updateMessage = storeMessage(.alreadyLatestVersion)
                }
            } catch {
                updateMessage = storeMessage(.updateCheckFailed(error.localizedDescription))
            }
        }
    }

    func performUpdate() {
        guard let info = availableUpdate, let url = URL(string: info.downloadURL) else { return }
        isUpdating = true
        updateMessage = storeMessage(.downloadingUpdate)

        Task {
            do {
                let downloader = UpdateDownloader()
                let update = try await downloader.download(from: url)
                updateMessage = storeMessage(.installingUpdate)
                try AppRelauncher.relaunch(
                    replacingWith: update.appURL,
                    cleanupDirectoryURL: update.cleanupDirectoryURL
                )
                NSApp.terminate(nil)
            } catch {
                isUpdating = false
                updateMessage = storeMessage(.updateFailed(error.localizedDescription))
            }
        }
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private func installBundledPlugins() throws {
        guard let sourceURL = bundledPluginsDirectoryURL() else { return }
        _ = try BundledPluginInstaller(
            sourceDirectoryURL: sourceURL,
            destinationDirectoryURL: configStore.pluginsDirectoryURL()
        )
        .installIfNeeded()
    }

    private func bundledPluginsDirectoryURL() -> URL? {
        if let appResourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("Plugins", isDirectory: true),
            FileManager.default.fileExists(atPath: appResourceURL.path) {
            return appResourceURL
        }

        let developmentURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/BundledPlugins", isDirectory: true)
        if FileManager.default.fileExists(atPath: developmentURL.path) {
            return developmentURL
        }

        return nil
    }

    func rebuildSnapshots() {
        invalidateDisplayNames()
        var next: [UUID: PluginSnapshot] = [:]
        for plugin in configuration.plugins {
            next[plugin.id] = snapshots[plugin.id] ?? makeSnapshot(for: plugin)
        }
        snapshots = next
    }

    private func loadCachedStates() {
        for plugin in configuration.plugins {
            guard let cached = stateStore.load(stateID: plugin.stateID) else { continue }
            snapshots[plugin.id] = makeSnapshot(
                for: plugin,
                state: .ready,
                items: cached.items,
                updatedAt: cached.updatedAt,
                badge: cached.badge,
                chart: cached.chart
            )
        }
    }

    private func startSchedulers() {
        let enabledPlugins = configuration.plugins.filter { $0.enabled }
        let currentIDs = Set(enabledPlugins.map(\.id))

        // Cancel schedulers for plugins that no longer exist or were disabled.
        for id in refreshTasks.keys where !currentIDs.contains(id) {
            refreshTasks[id]?.cancel()
            refreshTasks.removeValue(forKey: id)
            schedulerKeys.removeValue(forKey: id)
            nextRefreshAt.removeValue(forKey: id)
        }

        for plugin in enabledPlugins {
            let id = plugin.id
            let interval = max(plugin.refreshIntervalSeconds, 5)
            let newKey = SchedulerKey(refreshIntervalSeconds: interval, stateID: plugin.stateID)
            let cachedUpdatedAt = snapshots[id]?.updatedAt

            // Keep an already-running scheduler if its key is unchanged.
            if refreshTasks[id] != nil, schedulerKeys[id] == newKey {
                if nextRefreshAt[id] == nil {
                    nextRefreshAt[id] = scheduledRefreshDate(updatedAt: cachedUpdatedAt, interval: interval)
                }
                continue
            }

            // Replace stale scheduler (interval or stateID changed) or start new one.
            refreshTasks[id]?.cancel()
            schedulerKeys[id] = newKey
            let initialRefreshAt = scheduledRefreshDate(updatedAt: cachedUpdatedAt, interval: interval)
            nextRefreshAt[id] = initialRefreshAt

            let hasCached = cachedUpdatedAt != nil
            if !hasCached {
                snapshots[id] = makeSnapshot(for: plugin, state: .loading)
            }

            refreshTasks[id] = Task { [weak self] in
                let initialDelay = max(0, initialRefreshAt.timeIntervalSince(Date()))
                if initialDelay > 0 {
                    try? await Task.sleep(for: .seconds(initialDelay))
                }
                while !Task.isCancelled {
                    guard let self else { return }
                    guard let current = self.configuration.plugins.first(where: { $0.id == id }),
                          current.enabled else { return }
                    if self.isSystemActive, self.isPluginReadyToRun(current) {
                        self.refresh(pluginID: id)
                    }
                    let delay = self.nextSchedulerDelay(pluginID: id, interval: interval)
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
    }

    private func nextSchedulerDelay(pluginID: UUID, interval: Int, now: Date = Date()) -> TimeInterval {
        let interval = TimeInterval(max(interval, 5))
        guard let target = nextRefreshAt[pluginID] else {
            nextRefreshAt[pluginID] = now.addingTimeInterval(interval)
            return interval
        }

        let delay = target.timeIntervalSince(now)
        guard delay > 0 else {
            nextRefreshAt[pluginID] = now.addingTimeInterval(interval)
            return interval
        }
        return delay
    }

    private func scheduledRefreshDate(updatedAt: Date?, interval: Int, now: Date = Date()) -> Date {
        guard let updatedAt else { return now }
        let due = updatedAt.addingTimeInterval(TimeInterval(interval))
        return due > now ? due : now
    }

    private func refreshPluginsAfterConfigurationChange() {
        for plugin in configuration.plugins where plugin.enabled && isPluginReadyToRun(plugin) {
            let snapshot = snapshots[plugin.id]
            let hasCached = snapshot?.updatedAt != nil
            let shouldRefresh = !hasCached || snapshot?.state == .loading || isFailed(snapshot?.state)
            if shouldRefresh {
                refresh(pluginID: plugin.id, force: true)
            }
        }
    }

    private func observeSystemActivity() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        // Only gate on actual system sleep. Screen lock / session resign are
        // intentionally ignored: usage tracking should continue while the user
        // steps away, and the DistributedNotificationCenter lock/unlock events
        // are unreliable — if only the lock event arrived, the previous code
        // would freeze refresh indefinitely.
        let sleepToken = workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSystemActive(false) }
        }
        let wakeToken = workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSystemActive(true) }
        }
        systemActivityObservers.append(sleepToken)
        systemActivityObservers.append(wakeToken)
    }

    private func setSystemActive(_ active: Bool) {
        guard active != isSystemActive else { return }
        isSystemActive = active
        systemInactiveTimeout?.cancel()
        systemInactiveTimeout = nil
        if active {
            refreshPluginsIfDue()
        } else {
            // Safety net: if a wake notification is dropped or never arrives,
            // recover after 4 hours so the app doesn't stay frozen.
            systemInactiveTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4 * 3600))
                guard let self, !Task.isCancelled else { return }
                if !self.isSystemActive {
                    self.setSystemActive(true)
                }
            }
        }
    }

    private func refreshPluginsIfDue() {
        for plugin in configuration.plugins where plugin.enabled && isPluginReadyToRun(plugin) {
            refresh(pluginID: plugin.id)
        }
    }

    private func isFailed(_ state: PluginSnapshotState?) -> Bool {
        guard let state else { return false }
        if case .failed = state {
            return true
        }
        return false
    }

    func missingRequiredParameters(for plugin: PluginConfiguration) -> [String] {
        var missing: [String] = []
        for parameter in plugin.metadata?.parameters ?? [] where parameter.required {
            let value = plugin.parameterValues[parameter.name] ?? parameter.defaultValue ?? ""
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missing.append(parameter.localizedLabel(language: activeLanguage))
            }
        }
        return missing
    }

    private func makeSnapshot(
        for plugin: PluginConfiguration,
        state: PluginSnapshotState = .idle,
        items: [UsageItem] = [],
        updatedAt: Date? = nil,
        badge: String? = nil,
        chart: PluginChart? = nil
    ) -> PluginSnapshot {
        PluginSnapshot(
            id: plugin.id,
            displayName: displayNames[plugin.id] ?? PluginDisplayNames.displayName(for: plugin, language: activeLanguage),
            state: state,
            items: items,
            updatedAt: updatedAt,
            badge: badge,
            iconURL: plugin.metadata?.icon,
            chart: chart
        )
    }

    private func isPluginReadyToRun(_ plugin: PluginConfiguration) -> Bool {
        missingRequiredParameters(for: plugin).isEmpty
    }

    // MARK: - Launch at Login

    func requestLaunchAtLogin(_ enabled: Bool) {
        guard enabled != configuration.launchAtLogin else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            configuration.launchAtLogin = enabled
            persistConfiguration()
        } catch {
            lastError = storeMessage(.launchAtLoginFailed(error.localizedDescription))
            objectWillChange.send()
        }
    }

    private enum StoreMessage {
        case configurationSaveFailed(String)
        case cacheSaveFailed(String)
        case pluginsDirectoryCreateFailed(String)
        case missingRequiredParameters([String])
        case updateCheckURLMissing
        case alreadyLatestVersion
        case updateCheckFailed(String)
        case downloadingUpdate
        case installingUpdate
        case updateFailed(String)
        case launchAtLoginFailed(String)
    }

    private func storeMessage(_ message: StoreMessage) -> String {
        switch (message, activeLanguage) {
        case (.configurationSaveFailed(let detail), .en):
            return "Failed to save configuration: \(detail)"
        case (.configurationSaveFailed(let detail), .zhHans):
            return "配置保存失败：\(detail)"
        case (.cacheSaveFailed(let detail), .en):
            return "Failed to save plugin cache: \(detail)"
        case (.cacheSaveFailed(let detail), .zhHans):
            return "插件缓存保存失败：\(detail)"
        case (.pluginsDirectoryCreateFailed(let detail), .en):
            return "Failed to create plugins folder: \(detail)"
        case (.pluginsDirectoryCreateFailed(let detail), .zhHans):
            return "插件目录创建失败：\(detail)"
        case (.missingRequiredParameters(let names), .en):
            return "Fill required parameters first: \(names.joined(separator: ", "))"
        case (.missingRequiredParameters(let names), .zhHans):
            return "请先填写必填参数：\(names.joined(separator: "、"))"
        case (.updateCheckURLMissing, .en):
            return "Update check URL is not configured"
        case (.updateCheckURLMissing, .zhHans):
            return "未配置更新检查地址"
        case (.alreadyLatestVersion, .en):
            return "You are on the latest version"
        case (.alreadyLatestVersion, .zhHans):
            return "当前已是最新版本"
        case (.updateCheckFailed(let detail), .en):
            return "Failed to check for updates: \(detail)"
        case (.updateCheckFailed(let detail), .zhHans):
            return "检查更新失败：\(detail)"
        case (.downloadingUpdate, .en):
            return "Downloading update..."
        case (.downloadingUpdate, .zhHans):
            return "正在下载更新..."
        case (.installingUpdate, .en):
            return "Installing update..."
        case (.installingUpdate, .zhHans):
            return "正在安装更新..."
        case (.updateFailed(let detail), .en):
            return "Update failed: \(detail)"
        case (.updateFailed(let detail), .zhHans):
            return "更新失败：\(detail)"
        case (.launchAtLoginFailed(let detail), .en):
            return "Failed to update launch at login: \(detail)"
        case (.launchAtLoginFailed(let detail), .zhHans):
            return "开机启动设置失败：\(detail)"
        }
    }
}
