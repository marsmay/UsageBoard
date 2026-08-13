import AppKit
import SwiftUI
import UsageBoardCore

struct TokenBarChartPlot: View {
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
                stackedBars(in: plotRect, hoverIndex: hoverIndex)

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
                        mode: .bar
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
                Text(buckets[index].label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .position(
                        x: xPosition(for: index, in: plotRect),
                        y: TokenChartLayout.xAxisLabelCenterY
                    )
            }
        }
    }

    private func stackedBars(in plotRect: CGRect, hoverIndex: Int?) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(buckets.indices, id: \.self) { index in
                stackedBar(at: index, in: plotRect)
                    .opacity(hoverIndex == nil || hoverIndex == index ? 1 : 0.42)
            }
        }
    }

    private func stackedBar(at index: Int, in plotRect: CGRect) -> some View {
        let values = series.map { valueAt(index, in: $0) }
        let total = values.reduce(0, +)
        let height = yHeight(for: total, in: plotRect)

        return VStack(spacing: 0) {
            ForEach(Array(series.enumerated()), id: \.element.id) { seriesIndex, item in
                Rectangle()
                    .fill(item.color)
                    .frame(height: total > 0 ? height * values[seriesIndex] / total : 0)
            }
        }
        .frame(width: barWidth(in: plotRect), height: height, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: min(3, barWidth(in: plotRect) / 2), style: .continuous))
        .position(x: xPosition(for: index, in: plotRect), y: plotRect.maxY - height / 2)
    }

    private func hoverIndicator(index: Int, in plotRect: CGRect) -> some View {
        let x = xPosition(for: index, in: plotRect)
        let total = series.reduce(0) { $0 + valueAt(index, in: $1) }
        let barHeight = yHeight(for: total, in: plotRect)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: min(4, barWidth(in: plotRect) / 2), style: .continuous)
                .stroke(Color.primary.opacity(0.55), lineWidth: 1)
                .frame(width: barWidth(in: plotRect) + 4, height: barHeight + 4)
                .position(x: x, y: plotRect.maxY - barHeight / 2)
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
        guard !buckets.isEmpty else { return plotRect.midX }
        return plotRect.minX + (CGFloat(index) + 0.5) * plotRect.width / CGFloat(buckets.count)
    }

    private func barWidth(in plotRect: CGRect) -> CGFloat {
        guard !buckets.isEmpty else { return 4 }
        let slotWidth = plotRect.width / CGFloat(buckets.count)
        return max(4, min(18, slotWidth * 0.68))
    }

    private func yHeight(for value: Double, in plotRect: CGRect) -> CGFloat {
        let clamped = max(0, min(value / axisScale.maximum, 1))
        return CGFloat(clamped) * plotRect.height
    }

    private func valueAt(_ index: Int, in series: TokenChartSeries) -> Double {
        guard series.values.indices.contains(index) else { return 0 }
        return max(series.values[index], 0)
    }
}
