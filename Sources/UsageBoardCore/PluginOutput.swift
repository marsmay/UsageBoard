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
    public var credits: [PluginResetCredit]?

    public init(updatedAt: Date, items: [UsageItem], badge: String? = nil, badgeColor: String? = nil, chart: PluginChart? = nil, credits: [PluginResetCredit]? = nil) {
        self.updatedAt = updatedAt
        self.items = items
        self.badge = badge
        self.badgeColor = badgeColor
        self.chart = chart
        self.credits = credits
    }
}

/// A banked quota-reset credit (e.g. Codex rate-limit reset cards).
/// Plugins only report currently usable credits; redeemed/expired ones are filtered plugin-side.
public struct PluginResetCredit: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String?
    public var expiresAt: Date?

    public init(id: String, title: String? = nil, expiresAt: Date? = nil) {
        self.id = id
        self.title = title
        self.expiresAt = expiresAt
    }

    /// Remaining validity bucket driving the status dot color.
    public func urgency(now: Date = Date()) -> ResetCreditUrgency {
        guard let expiresAt else { return .unknown }
        let remaining = expiresAt.timeIntervalSince(now)
        if remaining <= 0 { return .expired }
        let days = remaining / 86_400
        if days < 7 { return .soon }
        if days < 14 { return .approaching }
        return .fresh
    }

    public enum ResetCreditUrgency: String, Equatable, Sendable {
        case fresh
        case approaching
        case soon
        case expired
        case unknown
    }

    /// Expiry timestamp reusing the same today/tomorrow rules as `UsageItem.resetText`.
    public func expiryText(now: Date = Date(), language: AppLanguage = .zhHans) -> String {
        guard let expiresAt else { return "--" }
        let calendar = Calendar.current
        let time = expiresAt.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(expiresAt, inSameDayAs: now) {
            return language == .en ? "Today \(time)" : "今天 \(time)"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(expiresAt, inSameDayAs: tomorrow) {
            return language == .en ? "Tomorrow \(time)" : "明天 \(time)"
        }
        let date = expiresAt.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
        return "\(date) \(time)"
    }

    /// Remaining validity: "剩余 22 天" / "22 days left", switching to hours under a day.
    public func remainingText(now: Date = Date(), language: AppLanguage = .zhHans) -> String {
        guard let expiresAt else { return "--" }
        let remaining = expiresAt.timeIntervalSince(now)
        if remaining <= 0 {
            return language == .en ? "Expired" : "已过期"
        }
        let days = Int(remaining / 86_400)
        if days >= 1 {
            return language == .en ? "\(days)d left" : "剩余 \(days) 天"
        }
        let hours = max(Int(remaining / 3_600), 1)
        return language == .en ? "\(hours)h left" : "剩余 \(hours) 小时"
    }

    /// "Expires Sep 21, 8:10 AM" / "9/21 8:10 到期" — the clause shown on the left of a credit row.
    public func expiryClause(now: Date = Date(), language: AppLanguage = .zhHans) -> String {
        let expiry = expiryText(now: now, language: language)
        switch language {
        case .en: return "Expires \(expiry)"
        case .zhHans: return "\(expiry) 到期"
        }
    }

    /// Bare "9/21 8:10" month/day + time for tight single-line card layouts.
    public func compactExpiryText() -> String {
        guard let expiresAt else { return "--" }
        let date = expiresAt.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
        let time = expiresAt.formatted(date: .omitted, time: .shortened)
        return "\(date) \(time)"
    }

    /// One-line summary shown in the dashboard: expiry plus remaining validity.
    public func lineText(now: Date = Date(), language: AppLanguage = .zhHans) -> String {
        let line = "\(expiryClause(now: now, language: language)) · \(remainingText(now: now, language: language))"
        guard let title, !title.isEmpty else { return line }
        return "\(title) · \(line)"
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
        guard used.isFinite, limit.isFinite, limit > 0 else { return 0 }
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
        guard value.isFinite else { return "--" }
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }
}
