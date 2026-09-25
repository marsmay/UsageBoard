@preconcurrency import Foundation

public enum PluginDisplayNames {
    public static func make(for plugins: [PluginConfiguration], language: AppLanguage = .en) -> [UUID: String] {
        var counts: [String: Int] = [:]
        var names: [UUID: String] = [:]

        for plugin in plugins {
            let baseName = displayName(for: plugin, language: language)
            let nextCount = (counts[baseName] ?? 0) + 1
            counts[baseName] = nextCount
            names[plugin.id] = nextCount == 1 ? baseName : "\(baseName) \(nextCount)"
        }

        return names
    }

    public static func displayName(for plugin: PluginConfiguration, language: AppLanguage = .en) -> String {
        let configuredName = plugin.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let metadata = plugin.metadata,
           let baseMetadataName = metadata.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !baseMetadataName.isEmpty,
           configuredName.isEmpty || configuredName == baseMetadataName {
            return metadata.localizedName(language: language) ?? baseMetadataName
        }

        if !configuredName.isEmpty {
            return configuredName
        }

        return language == .en ? "Untitled" : "未命名"
    }
}
