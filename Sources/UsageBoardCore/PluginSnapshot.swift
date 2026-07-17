@preconcurrency import Foundation

public enum PluginSnapshotState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed(String)
}

public struct PluginSnapshot: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String
    public var state: PluginSnapshotState
    public var items: [UsageItem]
    public var updatedAt: Date?
    public var badge: String?
    public var badgeColor: String?
    public var iconURL: String?
    public var chart: PluginChart?

    public init(
        id: UUID,
        displayName: String,
        state: PluginSnapshotState = .idle,
        items: [UsageItem] = [],
        updatedAt: Date? = nil,
        badge: String? = nil,
        badgeColor: String? = nil,
        iconURL: String? = nil,
        chart: PluginChart? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.state = state
        self.items = items
        self.updatedAt = updatedAt
        self.badge = badge
        self.badgeColor = badgeColor
        self.iconURL = iconURL
        self.chart = chart
    }
}

public struct PluginCachedState: Codable, Equatable, Sendable {
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
