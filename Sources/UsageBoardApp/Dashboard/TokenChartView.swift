import SwiftUI
import UsageBoardCore

struct TokenUsageChartView: View {
    var chart: PluginChart
    var language: AppLanguage
    var chartMode: ChartMode
    @State private var selectedSeries: String?
    @State private var chartHover: TokenChartHover?
    @State private var chartHoverLocation: CGPoint?
    @State private var chartContentMinX: CGFloat = 0
    private var strings: AppLocalization {
        .shared
    }

    private var series: [TokenChartSeries] {
        var output = [
            TokenChartSeries(
                name: strings.text(.totalTokenUsage),
                tooltipName: strings.text(.chartTooltipTotal),
                color: .blue,
                values: chart.buckets.map(\.total)
            )
        ]
        output.append(contentsOf: modelSummaries.map { summary in
            TokenChartSeries(
                name: strings.usageSuffix(for: summary.name),
                tooltipName: summary.name,
                color: summary.color,
                values: chart.buckets.map { bucket in
                    bucket.segments.first(where: { $0.model == summary.name })?.tokens ?? 0
                }
            )
        })
        return output
    }

    private var visibleSeries: [TokenChartSeries] {
        let filtered = series.filter { $0.values.contains(where: { $0 > 0 }) }
        guard let selectedSeries else { return filtered }
        let selected = filtered.filter { $0.name == selectedSeries }
        return selected.isEmpty ? filtered : selected
    }

    private var visibleBarSeries: [TokenChartSeries] {
        TokenBarChartModel.series(
            all: series,
            selectedSeriesName: selectedSeries,
            totalSeriesName: strings.text(.totalTokenUsage)
        )
    }

    private var visibleBarTooltipSeries: [TokenChartSeries] {
        TokenBarChartModel.tooltipSeries(
            all: series,
            selectedSeriesName: selectedSeries
        )
    }

    private var modelSummaries: [TokenModelSummary] {
        var totals: [String: Double] = [:]
        for bucket in chart.buckets {
            for segment in bucket.segments {
                totals[segment.model, default: 0] += max(segment.tokens, 0)
            }
        }
        return totals
            .filter { $0.key != "总计" }
            .sorted(by: { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            })
            .enumerated()
            .map { index, element in
                TokenModelSummary(name: element.key, total: element.value, color: modelColor(at: index))
            }
    }

    private var totalTokens: Double {
        chart.buckets.reduce(0) { $0 + $1.total }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if chart.buckets.contains(where: { !$0.segments.isEmpty }) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    Button {
                        selectedSeries = selectedSeries == strings.text(.totalTokenUsage) ? nil : strings.text(.totalTokenUsage)
                    } label: {
                        TokenMetricView(
                            title: strings.text(.totalTokenUsage),
                            value: totalTokens,
                            color: .blue,
                            isSelected: selectedSeries == strings.text(.totalTokenUsage)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(selectedSeries == strings.text(.totalTokenUsage) ? strings.text(.showAllLines) : strings.text(.showOnlyTotalUsage))

                    ForEach(modelSummaries) { summary in
                        Button {
                            let seriesName = strings.usageSuffix(for: summary.name)
                            selectedSeries = selectedSeries == seriesName ? nil : seriesName
                        } label: {
                            TokenMetricView(
                                title: strings.usageSuffix(for: summary.name),
                                value: summary.total,
                                color: summary.color,
                                isSelected: selectedSeries == strings.usageSuffix(for: summary.name)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help(selectedSeries == strings.usageSuffix(for: summary.name) ? strings.text(.showAllLines) : strings.showOnlyUsageSuffix(for: summary.name))
                    }
                }

                GeometryReader { viewport in
                    let resolvedWidth = resolvedChartWidth(for: viewport.size.width)
                    let resolvedHover = validHover
                    ScrollView(.horizontal, showsIndicators: false) {
                        Group {
                            switch chartMode {
                            case .line:
                                TokenLineChartPlot(
                                    buckets: chart.buckets,
                                    series: visibleSeries,
                                    maxValue: max(visibleSeries.flatMap(\.values).max() ?? 0, 1),
                                    hoverIndex: resolvedHover?.index
                                )
                                .frame(width: resolvedWidth, height: TokenChartLayout.height)
                            case .bar:
                                TokenBarChartPlot(
                                    buckets: chart.buckets,
                                    series: visibleBarSeries,
                                    maxValue: max(TokenBarChartModel.maximum(for: visibleBarSeries), 1),
                                    hoverIndex: resolvedHover?.index
                                )
                                .frame(width: resolvedWidth, height: TokenChartLayout.height)
                            }
                        }
                        .background(
                            GeometryReader { content in
                                Color.clear.preference(
                                    key: TokenChartContentMinXPreferenceKey.self,
                                    value: content.frame(in: .named("TokenChartViewport")).minX
                                )
                            }
                        )
                    }
                    .coordinateSpace(name: "TokenChartViewport")
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            chartHoverLocation = location
                            updateChartHover(
                                at: location,
                                contentMinX: chartContentMinX,
                                contentWidth: resolvedWidth
                            )
                        case .ended:
                            chartHoverLocation = nil
                            chartHover = nil
                        }
                    }
                    .onPreferenceChange(TokenChartContentMinXPreferenceKey.self) { minX in
                        chartContentMinX = minX
                        if let chartHoverLocation {
                            updateChartHover(
                                at: chartHoverLocation,
                                contentMinX: minX,
                                contentWidth: resolvedWidth
                            )
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        tooltip(at: resolvedHover?.index ?? chart.buckets.startIndex)
                            .offset(
                                x: TokenChartLayout.tooltipOriginX(
                                    anchorX: resolvedHover?.anchorX ?? TokenChartLayout.tooltipMargin,
                                    visibleWidth: viewport.size.width
                                ),
                                y: TokenChartLayout.tooltipOffsetY
                            )
                            .opacity(resolvedHover == nil ? 0 : 1)
                            .allowsHitTesting(false)
                            .accessibilityHidden(resolvedHover == nil)
                    }
                }
                .frame(height: TokenChartLayout.height)
                .onChange(of: chartMode) { _ in
                    chartHover = nil
                    chartHoverLocation = nil
                }
            } else {
                Text(chart.message ?? strings.text(.noStatsData))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            }
        }
    }

    private var tooltipSeries: [TokenChartSeries] {
        chartMode == .line ? visibleSeries : visibleBarTooltipSeries
    }

    private var validHover: TokenChartHover? {
        guard let chartHover,
              chart.buckets.indices.contains(chartHover.index) else { return nil }
        return chartHover
    }

    private func updateChartHover(at location: CGPoint, contentMinX: CGFloat, contentWidth: CGFloat) {
        let hover = TokenChartHoverModel.hover(
            at: location,
            contentMinX: contentMinX,
            contentWidth: contentWidth,
            bucketCount: chart.buckets.count,
            mode: chartMode
        )
        guard chartHover != hover else { return }
        chartHover = hover
    }

    private func tooltip(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(chart.buckets[index].id)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            ForEach(tooltipSeries) { item in
                HStack(spacing: 5) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 6, height: 6)
                    Text(item.tooltipName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(formattedTokenNumber(valueAt(index, in: item)).compact)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }
        }
        .padding(8)
        .frame(width: TokenChartLayout.tooltipWidth)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func valueAt(_ index: Int, in series: TokenChartSeries) -> Double {
        guard series.values.indices.contains(index) else { return 0 }
        return max(series.values[index], 0)
    }

    private func resolvedChartWidth(for visibleWidth: CGFloat) -> CGFloat {
        if chartMode == .bar {
            let step: CGFloat = chart.bucketUnit == "day" ? 14 : 30
            return max(visibleWidth, CGFloat(chart.buckets.count) * step + 50)
        }
        if chart.bucketUnit == "day" {
            return max(visibleWidth, 320)
        }
        let step: CGFloat = 30
        return max(visibleWidth, CGFloat(max(chart.buckets.count - 1, 1)) * step + 110)
    }

    private func modelColor(at index: Int) -> Color {
        let palette: [Color] = [
            .green,
            .orange,
            .purple,
            .pink,
            .teal,
            .red,
            .indigo,
            .mint,
            .brown,
            .cyan,
            .yellow,
        ]
        if index < palette.count {
            return palette[index]
        }

        let hue = Double((index - palette.count) % 24) / 24.0
        let brightness = 0.62 + Double((index / 24) % 3) * 0.12
        return Color(hue: hue, saturation: 0.72, brightness: min(brightness, 0.86))
    }
}

private struct TokenChartContentMinXPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct TokenModelSummary: Identifiable {
    var name: String
    var total: Double
    var color: Color

    var id: String { name }
}

struct TokenChartSeries: Identifiable {
    var name: String
    var tooltipName: String
    var color: Color
    var values: [Double]

    var id: String { name }

    init(name: String, tooltipName: String? = nil, color: Color, values: [Double]) {
        self.name = name
        self.tooltipName = tooltipName ?? name
        self.color = color
        self.values = values
    }
}

enum TokenBarChartModel {
    static func series(
        all: [TokenChartSeries],
        selectedSeriesName: String?,
        totalSeriesName: String
    ) -> [TokenChartSeries] {
        let nonEmpty = all.filter { $0.values.contains(where: { $0 > 0 }) }
        if let selectedSeriesName,
           let selected = nonEmpty.first(where: { $0.name == selectedSeriesName }) {
            return [selected]
        }

        let components = nonEmpty.filter { $0.name != totalSeriesName }
        return components.isEmpty ? nonEmpty.filter { $0.name == totalSeriesName } : components
    }

    static func maximum(for series: [TokenChartSeries]) -> Double {
        let valueCount = series.map(\.values.count).max() ?? 0
        return (0..<valueCount).map { index in
            series.reduce(0) { total, item in
                guard item.values.indices.contains(index) else { return total }
                return total + max(item.values[index], 0)
            }
        }.max() ?? 0
    }

    static func tooltipSeries(
        all: [TokenChartSeries],
        selectedSeriesName: String?
    ) -> [TokenChartSeries] {
        let nonEmpty = all.filter { $0.values.contains(where: { $0 > 0 }) }
        guard let selectedSeriesName else { return nonEmpty }
        return nonEmpty.filter { $0.name == selectedSeriesName }
    }
}

struct TokenMetricView: View {
    var title: String
    var value: Double
    var color: Color
    var isSelected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(formattedTokenNumber(value).number)
                    .font(UB.Font.summaryBig)
                    .tracking(-0.6)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(formattedTokenNumber(value).unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? color.opacity(0.10) : .clear)
        )
    }
}
