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

    func testTotalSeriesCanUseTooltipNameWithoutChangingSelectionName() {
        let series = TokenChartSeries(
            name: "Token 总量",
            tooltipName: "总量",
            color: .blue,
            values: [10]
        )

        XCTAssertEqual(series.name, "Token 总量")
        XCTAssertEqual(series.tooltipName, "总量")
    }

    func testUnselectedBarTooltipIncludesTotalAndComponents() {
        let series = [
            makeSeries("total", [10, 20]),
            makeSeries("first", [3, 8]),
            makeSeries("second", [7, 12]),
        ]

        let visible = TokenBarChartModel.tooltipSeries(
            all: series,
            selectedSeriesName: nil
        )

        XCTAssertEqual(visible.map(\.name), ["total", "first", "second"])
    }

    func testSelectedBarTooltipOnlyIncludesSelectedSeries() {
        let series = [
            makeSeries("total", [10, 20]),
            makeSeries("first", [3, 8]),
            makeSeries("second", [7, 12]),
        ]

        let visible = TokenBarChartModel.tooltipSeries(
            all: series,
            selectedSeriesName: "second"
        )

        XCTAssertEqual(visible.map(\.name), ["second"])
    }

    func testTooltipHidesSeriesWhoseCurrentBucketIsZero() {
        let series = [
            makeSeries("total", [10, 20]),
            makeSeries("first", [0, 8]),
            makeSeries("second", [10, 12]),
        ]

        let visible = TokenChartTooltipModel.series(at: 0, from: series)

        XCTAssertEqual(visible.map(\.name), ["total", "second"])
    }

    func testTooltipDoesNotUseValuesFromOtherBuckets() {
        let series = [
            makeSeries("first", [0, 8]),
            makeSeries("second", [10, 0]),
        ]

        XCTAssertEqual(
            TokenChartTooltipModel.series(at: 1, from: series).map(\.name),
            ["first"]
        )
    }

    private func makeSeries(_ name: String, _ values: [Double]) -> TokenChartSeries {
        TokenChartSeries(name: name, color: .blue, values: values)
    }
}
