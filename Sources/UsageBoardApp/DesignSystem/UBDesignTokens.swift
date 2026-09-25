import SwiftUI

enum UB {
    enum Radius {
        static let card: CGFloat = 10
        static let bar: CGFloat = 5
    }

    enum Font {
        static let cardTitle = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let popoverTitle = SwiftUI.Font.system(size: 13.5, weight: .semibold)
        static let detailTitle = SwiftUI.Font.system(size: 15, weight: .bold)
        static let formLabel = SwiftUI.Font.system(size: 12.5)
        static let countdown = SwiftUI.Font.system(size: 11, design: .default)
            .monospacedDigit()
        static let summaryBig = SwiftUI.Font.system(size: 18, weight: .bold)
            .monospacedDigit()
        // 语义字号 token：新代码优先使用，既有硬编码在触碰对应文件时渐进迁移。
        static let body = SwiftUI.Font.system(size: 13)
        static let label = SwiftUI.Font.system(size: 12)
        static let caption = SwiftUI.Font.system(size: 11)
        static let caption2 = SwiftUI.Font.system(size: 10)
        static let metricTitle = SwiftUI.Font.system(size: 11.5)
    }

    enum Canvas {
        static let canvasBackground = Color(nsColor: .windowBackgroundColor)
        static let cardBackground = Color(nsColor: .textBackgroundColor)
        static let separator = Color(nsColor: .separatorColor)
    }

    enum Text {
        // 数据标签和时间需要在两种主题下保持可读，避免层级文字色过度淡化。
        static let supporting = Color.primary.opacity(0.75)
    }
}

/// 主操作胶囊（强调色填充白字）：关于页检查更新、更新提示立即更新共用。
struct UBPrimaryCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(UB.Font.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1)))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}

/// 次操作胶囊（描边）：更新提示稍后更新等。
struct UBSecondaryCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(UB.Font.body.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(
                Capsule().strokeBorder(
                    Color.primary.opacity(configuration.isPressed ? 0.45 : 0.25),
                    lineWidth: 1
                )
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}
