import AppKit
import SwiftUI
import UsageBoardCore

struct TokenLineChartPlot: View {
    var buckets: [PluginChartBucket]
    var series: [TokenChartSeries]
    var maxValue: Double
    var hoverIndex: Int?
    var onHover: (TokenChartHover?) -> Void

    private var axisScale: TokenChartAxisScale {
        TokenChartAxisScale(dataMaximum: maxValue)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let chartFrame = proxy.frame(in: .named("TokenChartViewport"))
            let plotRect = CGRect(
                x: TokenChartLayout.leadingAxisWidth,
                y: TokenChartLayout.topPadding,
                width: max(
                    size.width - TokenChartLayout.leadingAxisWidth - TokenChartLayout.trailingPadding,
                    1
                ),
                height: max(
                    size.height - TokenChartLayout.topPadding - TokenChartLayout.bottomHeight,
                    1
                )
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))

                gridLines(in: plotRect)
                xAxisLabels(in: plotRect)
                lineSeries(in: plotRect)

                if let hoverIndex, buckets.indices.contains(hoverIndex) {
                    hoverIndicator(index: hoverIndex, in: plotRect)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    onHover(TokenChartHoverModel.hover(
                        at: location,
                        in: plotRect,
                        chartMinX: chartFrame.minX,
                        bucketCount: buckets.count,
                        mode: .line
                    ))
                case .ended:
                    onHover(nil)
                }
            }
        }
    }

    private func gridLines(in plotRect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...axisScale.tickCount, id: \.self) { index in
                let y = plotRect.minY + CGFloat(index) / CGFloat(axisScale.tickCount) * plotRect.height
                Path { path in
                    path.move(to: CGPoint(x: plotRect.minX, y: y))
                    path.addLine(to: CGPoint(x: plotRect.maxX, y: y))
                }
                .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 0.6)
            }
        }
    }

    private func xAxisLabels(in plotRect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(xTickIndices, id: \.self) { index in
                let x = xPosition(for: index, in: plotRect)
                Text(buckets[index].label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .position(x: x, y: TokenChartLayout.xAxisLabelCenterY)
            }
        }
    }

    private func lineSeries(in plotRect: CGRect) -> some View {
        ZStack {
            ForEach(series) { item in
                Path { path in
                    guard !item.values.isEmpty else { return }
                    path.move(to: CGPoint(x: xPosition(for: 0, in: plotRect), y: plotRect.maxY))
                    for index in item.values.indices {
                        path.addLine(to: CGPoint(
                            x: xPosition(for: index, in: plotRect),
                            y: yPosition(for: item.values[index], in: plotRect)
                        ))
                    }
                    path.addLine(to: CGPoint(x: xPosition(for: item.values.count - 1, in: plotRect), y: plotRect.maxY))
                    path.closeSubpath()
                }
                .fill(item.color.opacity(0.06))

                Path { path in
                    for index in item.values.indices {
                        let point = CGPoint(
                            x: xPosition(for: index, in: plotRect),
                            y: yPosition(for: item.values[index], in: plotRect)
                        )
                        if index == item.values.startIndex {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                }
                .stroke(item.color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func hoverIndicator(index: Int, in plotRect: CGRect) -> some View {
        let x = xPosition(for: index, in: plotRect)
        // 未选中时首条可见线即总量线；选中时只剩目标线，圆点跟随其数值与颜色
        let markerValue = series.first.map { valueAt(index, in: $0) } ?? buckets[index].total
        let markerColor = series.first?.color ?? .blue

        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: x, y: plotRect.minY))
                path.addLine(to: CGPoint(x: x, y: plotRect.maxY))
            }
            .stroke(Color.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            Circle()
                .strokeBorder(.white, lineWidth: 2)
                .background(Circle().fill(markerColor))
                .frame(width: 8, height: 8)
                .position(x: x, y: yPosition(for: markerValue, in: plotRect))
        }
    }

    private var xTickIndices: [Int] {
        guard buckets.count > 1 else { return buckets.indices.map { $0 } }
        let desiredTicks = min(5, buckets.count)
        let step = max(1, Int(ceil(Double(buckets.count - 1) / Double(desiredTicks - 1))))
        var indices = Array(stride(from: 0, to: buckets.count, by: step))
        if indices.last != buckets.count - 1 {
            indices.append(buckets.count - 1)
        }
        return indices
    }

    private func xPosition(for index: Int, in plotRect: CGRect) -> CGFloat {
        guard buckets.count > 1 else { return plotRect.midX }
        return plotRect.minX + CGFloat(index) / CGFloat(buckets.count - 1) * plotRect.width
    }

    private func yPosition(for value: Double, in plotRect: CGRect) -> CGFloat {
        let clamped = max(0, min(value / axisScale.maximum, 1))
        return plotRect.maxY - CGFloat(clamped) * plotRect.height
    }

    private func valueAt(_ index: Int, in series: TokenChartSeries) -> Double {
        guard series.values.indices.contains(index) else { return 0 }
        return series.values[index]
    }
}

enum TokenChartLayout {
    static let leadingAxisWidth: CGFloat = 40
    static let trailingPadding: CGFloat = 20
    static let topPadding: CGFloat = 12
    static let bottomHeight: CGFloat = 26
    static let height: CGFloat = 170
    static let plotHeight: CGFloat = height - topPadding - bottomHeight
    static let plotBottomY: CGFloat = topPadding + plotHeight
    static let xAxisLabelCenterY: CGFloat = plotBottomY + 15
    static let tooltipWidth: CGFloat = 178
    static let tooltipMargin: CGFloat = 8
    static let tooltipGap: CGFloat = 12
    static let tooltipOffsetY: CGFloat = -tooltipMargin

    static func tooltipOriginX(anchorX: CGFloat, visibleWidth: CGFloat) -> CGFloat {
        let rightOrigin = anchorX + tooltipGap
        if rightOrigin + tooltipWidth <= visibleWidth - tooltipMargin {
            return rightOrigin
        }

        let leftOrigin = anchorX - tooltipGap - tooltipWidth
        if leftOrigin >= tooltipMargin {
            return leftOrigin
        }

        return min(
            max(rightOrigin, tooltipMargin),
            max(visibleWidth - tooltipMargin - tooltipWidth, tooltipMargin)
        )
    }
}

struct TokenChartYAxis: View {
    var maxValue: Double
    var viewportWidth: CGFloat

    private var axisScale: TokenChartAxisScale {
        TokenChartAxisScale(dataMaximum: maxValue)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(nsColor: .textBackgroundColor))
                .frame(
                    width: TokenChartLayout.leadingAxisWidth,
                    height: TokenChartLayout.plotBottomY
                )

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.35))
                .frame(width: 0.5, height: TokenChartLayout.plotHeight)
                .offset(
                    x: TokenChartLayout.leadingAxisWidth - 0.5,
                    y: TokenChartLayout.topPadding
                )

            ForEach(0...axisScale.tickCount, id: \.self) { index in
                let value = axisScale.step * Double(axisScale.tickCount - index)
                let y = TokenChartLayout.topPadding
                    + CGFloat(index) / CGFloat(axisScale.tickCount) * TokenChartLayout.plotHeight
                Text(formattedAxisTokenNumber(value))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .frame(width: TokenChartLayout.leadingAxisWidth - 8, alignment: .trailing)
                    .position(x: (TokenChartLayout.leadingAxisWidth - 8) / 2, y: y)
            }
        }
        .frame(width: viewportWidth, height: TokenChartLayout.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

enum TokenChartHoverModel {
    static func hover(
        at location: CGPoint,
        in plotRect: CGRect,
        chartMinX: CGFloat,
        bucketCount: Int,
        mode: ChartMode
    ) -> TokenChartHover? {
        guard bucketCount > 0 else { return nil }
        guard plotRect.contains(location) else { return nil }
        guard chartMinX + location.x >= TokenChartLayout.leadingAxisWidth else { return nil }

        let index: Int
        switch mode {
        case .line:
            if bucketCount == 1 {
                index = 0
            } else {
                let ratio = min(max((location.x - plotRect.minX) / plotRect.width, 0), 1)
                index = min(
                    max(Int((ratio * CGFloat(bucketCount - 1)).rounded()), 0),
                    bucketCount - 1
                )
            }
        case .bar:
            let slotWidth = plotRect.width / CGFloat(bucketCount)
            index = min(
                max(Int((location.x - plotRect.minX) / slotWidth), 0),
                bucketCount - 1
            )
        }

        let anchorContentX: CGFloat
        switch mode {
        case .line:
            anchorContentX = bucketCount == 1
                ? plotRect.midX
                : plotRect.minX + CGFloat(index) / CGFloat(bucketCount - 1) * plotRect.width
        case .bar:
            anchorContentX = plotRect.minX
                + (CGFloat(index) + 0.5) * plotRect.width / CGFloat(bucketCount)
        }
        return TokenChartHover(index: index, anchorX: chartMinX + anchorContentX)
    }
}

struct TokenChartHover: Equatable {
    var index: Int
    var anchorX: CGFloat
}

struct TokenChartAxisScale: Equatable {
    var maximum: Double
    var step: Double
    var tickCount: Int

    init(dataMaximum: Double, maximumTickCount: Int = 5) {
        let resolvedMaximum = max(dataMaximum, 0)
        let resolvedMaximumTickCount = max(maximumTickCount, 1)
        var selectedMaximum = Double.greatestFiniteMagnitude
        var selectedStep = 50.0
        var selectedTickCount = 1

        for tickCount in 1...resolvedMaximumTickCount {
            let rawStep = resolvedMaximum / Double(tickCount)
            let step = Self.niceStep(ceiling: rawStep)
            let maximum = step * Double(tickCount)
            if maximum < selectedMaximum
                || (maximum == selectedMaximum && tickCount > selectedTickCount) {
                selectedMaximum = maximum
                selectedStep = step
                selectedTickCount = tickCount
            }
        }

        self.maximum = selectedMaximum
        self.step = selectedStep
        self.tickCount = selectedTickCount
    }

    private static func niceStep(ceiling value: Double) -> Double {
        let resolvedValue = max(value, 50)
        let magnitude = pow(10, floor(log10(resolvedValue)))
        let normalized = resolvedValue / magnitude
        let factor: Double
        if normalized <= 1 {
            factor = 1
        } else if normalized <= 2 {
            factor = 2
        } else if normalized <= 5 {
            factor = 5
        } else {
            factor = 10
        }
        return factor * magnitude
    }
}

func formattedTokenNumber(_ value: Double) -> (number: String, unit: String, compact: String) {
    if value >= 1_000_000_000 {
        let number = String(format: "%.2f", value / 1_000_000_000)
        return (number, "B", "\(number)B")
    }
    if value >= 1_000_000 {
        let number = String(format: "%.2f", value / 1_000_000)
        return (number, "M", "\(number)M")
    }
    if value >= 1_000 {
        let number = String(format: "%.2f", value / 1_000)
        return (number, "K", "\(number)K")
    }
    if value.rounded() == value {
        let number = String(Int(value))
        return (number, "", number)
    }
    let number = String(format: "%.2f", value)
    return (number, "", number)
}

func formattedAxisTokenNumber(_ value: Double) -> String {
    if value >= 1_000_000_000 {
        return "\(formattedAxisNumber(value / 1_000_000_000))B"
    }
    if value >= 1_000_000 {
        return "\(formattedAxisNumber(value / 1_000_000))M"
    }
    if value >= 1_000 {
        return "\(formattedAxisNumber(value / 1_000))K"
    }
    return "\(Int(value.rounded()))"
}

private func formattedAxisNumber(_ value: Double) -> String {
    if abs(value.rounded() - value) < 0.000_001 {
        return String(Int(value.rounded()))
    }
    return String(format: "%.1f", value)
}
