import SwiftUI
import UsageBoardCore

struct UsageItemRow: View {
    var item: UsageItem
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            Text(item.name)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 92, alignment: .leading)

            UsageProgressBar(value: item.progress, label: item.displayValue(), color: item.color)
                .frame(height: 18)
                .layoutPriority(1)

            Text(item.resetText(language: language))
                .font(.system(size: 11))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.tertiary)
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

struct UsageProgressBar: View {
    var value: Double
    var label: String
    var color: String?

    var body: some View {
        GeometryReader { proxy in
            let ratio = max(0, min(value, 1))
            let width = ratio * proxy.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: UB.Radius.bar, style: .continuous)
                    .fill(resolvedColor.opacity(0.16))
                RoundedRectangle(cornerRadius: UB.Radius.bar, style: .continuous)
                    .fill(resolvedColor)
                    .frame(width: width)
                valueLabel
                    .foregroundStyle(Color.primary)
                valueLabel
                    .foregroundStyle(fillTextColor)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: width)
                    }
            }
        }
        .frame(minWidth: 80, idealHeight: 18, maxHeight: 18)
        .clipShape(RoundedRectangle(cornerRadius: UB.Radius.bar, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var valueLabel: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var fillTextColor: Color {
        [Color.yellow, .orange, .green].contains(resolvedColor) ? .black : .white
    }

    private var resolvedColor: Color {
        if let override = color?.lowercased(), let c = mapOverride(override) {
            return c
        }
        let pct = value * 100
        if pct >= 100 { return .red }
        if pct >= 80 { return .orange }
        if pct >= 60 { return .yellow }
        return .blue
    }

    private func mapOverride(_ name: String) -> Color? {
        switch name {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        default: return nil
        }
    }
}
