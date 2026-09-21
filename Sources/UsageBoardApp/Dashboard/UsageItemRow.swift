import SwiftUI
import UsageBoardCore

struct UsageItemRow: View {
    var item: UsageItem
    var language: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            Text(item.name)
                .font(.system(size: 12))
                .foregroundStyle(UB.Text.supporting)
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
                .foregroundStyle(UB.Text.supporting)
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

struct ResetCreditsSection: View {
    var credits: [PluginResetCredit]
    var language: AppLanguage
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var strings: AppLocalization { AppLocalization(language: language) }
    private var sortedCredits: [PluginResetCredit] {
        credits.sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "ticket")
                        .accessibilityHidden(true)
                    Text("\(strings.text(.resetCards)) ×\(credits.count)")
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    if let credit = sortedCredits.first, credit.expiresAt != nil {
                        Text(strings.resetCardsSummary(remaining: credit.remainingText(language: language)))
                            .foregroundStyle(credit.urgency().foregroundColor(in: colorScheme))
                            .monospacedDigit()
                    }
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 10)
                        .accessibilityHidden(true)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minHeight: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(strings.resetCardsAction(isExpanded: isExpanded))
            .accessibilityValue(strings.disclosureState(isExpanded: isExpanded))

            if isExpanded {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                    ForEach(sortedCredits) { credit in
                        ResetCreditCard(credit: credit, language: language)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

struct ResetCreditCard: View {
    var credit: PluginResetCredit
    var language: AppLanguage
    @Environment(\.colorScheme) private var colorScheme

    private var urgency: PluginResetCredit.ResetCreditUrgency { credit.urgency() }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(urgency.accentColor)
                .frame(width: 5, height: 5)
            if let title = credit.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(credit.remainingText(language: language))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(urgency.foregroundColor(in: colorScheme))
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 2)
            Text(credit.compactExpiryText())
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [urgency.accentColor.opacity(0.14), urgency.accentColor.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(urgency.accentColor.opacity(0.28), lineWidth: 0.5)
        )
        .help(credit.lineText(language: language))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(credit.lineText(language: language))
    }
}

private extension PluginResetCredit.ResetCreditUrgency {
    /// 装饰色（圆点 / 渐变底 / 描边）：可用卡也给绿色点缀，避免整组灰底。
    var accentColor: Color {
        switch self {
        case .fresh: return .green
        case .approaching: return .orange
        case .soon: return .red
        case .expired, .unknown: return .gray
        }
    }

    func foregroundColor(in scheme: ColorScheme) -> Color {
        switch self {
        case .fresh, .expired, .unknown: return .secondary
        case .approaching: return scheme == .dark ? .orange : Color(red: 0.58, green: 0.30, blue: 0.02)
        case .soon: return scheme == .dark ? .red : Color(red: 0.70, green: 0.13, blue: 0.10)
        }
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
