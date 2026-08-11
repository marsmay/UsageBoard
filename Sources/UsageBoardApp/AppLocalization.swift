import Foundation
import UsageBoardCore

struct AppLocalization {
    @MainActor static var shared = AppLocalization(language: .zhHans)

    var language: AppLanguage

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

    func text(_ key: Key) -> String {
        switch (key, language) {
        case (.launchAtLogin, .en): return "Launch at Login"
        case (.launchAtLogin, .zhHans): return "开机启动"
        case (.launchAtLoginHint, .en): return "Launch UsageBoard at login"
        case (.launchAtLoginHint, .zhHans): return "登录时自动启动 UsageBoard"
        case (.displayMode, .en): return "Display Mode"
        case (.displayMode, .zhHans): return "显示模式"
        case (.displayModeHint, .en): return "Group by service or merge to a list"
        case (.displayModeHint, .zhHans): return "按服务分组或合并为列表"
        case (.chartMode, .en): return "Chart Mode"
        case (.chartMode, .zhHans): return "图表模式"
        case (.chartModeHint, .en): return "Show statistics as lines or stacked bars"
        case (.chartModeHint, .zhHans): return "以折线或堆叠直方展示统计数据"
        case (.language, .en): return "Language"
        case (.language, .zhHans): return "语言"
        case (.openPluginsFolder, .en): return "Open plugins folder"
        case (.openPluginsFolder, .zhHans): return "打开插件文件夹"
        case (.pluginAuthoringGuide, .en): return "Plugin authoring guide"
        case (.pluginAuthoringGuide, .zhHans): return "插件编写说明"
        case (.reset, .en): return "Reset"
        case (.reset, .zhHans): return "重置"
        case (.save, .en): return "Save"
        case (.save, .zhHans): return "保存"
        case (.selectPlugin, .en): return "Select a plugin to configure"
        case (.selectPlugin, .zhHans): return "选择一个插件查看配置"
        case (.version, .en): return "Version"
        case (.version, .zhHans): return "版本"
        case (.unknownVersion, .en): return "Unknown"
        case (.unknownVersion, .zhHans): return "未知"
        case (.checkingUpdate, .en): return "Updating..."
        case (.checkingUpdate, .zhHans): return "检查中..."
        case (.checkForUpdates, .en): return "Check for Updates"
        case (.checkForUpdates, .zhHans): return "检查更新"
        case (.aboutDescription, .en): return "Aggregates usage quotas for APIs and services"
        case (.aboutDescription, .zhHans): return "聚合展示各类 API 和服务的用量配额"
        case (.enabled, .en): return "Enabled"
        case (.enabled, .zhHans): return "启用"
        case (.name, .en): return "Name"
        case (.name, .zhHans): return "名称"
        case (.pluginNamePlaceholder, .en): return "Plugin name"
        case (.pluginNamePlaceholder, .zhHans): return "插件名称"
        case (.script, .en): return "Script"
        case (.script, .zhHans): return "脚本"
        case (.scriptPathPlaceholder, .en): return "Python script path"
        case (.scriptPathPlaceholder, .zhHans): return "Python 脚本路径"
        case (.refreshInterval, .en): return "Refresh"
        case (.refreshInterval, .zhHans): return "刷新间隔"
        case (.seconds, .en): return "seconds"
        case (.seconds, .zhHans): return "秒"
        case (.pluginParameters, .en): return "Plugin Parameters"
        case (.pluginParameters, .zhHans): return "插件参数"
        case (.noParameterMetadata, .en): return "No plugin parameter metadata found"
        case (.noParameterMetadata, .zhHans): return "未读取到插件参数元数据"
        case (.noPluginsTitle, .en): return "No Plugins"
        case (.noPluginsTitle, .zhHans): return "暂无插件"
        case (.noPluginsDescription, .en): return "Add plugins in Settings to show usage."
        case (.noPluginsDescription, .zhHans): return "在设置中添加插件后显示用量。"
        case (.refresh, .en): return "Refresh"
        case (.refresh, .zhHans): return "刷新"
        case (.waitingRefresh, .en): return "Waiting"
        case (.waitingRefresh, .zhHans): return "等待刷新"
        case (.pluginFailed, .en): return "Plugin execution failed"
        case (.pluginFailed, .zhHans): return "插件执行失败"
        case (.noUsageData, .en): return "No usage data"
        case (.noUsageData, .zhHans): return "暂无用量数据"
        case (.collapseTokenStats, .en): return "Collapse token stats"
        case (.collapseTokenStats, .zhHans): return "收起 token 统计"
        case (.expandTokenStats, .en): return "Expand token stats"
        case (.expandTokenStats, .zhHans): return "展开 token 统计"
        case (.totalTokenUsage, .en): return "Total tokens"
        case (.totalTokenUsage, .zhHans): return "Token 总量"
        case (.showAllLines, .en): return "Show all statistics"
        case (.showAllLines, .zhHans): return "显示全部统计项"
        case (.showOnlyTotalUsage, .en): return "Show only total tokens"
        case (.showOnlyTotalUsage, .zhHans): return "只显示 Token 总量"
        case (.noStatsData, .en): return "No stats data available"
        case (.noStatsData, .zhHans): return "暂无可用统计数据"
        case (.quitUsageBoard, .en): return "Quit UsageBoard"
        case (.quitUsageBoard, .zhHans): return "退出 UsageBoard"
        case (.restartRequiredTitle, .en): return "Restart Required"
        case (.restartRequiredTitle, .zhHans): return "需要重启"
        case (.restartRequiredMessage, .en): return "Language changes take effect after restarting UsageBoard."
        case (.restartRequiredMessage, .zhHans): return "语言设置会在重启 UsageBoard 后生效。"
        case (.restartNow, .en): return "Restart Now"
        case (.restartNow, .zhHans): return "现在重启"
        case (.restartLater, .en): return "Restart Later"
        case (.restartLater, .zhHans): return "稍后重启"
        case (.relaunchFailed, .en): return "Failed to restart UsageBoard"
        case (.relaunchFailed, .zhHans): return "重启 UsageBoard 失败"
        case (.searchPlugins, .en): return "Search plugins"
        case (.searchPlugins, .zhHans): return "搜索插件"
        case (.errorBadge, .en): return "Error"
        case (.errorBadge, .zhHans): return "错误"
        case (.settingsWindowTitle, .en): return "UsageBoard Settings"
        case (.settingsWindowTitle, .zhHans): return "UsageBoard 设置"
        case (.updateNow, .en): return "Update"
        case (.updateNow, .zhHans): return "更新"
        case (.cancel, .en): return "Cancel"
        case (.cancel, .zhHans): return "取消"
        case (.scriptPathNotFound, .en): return "Script file does not exist"
        case (.scriptPathNotFound, .zhHans): return "脚本文件不存在"
        }
    }

    enum Key {
        case launchAtLogin
        case launchAtLoginHint
        case displayMode
        case displayModeHint
        case chartMode
        case chartModeHint
        case language
        case openPluginsFolder
        case pluginAuthoringGuide
        case reset
        case save
        case selectPlugin
        case version
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
        case cancel
        case scriptPathNotFound
    }
}
