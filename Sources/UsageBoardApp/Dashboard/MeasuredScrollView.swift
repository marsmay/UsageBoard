import SwiftUI

struct MeasuredScrollView<Content: View>: View {
    var maxHeight: CGFloat
    var minHeight: CGFloat = 100
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    private var resolvedMaximumHeight: CGFloat {
        max(maxHeight, 0)
    }

    private var resolvedMinimumHeight: CGFloat {
        min(minHeight, resolvedMaximumHeight)
    }

    var body: some View {
        ScrollView {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .frame(
            height: contentHeight > 0
                ? min(max(contentHeight, resolvedMinimumHeight), resolvedMaximumHeight)
                : resolvedMinimumHeight
        )
        .onPreferenceChange(ContentHeightKey.self) { height in
            if height > 0, abs(contentHeight - height) > 1 {
                contentHeight = height
            }
        }
    }
}

struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
