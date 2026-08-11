import SwiftUI
import XCTest
@testable import UsageBoardApp

final class TokenBarChartModelTests: XCTestCase {
    func testUnselectedBarUsesComponentsInLegendOrderWithoutDuplicatingTotal() {
        let series = [
            makeSeries("total", [10, 20]),
            makeSeries("first", [3, 8]),
            makeSeries("second", [7, 12]),
        ]

        let visible = TokenBarChartModel.series(
            all: series,
            selectedSeriesName: nil,
            totalSeriesName: "total"
        )

        XCTAssertEqual(visible.map(\.name), ["first", "second"])
    }

    func testSelectedBarUsesOnlySelectedSeries() {
        let series = [
            makeSeries("total", [10, 20]),
            makeSeries("first", [3, 8]),
            makeSeries("second", [7, 12]),
        ]

        let visible = TokenBarChartModel.series(
            all: series,
            selectedSeriesName: "second",
            totalSeriesName: "total"
        )

        XCTAssertEqual(visible.map(\.name), ["second"])
        XCTAssertEqual(visible.first?.values, [7, 12])
    }

    func testBarMaximumUsesStackedBucketTotal() {
        let series = [
            makeSeries("first", [3, 8]),
            makeSeries("second", [7, 12]),
        ]

        XCTAssertEqual(TokenBarChartModel.maximum(for: series), 20)
    }

    func testBarFallsBackToTotalWhenThereAreNoComponentSeries() {
        let total = makeSeries("total", [10, 20])

        let visible = TokenBarChartModel.series(
            all: [total],
            selectedSeriesName: nil,
            totalSeriesName: "total"
        )

        XCTAssertEqual(visible.map(\.name), ["total"])
    }

    func testSeriesCanUseShortTooltipNameWithoutChangingSelectionName() {
        let series = TokenChartSeries(
            name: "glm-4.5 用量",
            tooltipName: "glm-4.5",
            color: .blue,
            values: [10]
        )

        XCTAssertEqual(series.name, "glm-4.5 用量")
        XCTAssertEqual(series.tooltipName, "glm-4.5")
    }

    private func makeSeries(_ name: String, _ values: [Double]) -> TokenChartSeries {
        TokenChartSeries(name: name, color: .blue, values: values)
    }
}
