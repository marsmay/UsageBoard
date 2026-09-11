import Foundation
import UsageBoardCore

struct AppLocalization {
    @MainActor static var shared = AppLocalization(language: .zhHans)

    var language: AppLanguage

    func themeName(_ theme: AppTheme) -> String {
        switch (theme, language) {
        case (.light, .en): return "Light"
        case (.light, .zhHans): return "浅色"
        case (.dark, .en): return "Dark"
        case (.dark, .zhHans): return "深色"
        case (.system, .en): return "System"
        case (.system, .zhHans): return "跟随系统"
        }
    }

    func displayModeName(_ mode: DisplayMode) -> String {
        switch (mode, language) {
        case (.grouped, .en): return "Grouped"
        case (.grouped, .zhHans): return "分组"
        case (.tabs, .en): return "Tabs"
        case (.tabs, .zhHans): return "标签页"
        }
    }

    func chartModeName(_ mode: ChartMode) -> String {
        switch (mode, language) {
        case (.line, .en): return "Line Chart"
        case (.line, .zhHans): return "折线图"
        case (.bar, .en): return "Bar Chart"
        case (.bar, .zhHans): return "直方图"
        }
    }

    func tabTitle(_ tab: SettingsTab) -> String {
        switch (tab, language) {
        case (.general, .en): return "General"
        case (.general, .zhHans): return "通用"
        case (.plugins, .en): return "Plugins"
        case (.plugins, .zhHans): return "插件"
        case (.about, .en): return "About"
        case (.about, .zhHans): return "关于"
        }
    }

    func tabSubtitle(_ tab: SettingsTab) -> String {
        switch (tab, language) {
        case (.general, .en): return "Launch, language, and display"
        case (.general, .zhHans): return "启动、语言与显示"
        case (.plugins, .en): return "Manage API usage plugins"
        case (.plugins, .zhHans): return "管理 API 用量查询插件"
        case (.about, .en): return "App information and updates"
        case (.about, .zhHans): return "应用信息与更新"
        }
    }

    func usageSuffix(for name: String) -> String {
        language == .en ? "\(name) usage" : "\(name) 用量"
    }

    func showOnlyUsageSuffix(for name: String) -> String {
        language == .en ? "Show only \(name)" : "只显示 \(name)"
    }

    func updateAvailableTitle(latestVersion: String) -> String {
        language == .en ? "New version \(latestVersion) available" : "发现新版本 \(latestVersion)"
    }

    func updateAvailableMessage(currentVersion: String, latestVersion: String) -> String {
        switch language {
        case .en:
            return "Current version \(currentVersion), new version \(latestVersion).\nDownload and update now?"
        case .zhHans:
            return "当前版本 \(currentVersion)，新版本 \(latestVersion)。\n是否立即下载并更新？"
        }
    }

    func resetCardsSummary(remaining: String) -> String {
        language == .en ? "Next expiry · \(remaining)" : "最近到期 · \(remaining)"
    }

    func resetCardsAction(isExpanded: Bool) -> String {
        if language == .en {
            return isExpanded ? "Hide reset card details" : "Show reset card details"
        }
        return isExpanded ? "收起重置卡明细" : "展开重置卡明细"
    }

    func disclosureState(isExpanded: Bool) -> String {
        if language == .en {
            return isExpanded ? "Expanded" : "Collapsed"
        }
        return isExpanded ? "已展开" : "已收起"
    }

    func text(_ key: Key) -> String {
        switch language {
        case .en: return englishText(key)
        case .zhHans: return chineseText(key)
        }
    }

    private func englishText(_ key: Key) -> String {
        switch key {
        case .discardChanges: return "Discard Changes"
        case .unsavedChanges: return "Save changes before switching plugins?"
        case .noSearchResults: return "No matching plugins"
        case .reloadMetadata: return "Reload metadata"
        case .chooseScript: return "Choose script"
        case .removePlugin: return "Remove plugin"
        case .addPlugin: return "Add plugin"
        case .launchAtLogin: return "Launch at Login"
        case .launchAtLoginHint: return "Launch UsageBoard at login"
        case .autoUpdateCheck: return "Automatic Updates"
        case .autoUpdateCheckHint: return "Periodically check for new versions and notify"
        case .displayMode: return "Display Mode"
        case .displayModeHint: return "Show services in groups or tabs"
        case .chartMode: return "Chart Mode"
        case .chartModeHint: return "Show statistics as lines or stacked bars"
        case .theme: return "Theme"
        case .appearanceSection: return "Appearance"
        case .behaviorSection: return "Behavior"
        case .languageRestartHint: return "Applies after restarting"
        case .language: return "Language"
        case .openPluginsFolder: return "Open plugins folder"
        case .pluginAuthoringGuide: return "Plugin authoring guide"
        case .reset: return "Reset"
        case .save: return "Save"
        case .selectPlugin: return "Select a plugin to configure"
        case .unknownVersion: return "Unknown"
        case .checkingUpdate: return "Checking..."
        case .checkForUpdates: return "Check for Updates"
        case .aboutDescription: return "Aggregates usage quotas for APIs and services"
        case .enabled: return "Enabled"
        case .name: return "Name"
        case .pluginNamePlaceholder: return "Plugin name"
        case .script: return "Script"
        case .scriptPathPlaceholder: return "Python script path"
        case .refreshInterval: return "Refresh"
        case .seconds: return "seconds"
        case .pluginParameters: return "Plugin Parameters"
        case .noParameterMetadata: return "No plugin parameter metadata found"
        case .noPluginsTitle: return "No Plugins"
        case .noPluginsDescription: return "Add plugins in Settings to show usage."
        case .refresh: return "Refresh"
        case .waitingRefresh: return "Waiting"
        case .pluginFailed: return "Plugin execution failed"
        case .noUsageData: return "No usage data"
        case .collapseTokenStats: return "Collapse token stats"
        case .expandTokenStats: return "Expand token stats"
        case .totalTokenUsage: return "Total tokens"
        case .chartTooltipTotal: return "Total"
        case .showAllLines: return "Show all statistics"
        case .showOnlyTotalUsage: return "Show only total tokens"
        case .noStatsData: return "No stats data available"
        case .quitUsageBoard: return "Quit UsageBoard"
        case .restartRequiredTitle: return "Apply the new language now?"
        case .restartRequiredMessage: return "Restart UsageBoard to use the new language. You can also restart later; your language selection will be kept."
        case .restartNow: return "Restart Now"
        case .restartLater: return "Restart Later"
        case .relaunchFailed: return "Failed to restart UsageBoard"
        case .searchPlugins: return "Search plugins"
        case .errorBadge: return "Error"
        case .settingsWindowTitle: return "UsageBoard Settings"
        case .updateNow: return "Update"
        case .updateLater: return "Later"
        case .cancel: return "Cancel"
        case .scriptPathNotFound: return "Script file does not exist"
        case .resetCards: return "Reset cards"
        }
    }

    private func chineseText(_ key: Key) -> String {
        switch key {
        case .discardChanges: return "放弃更改"
        case .unsavedChanges: return "切换插件前保存更改？"
        case .noSearchResults: return "未找到匹配插件"
        case .reloadMetadata: return "重新加载元数据"
        case .chooseScript: return "选择脚本"
        case .removePlugin: return "移除插件"
        case .addPlugin: return "添加插件"
        case .launchAtLogin: return "开机启动"
        case .launchAtLoginHint: return "登录时自动启动 UsageBoard"
        case .autoUpdateCheck: return "自动更新"
        case .autoUpdateCheckHint: return "定时检查新版本并提示"
        case .displayMode: return "显示模式"
        case .displayModeHint: return "按服务分组或通过标签页切换"
        case .chartMode: return "图表模式"
        case .chartModeHint: return "以折线或堆叠直方展示统计数据"
        case .theme: return "主题"
        case .appearanceSection: return "外观"
        case .behaviorSection: return "使用偏好"
        case .languageRestartHint: return "重启应用后生效"
        case .language: return "语言"
        case .openPluginsFolder: return "打开插件文件夹"
        case .pluginAuthoringGuide: return "插件编写说明"
        case .reset: return "重置"
        case .save: return "保存"
        case .selectPlugin: return "选择一个插件查看配置"
        case .unknownVersion: return "未知"
        case .checkingUpdate: return "检查中..."
        case .checkForUpdates: return "检查更新"
        case .aboutDescription: return "聚合展示各类 API 和服务的用量配额"
        case .enabled: return "启用"
        case .name: return "名称"
        case .pluginNamePlaceholder: return "插件名称"
        case .script: return "脚本"
        case .scriptPathPlaceholder: return "Python 脚本路径"
        case .refreshInterval: return "刷新间隔"
        case .seconds: return "秒"
        case .pluginParameters: return "插件参数"
        case .noParameterMetadata: return "未读取到插件参数元数据"
        case .noPluginsTitle: return "暂无插件"
        case .noPluginsDescription: return "在设置中添加插件后显示用量。"
        case .refresh: return "刷新"
        case .waitingRefresh: return "等待刷新"
        case .pluginFailed: return "插件执行失败"
        case .noUsageData: return "暂无用量数据"
        case .collapseTokenStats: return "收起 token 统计"
        case .expandTokenStats: return "展开 token 统计"
        case .totalTokenUsage: return "Token 总量"
        case .chartTooltipTotal: return "总量"
        case .showAllLines: return "显示全部统计项"
        case .showOnlyTotalUsage: return "只显示 Token 总量"
        case .noStatsData: return "暂无可用统计数据"
        case .quitUsageBoard: return "退出 UsageBoard"
        case .restartRequiredTitle: return "立即应用新语言？"
        case .restartRequiredMessage: return "重启 UsageBoard 后，界面将使用新语言。也可以稍后重启，所选语言会保留。"
        case .restartNow: return "立即重启"
        case .restartLater: return "稍后重启"
        case .relaunchFailed: return "重启 UsageBoard 失败"
        case .searchPlugins: return "搜索插件"
        case .errorBadge: return "错误"
        case .settingsWindowTitle: return "UsageBoard 设置"
        case .updateNow: return "更新"
        case .updateLater: return "稍后更新"
        case .cancel: return "取消"
        case .scriptPathNotFound: return "脚本文件不存在"
        case .resetCards: return "重置卡"
        }
    }

    enum Key {
        case discardChanges
        case unsavedChanges
        case noSearchResults
        case reloadMetadata
        case chooseScript
        case removePlugin
        case addPlugin
        case launchAtLogin
        case launchAtLoginHint
        case autoUpdateCheck
        case autoUpdateCheckHint
        case displayMode
        case displayModeHint
        case chartMode
        case chartModeHint
        case language
        case theme
        case appearanceSection
        case behaviorSection
        case languageRestartHint
        case openPluginsFolder
        case pluginAuthoringGuide
        case reset
        case save
        case selectPlugin
        case unknownVersion
        case checkingUpdate
        case checkForUpdates
        case aboutDescription
        case enabled
        case name
        case pluginNamePlaceholder
        case script
        case scriptPathPlaceholder
        case refreshInterval
        case seconds
        case pluginParameters
        case noParameterMetadata
        case noPluginsTitle
        case noPluginsDescription
        case refresh
        case waitingRefresh
        case pluginFailed
        case noUsageData
        case collapseTokenStats
        case expandTokenStats
        case totalTokenUsage
        case chartTooltipTotal
        case showAllLines
        case showOnlyTotalUsage
        case noStatsData
        case quitUsageBoard
        case restartRequiredTitle
        case restartRequiredMessage
        case restartNow
        case restartLater
        case relaunchFailed
        case searchPlugins
        case errorBadge
        case settingsWindowTitle
        case updateNow
        case updateLater
        case cancel
        case scriptPathNotFound
        case resetCards
    }
}
