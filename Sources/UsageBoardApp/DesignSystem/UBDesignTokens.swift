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
