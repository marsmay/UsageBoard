import SwiftUI
import UsageBoardCore

struct PluginGroupView: View {
    var snapshot: PluginSnapshot
    var language: AppLanguage
    var nextRefreshAt: Date?
    var onRefresh: (() -> Void)?
    @State private var isChartExpanded = false
    private var strings: AppLocalization {
        .shared
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                header

                Divider()

                if case .failed(let message) = snapshot.state {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 8)
                } else if snapshot.items.isEmpty && snapshot.chart == nil {
                    Text(strings.text(.noUsageData))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 18)
                } else if !snapshot.items.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(snapshot.items) { item in
                            UsageItemRow(item: item, language: language)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, snapshot.chart == nil ? 10 : 0)

            if let chart = snapshot.chart {
                if snapshot.items.isEmpty {
                    TokenUsageChartView(chart: chart, language: language)
                        .padding(.horizontal, 12)
                        .padding(.top, 2)
                        .padding(.bottom, 8)
                } else {
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isChartExpanded.toggle()
                            }
                        } label: {
                            VStack(spacing: 0) {
                                Divider()
                                    .padding(.top, 8)
                                Image(systemName: isChartExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, minHeight: 22)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(isChartExpanded ? strings.text(.collapseTokenStats) : strings.text(.expandTokenStats))

                        if isChartExpanded {
                            TokenUsageChartView(chart: chart, language: language)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 8)
                        }
                    }
                }
            }
        }
        .background(UB.Canvas.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: UB.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: UB.Radius.card, style: .continuous)
                .stroke(UB.Canvas.separator.opacity(0.7), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 1, y: 1)
    }

    private var header: some View {
        HStack(spacing: 8) {
            BrandTile(iconURL: snapshot.iconURL, fallbackName: snapshot.displayName, size: 22)
            Text(snapshot.displayName)
                .font(UB.Font.cardTitle)
                .lineLimit(1)
            if let badge = snapshot.badge {
                PlanTag(text: badge, colorName: snapshot.badgeColor)
            }
            if case .failed = snapshot.state {
                Text(strings.text(.errorBadge))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.red.opacity(0.10))
                    .clipShape(Capsule())
            }
            Spacer()
            stateView
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch snapshot.state {
        case .idle:
            Text(strings.text(.waitingRefresh))
                .font(UB.Font.countdown)
                .foregroundStyle(.secondary)
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .ready, .failed:
            CountdownLabel(target: nextRefreshAt)
            Button {
                onRefresh?()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }

}
