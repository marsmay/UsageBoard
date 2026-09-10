import AppKit
import SwiftUI
import UsageBoardCore
import XCTest
@testable import UsageBoardApp

final class ResetCreditsLayoutTests: XCTestCase {
    @MainActor
    func testExpandedDetailsCollapseBackToOneRowInBothLanguages() async throws {
        for language in [AppLanguage.zhHans, .en] {
            var expandedHeights: [CGFloat] = []
            for count in 1...4 {
                let state = ExpansionState()
                let credits = [10, 23, 24, 25].prefix(count).map {
                    PluginResetCredit(id: String($0), expiresAt: Date().addingTimeInterval(Double($0) * 86_400))
                }
                let host = NSHostingView(rootView: CreditsFixture(state: state, credits: credits, language: language))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 336, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                defer { window.contentView = nil }

                try await Task.sleep(for: .milliseconds(100))
                host.layoutSubtreeIfNeeded()
                let collapsedHeight = host.fittingSize.height
                XCTAssertLessThanOrEqual(collapsedHeight, 28)

                state.isExpanded = true
                try await Task.sleep(for: .milliseconds(100))
                host.layoutSubtreeIfNeeded()
                // 单行卡片每行约 34pt（卡片 ~26 + 间距），展开至少多出近一行的高度。
                XCTAssertGreaterThan(host.fittingSize.height, collapsedHeight + 28)
                XCTAssertLessThan(host.fittingSize.height, 180)
                expandedHeights.append(host.fittingSize.height)

                state.isExpanded = false
                try await Task.sleep(for: .milliseconds(100))
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.height, collapsedHeight, accuracy: 1)
            }
            XCTAssertEqual(expandedHeights[0], expandedHeights[1], accuracy: 1)
            XCTAssertEqual(expandedHeights[2], expandedHeights[3], accuracy: 1)
            XCTAssertGreaterThan(expandedHeights[2], expandedHeights[0] + 28)
        }
    }
}

@MainActor
private final class ExpansionState: ObservableObject {
    @Published var isExpanded = false
}

private struct CreditsFixture: View {
    @ObservedObject var state: ExpansionState
    var credits: [PluginResetCredit]
    var language: AppLanguage

    var body: some View {
        ResetCreditsSection(credits: credits, language: language, isExpanded: $state.isExpanded)
            .frame(width: 336)
            .fixedSize(horizontal: false, vertical: true)
    }
}
