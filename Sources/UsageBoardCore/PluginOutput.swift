@preconcurrency import Foundation

public enum UsageDisplayStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case percent
    case ratio

    public var id: String { rawValue }
}

public enum UsageStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal
    case warning
    case critical
    case unknown

    public var id: String { rawValue }
}

public struct PluginOutput: Decodable, Equatable, Sendable {
    public var updatedAt: Date
    public var items: [UsageItem]
    public var badge: String?
    public var badgeColor: String?
    public var chart: PluginChart?

    public init(updatedAt: Date, items: [UsageItem], badge: String? = nil, badgeColor: String? = nil, chart: PluginChart? = nil) {
        self.updatedAt = updatedAt
        self.items = items
        self.badge = badge
        self.badgeColor = badgeColor
        self.chart = chart
    }
}

public struct PluginChart: Codable, Equatable, Sendable {
    public var kind: String
    public var period: String
    public var bucketUnit: String
    public var buckets: [PluginChartBucket]
    public var message: String?

    private static let validBucketUnits: Set<String> = ["hour", "day"]

    private static func normalizedBucketUnit(_ value: String) -> String {
        validBucketUnits.contains(value) ? value : "day"
    }

    public init(
        kind: String = "line",
        period: String,
        bucketUnit: String,
        buckets: [PluginChartBucket],
        message: String? = nil
    ) {
        self.kind = kind
        self.period = period
        self.bucketUnit = Self.normalizedBucketUnit(bucketUnit)
        self.buckets = buckets
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decode(String.self, forKey: .kind)
        self.period = try container.decode(String.self, forKey: .period)
        let rawBucketUnit = try container.decode(String.self, forKey: .bucketUnit)
        self.bucketUnit = Self.normalizedBucketUnit(rawBucketUnit)
        self.buckets = try container.decode([PluginChartBucket].self, forKey: .buckets)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

public struct PluginChartBucket: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var segments: [PluginChartSegment]

    public init(id: String, label: String, segments: [PluginChartSegment]) {
        self.id = id
        self.label = label
        self.segments = segments
    }

    public var total: Double {
        segments.reduce(0) { $0 + max($1.tokens, 0) }
    }
}

public struct PluginChartSegment: Codable, Equatable, Identifiable, Sendable {
    public var model: String
    public var tokens: Double

    public init(model: String, tokens: Double) {
        self.model = model
        self.tokens = tokens
    }

    public var id: String { model }
}

public struct UsageItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var used: Double
    public var limit: Double
    public var displayStyle: UsageDisplayStyle
    public var resetAt: Date?
    public var status: UsageStatus
    public var color: String?

    public init(
        id: String,
        name: String,
        used: Double,
        limit: Double,
        displayStyle: UsageDisplayStyle,
        resetAt: Date? = nil,
        status: UsageStatus = .unknown,
        color: String? = nil
    ) {
        self.id = id
        self.name = name
        self.used = used
        self.limit = limit
        self.displayStyle = displayStyle
        self.resetAt = resetAt
        self.status = status
        self.color = color
    }

    public var progress: Double {
        guard limit > 0 else { return 0 }
        return min(max(used / limit, 0), 1)
    }

    public func displayValue() -> String {
        switch displayStyle {
        case .percent:
            return "\(Int((progress * 100).rounded()))%"
        case .ratio:
            return "\(UsageItem.formatNumber(used)) / \(UsageItem.formatNumber(limit))"
        }
    }

    public func resetText(now: Date = Date(), language: AppLanguage = .zhHans) -> String {
        guard let resetAt, resetAt > now else { return "--" }
        let calendar = Calendar.current
        let time = resetAt.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(resetAt, inSameDayAs: now) {
            return language == .en ? "Today \(time)" : "今天 \(time)"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(resetAt, inSameDayAs: tomorrow) {
            return language == .en ? "Tomorrow \(time)" : "明天 \(time)"
        }
        let date = resetAt.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
        return "\(date) \(time)"
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}
