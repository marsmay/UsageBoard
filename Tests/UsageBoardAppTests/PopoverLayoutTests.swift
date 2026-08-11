import XCTest
@testable import UsageBoardApp

final class PopoverLayoutTests: XCTestCase {
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
