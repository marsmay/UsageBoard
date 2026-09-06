import AppKit
import SwiftUI
import UsageBoardCore
import XCTest
@testable import UsageBoardApp

final class PopoverLayoutTests: XCTestCase {
    @MainActor
    func testTabsShrinkAfterTallerContentAndRespectHeightLimit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usageboard-layout-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtures = [2, 12, 40].map { count in
            PluginConfiguration(stateID: String(count), name: "Demo \(count)", executablePath: root.appendingPathComponent("demo.py").path)
        }
        let config = ConfigStore(fileURL: root.appendingPathComponent("config.json"))
        try config.save(AppConfiguration(plugins: fixtures))
        let store = UsageBoardStore(configStore: config, stateStore: LayoutStates())
        let plugins = store.configuration.plugins
        defer {
            for plugin in plugins {
                store.setPluginEnabled(id: plugin.id, enabled: false)
            }
        }
        let host = NSHostingView(rootView: OverviewView(store: store, maximumHeight: 600).frame(width: PopoverLayout.width))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }

        var heights: [CGFloat] = []
        for index in [0, 1, 0, 2, 0] {
            store.selectedTabID = plugins[index].id
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.frame.height, host.fittingSize.height, accuracy: 1,
                           "The window must shrink to the selected tab's content height")
            heights.append(host.fittingSize.height)
        }
        XCTAssertLessThan(heights[0], 300)
        XCTAssertGreaterThan(heights[1], heights[0] + 100)
        XCTAssertEqual(heights[2], heights[0], accuracy: 1)
        XCTAssertEqual(heights[3], 600, accuracy: 1)
        XCTAssertEqual(heights[4], heights[0], accuracy: 1)
    }

    func testMaximumHeightUsesSeventyFivePercentOfVisibleScreen() {
        XCTAssertEqual(PopoverLayout.maximumHeight(for: 900), 675)
    }

    func testDashboardHeightUsesRemainingPopoverBudget() {
        XCTAssertEqual(
            PopoverLayout.dashboardMaximumHeight(popoverMaximumHeight: 675, headerHeight: 45),
            630
        )
    }

    func testHeightBudgetsDoNotBecomeNegative() {
        XCTAssertEqual(PopoverLayout.maximumHeight(for: -1), 0)
        XCTAssertEqual(
            PopoverLayout.dashboardMaximumHeight(popoverMaximumHeight: 40, headerHeight: 45),
            0
        )
    }
}

private struct LayoutStates: PluginStateStoring {
    func load(stateID: String) -> PluginCachedState? {
        PluginCachedState(updatedAt: Date(), items: (0..<(Int(stateID) ?? 0)).map {
            .init(id: String($0), name: "Usage \($0)", used: 25, limit: 100, displayStyle: .percent, color: "blue")
        })
    }
    func save(stateID: String, state: PluginCachedState) throws {}
    func needsRefresh(stateID: String, intervalSeconds: Int) -> Bool { false }
}
