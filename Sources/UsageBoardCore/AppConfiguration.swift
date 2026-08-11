@preconcurrency import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case zhHans = "zh-Hans"
    case en

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .zhHans: return "中文"
        case .en: return "English"
        }
    }
}

public enum DisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case grouped
    case tabs

    public var id: String { rawValue }
}

public enum ChartMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case line
    case bar

    public var id: String { rawValue }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var language: AppLanguage
    public var overviewDisplayMode: DisplayMode
    public var chartMode: ChartMode
    public var plugins: [PluginConfiguration]
    public var launchAtLogin: Bool

    public init(
        schemaVersion: Int = 1,
        language: AppLanguage = .zhHans,
        overviewDisplayMode: DisplayMode = .tabs,
        chartMode: ChartMode = .line,
        plugins: [PluginConfiguration] = [],
        launchAtLogin: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.language = language
        self.overviewDisplayMode = overviewDisplayMode
        self.chartMode = chartMode
        self.plugins = plugins
        self.launchAtLogin = launchAtLogin
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case language
        case overviewDisplayMode
        case chartMode
        case plugins
        case launchAtLogin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .zhHans
        overviewDisplayMode = try container.decodeIfPresent(DisplayMode.self, forKey: .overviewDisplayMode) ?? .tabs
        chartMode = try container.decodeIfPresent(ChartMode.self, forKey: .chartMode) ?? .line
        plugins = try container.decodeIfPresent([PluginConfiguration].self, forKey: .plugins) ?? []
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    }
}
