import AppKit
import SwiftUI
import UsageBoardCore

struct TokenLineChartPlot: View {
    var buckets: [PluginChartBucket]
    var series: [TokenChartSeries]
    var maxValue: Double
    var visibleWidth: CGFloat
    @State private var hoverLocation: CGPoint?

    private let leadingWidth: CGFloat = 30
    private let trailingPadding: CGFloat = 20
    private let topPadding: CGFloat = 12
    private let bottomHeight: CGFloat = 26
    private let yTickCount = 3

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let chartFrame = proxy.frame(in: .named("TokenChartScroll"))
            let plotRect = CGRect(
                x: leadingWidth,
                y: topPadding,
                width: max(size.width - leadingWidth - trailingPadding, 1),
                height: max(size.height - topPadding - bottomHeight, 1)
            )
            let hoverIndex = nearestBucketIndex(in: plotRect)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))

                grid(in: plotRect)
                xAxisLabels(in: plotRect)
                lineSeries(in: plotRect)

                if let hoverIndex {
                    hoverOverlay(index: hoverIndex, in: plotRect, size: size, chartMinX: chartFrame.minX)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverLocation = location
                case .ended:
                    hoverLocation = nil
                }
            }
        }
    }

    private func grid(in plotRect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...yTickCount, id: \.self) { index in
                let value = maxValue * Double(yTickCount - index) / Double(yTickCount)
                let y = plotRect.minY + CGFloat(index) / CGFloat(yTickCount) * plotRect.height
                Path { path in
                    path.move(to: CGPoint(x: plotRect.minX, y: y))
                    path.addLine(to: CGPoint(x: plotRect.maxX, y: y))
                }
                .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 0.6)

                Text(formattedAxisTokenNumber(value))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: leadingWidth - 4, alignment: .trailing)
                    .position(x: (leadingWidth - 4) / 2, y: y)
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
                    .position(x: x, y: plotRect.maxY + 15)
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

    private func hoverOverlay(index: Int, in plotRect: CGRect, size: CGSize, chartMinX: CGFloat) -> some View {
        let x = xPosition(for: index, in: plotRect)
        let rows = series.map { ($0.id, $0.tooltipName, $0.color, valueAt(index, in: $0)) }
        let tooltipWidth: CGFloat = 178
        let tooltipMargin: CGFloat = 8
        let tooltipGap: CGFloat = 12
        let rightCenter = x + tooltipWidth / 2 + tooltipGap
        let leftCenter = x - tooltipWidth / 2 - tooltipGap
        let rightVisibleMax = chartMinX + rightCenter + tooltipWidth / 2
        let leftVisibleMin = chartMinX + leftCenter - tooltipWidth / 2
        let tooltipX: CGFloat
        if rightVisibleMax <= visibleWidth - tooltipMargin {
            tooltipX = rightCenter
        } else if leftVisibleMin >= tooltipMargin {
            tooltipX = leftCenter
        } else {
            let minCenter = tooltipMargin - chartMinX + tooltipWidth / 2
            let maxCenter = visibleWidth - tooltipMargin - chartMinX - tooltipWidth / 2
            tooltipX = min(max(rightCenter, minCenter), maxCenter)
        }

        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: x, y: plotRect.minY))
                path.addLine(to: CGPoint(x: x, y: plotRect.maxY))
            }
            .stroke(Color.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            Circle()
                .strokeBorder(.white, lineWidth: 2)
                .background(Circle().fill(.blue))
                .frame(width: 8, height: 8)
                .position(x: x, y: yPosition(for: buckets[index].total, in: plotRect))

            VStack(alignment: .leading, spacing: 6) {
                Text(buckets[index].id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                ForEach(rows, id: \.0) { row in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(row.2)
                            .frame(width: 6, height: 6)
                        Text(row.1)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(formattedTokenNumber(row.3).compact)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(8)
            .frame(width: tooltipWidth)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
            .position(x: tooltipX, y: plotRect.minY + 72)
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
        let clamped = max(0, min(value / maxValue, 1))
        return plotRect.maxY - CGFloat(clamped) * plotRect.height
    }

    private func nearestBucketIndex(in plotRect: CGRect) -> Int? {
        guard let hoverLocation, plotRect.contains(hoverLocation), !buckets.isEmpty else { return nil }
        guard buckets.count > 1 else { return 0 }
        let ratio = min(max((hoverLocation.x - plotRect.minX) / plotRect.width, 0), 1)
        return min(max(Int((ratio * CGFloat(buckets.count - 1)).rounded()), 0), buckets.count - 1)
    }

    private func valueAt(_ index: Int, in series: TokenChartSeries) -> Double {
        guard series.values.indices.contains(index) else { return 0 }
        return series.values[index]
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
        return "\(Int((value / 1_000_000_000).rounded()))B"
    }
    if value >= 1_000_000 {
        return "\(Int((value / 1_000_000).rounded()))M"
    }
    if value >= 1_000 {
        return "\(Int((value / 1_000).rounded()))K"
    }
    return "\(Int(value.rounded()))"
}
