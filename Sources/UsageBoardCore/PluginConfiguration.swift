@preconcurrency import Foundation

public enum PluginParameterType: String, Codable, CaseIterable, Identifiable, Sendable {
    case string
    case secret
    case integer
    case boolean
    case choice
    case directory
    case file

    public var id: String { rawValue }
}

public struct PluginParameterOption: Codable, Equatable, Identifiable, Sendable {
    public var label: String
    public var labelTranslations: [String: String]
    public var value: String

    public var id: String { value }

    public init(label: String, value: String, labelTranslations: [String: String] = [:]) {
        self.label = label
        self.labelTranslations = labelTranslations
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case label
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dynamicContainer = try decoder.container(keyedBy: AnyCodingKey.self)
        label = try container.decode(String.self, forKey: .label)
        value = try container.decode(String.self, forKey: .value)
        labelTranslations = Self.decodeTranslations(prefix: "label@", from: dynamicContainer)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        try container.encode(label, forKey: AnyCodingKey(stringValue: CodingKeys.label.rawValue))
        try container.encode(value, forKey: AnyCodingKey(stringValue: CodingKeys.value.rawValue))
        try Self.encodeTranslations(labelTranslations, prefix: "label@", to: &container)
    }

    public func localizedLabel(language: AppLanguage) -> String {
        LocalizedStrings.localizedValue(base: label, translations: labelTranslations, language: language)
    }
}

public struct PluginParameterMetadata: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var label: String
    public var labelTranslations: [String: String]
    public var type: PluginParameterType
    public var required: Bool
    public var placeholder: String?
    public var placeholderTranslations: [String: String]
    public var defaultValue: String?
    public var options: [PluginParameterOption]

    public var id: String { name }

    public init(
        name: String,
        label: String? = nil,
        labelTranslations: [String: String] = [:],
        type: PluginParameterType = .string,
        required: Bool = false,
        placeholder: String? = nil,
        placeholderTranslations: [String: String] = [:],
        defaultValue: String? = nil,
        options: [PluginParameterOption] = []
    ) {
        self.name = name
        self.label = label ?? name
        self.labelTranslations = labelTranslations
        self.type = type
        self.required = required
        self.placeholder = placeholder
        self.placeholderTranslations = placeholderTranslations
        self.defaultValue = defaultValue
        self.options = options
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case label
        case type
        case required
        case placeholder
        case defaultValue
        case options
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dynamicContainer = try decoder.container(keyedBy: AnyCodingKey.self)
        name = try container.decode(String.self, forKey: .name)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? name
        labelTranslations = Self.decodeTranslations(prefix: "label@", from: dynamicContainer)
        type = try container.decodeIfPresent(PluginParameterType.self, forKey: .type) ?? .string
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        placeholderTranslations = Self.decodeTranslations(prefix: "placeholder@", from: dynamicContainer)
        defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
        options = try container.decodeIfPresent([PluginParameterOption].self, forKey: .options) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        try container.encode(name, forKey: AnyCodingKey(stringValue: CodingKeys.name.rawValue))
        try container.encode(label, forKey: AnyCodingKey(stringValue: CodingKeys.label.rawValue))
        try Self.encodeTranslations(labelTranslations, prefix: "label@", to: &container)
        try container.encode(type, forKey: AnyCodingKey(stringValue: CodingKeys.type.rawValue))
        try container.encode(required, forKey: AnyCodingKey(stringValue: CodingKeys.required.rawValue))
        try container.encodeIfPresent(placeholder, forKey: AnyCodingKey(stringValue: CodingKeys.placeholder.rawValue))
        try Self.encodeTranslations(placeholderTranslations, prefix: "placeholder@", to: &container)
        try container.encodeIfPresent(defaultValue, forKey: AnyCodingKey(stringValue: CodingKeys.defaultValue.rawValue))
        try container.encode(options, forKey: AnyCodingKey(stringValue: CodingKeys.options.rawValue))
    }

    public func localizedLabel(language: AppLanguage) -> String {
        LocalizedStrings.localizedValue(base: label, translations: labelTranslations, language: language)
    }

    public func localizedPlaceholder(language: AppLanguage) -> String? {
        LocalizedStrings.localizedOptionalValue(base: placeholder, translations: placeholderTranslations, language: language)
    }
}

extension PluginConfiguration {
    /// 重新解析当前执行路径的 metadata，并为新增参数补默认值；已有参数值保留。
    /// addPlugin/updatePlugin/reloadMetadata 及设置页草稿共用同一套归一逻辑。
    public func reloadingMetadata() -> PluginConfiguration {
        var updated = self
        updated.metadata = PluginMetadataParser.parse(fileURL: URL(fileURLWithPath: executablePath))
        for parameter in updated.metadata?.parameters ?? [] where updated.parameterValues[parameter.name] == nil {
            updated.parameterValues[parameter.name] = parameter.defaultValue ?? ""
        }
        return updated
    }
}

public struct PluginMetadata: Codable, Equatable, Sendable {
    public var name: String?
    public var nameTranslations: [String: String]
    public var description: String?
    public var descriptionTranslations: [String: String]
    public var icon: String?
    public var parameters: [PluginParameterMetadata]

    public init(
        name: String? = nil,
        nameTranslations: [String: String] = [:],
        description: String? = nil,
        descriptionTranslations: [String: String] = [:],
        icon: String? = nil,
        parameters: [PluginParameterMetadata] = []
    ) {
        self.name = name
        self.nameTranslations = nameTranslations
        self.description = description
        self.descriptionTranslations = descriptionTranslations
        self.icon = icon
        self.parameters = parameters
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case icon
        case parameters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dynamicContainer = try decoder.container(keyedBy: AnyCodingKey.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        nameTranslations = Self.decodeTranslations(prefix: "name@", from: dynamicContainer)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        descriptionTranslations = Self.decodeTranslations(prefix: "description@", from: dynamicContainer)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        parameters = try container.decodeIfPresent([PluginParameterMetadata].self, forKey: .parameters) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        try container.encodeIfPresent(name, forKey: AnyCodingKey(stringValue: CodingKeys.name.rawValue))
        try Self.encodeTranslations(nameTranslations, prefix: "name@", to: &container)
        try container.encodeIfPresent(description, forKey: AnyCodingKey(stringValue: CodingKeys.description.rawValue))
        try Self.encodeTranslations(descriptionTranslations, prefix: "description@", to: &container)
        try container.encodeIfPresent(icon, forKey: AnyCodingKey(stringValue: CodingKeys.icon.rawValue))
        try container.encode(parameters, forKey: AnyCodingKey(stringValue: CodingKeys.parameters.rawValue))
    }

    public func localizedName(language: AppLanguage) -> String? {
        LocalizedStrings.localizedOptionalValue(base: name, translations: nameTranslations, language: language)
    }

    public func localizedDescription(language: AppLanguage) -> String? {
        LocalizedStrings.localizedOptionalValue(base: description, translations: descriptionTranslations, language: language)
    }
}

public struct PluginConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var stateID: String
    public var name: String
    public var enabled: Bool
    public var executablePath: String
    public var refreshIntervalSeconds: Int
    public var metadata: PluginMetadata?
    public var parameterValues: [String: String]

    public init(
        id: UUID = UUID(),
        stateID: String = UUID().uuidString,
        name: String,
        enabled: Bool = true,
        executablePath: String,
        refreshIntervalSeconds: Int = 300,
        metadata: PluginMetadata? = nil,
        parameterValues: [String: String] = [:]
    ) {
        self.id = id
        self.stateID = stateID
        self.name = name
        self.enabled = enabled
        self.executablePath = executablePath
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.metadata = metadata
        self.parameterValues = parameterValues
    }

    private enum CodingKeys: String, CodingKey {
        case stateID
        case name
        case enabled
        case executablePath
        case refreshIntervalSeconds
        case metadata
        case parameterValues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        stateID = try container.decodeIfPresent(String.self, forKey: .stateID) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        executablePath = try container.decodeIfPresent(String.self, forKey: .executablePath) ?? ""
        refreshIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds) ?? 300
        metadata = try container.decodeIfPresent(PluginMetadata.self, forKey: .metadata)
        parameterValues = try container.decodeIfPresent([String: String].self, forKey: .parameterValues) ?? [:]
    }
}
