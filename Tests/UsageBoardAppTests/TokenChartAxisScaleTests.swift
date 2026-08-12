import XCTest
@testable import UsageBoardApp

final class TokenChartAxisScaleTests: XCTestCase {
    func testScaleUsesFiftyStepForSmallValues() {
        let scale = TokenChartAxisScale(dataMaximum: 120)

        XCTAssertEqual(scale.step, 50)
        XCTAssertEqual(scale.maximum, 150)
        XCTAssertEqual(scale.tickCount, 3)
    }

    func testScaleAddsTicksToReduceTopPadding() {
        let scale = TokenChartAxisScale(dataMaximum: 230)

        XCTAssertEqual(scale.step, 50)
        XCTAssertEqual(scale.maximum, 250)
        XCTAssertEqual(scale.tickCount, 5)
    }

    func testScaleUsesHundredMultipleAtLargerMagnitudes() {
        let scale = TokenChartAxisScale(dataMaximum: 1_200)

        XCTAssertEqual(scale.step, 500)
        XCTAssertEqual(scale.maximum, 1_500)
        XCTAssertEqual(scale.tickCount, 3)
        XCTAssertEqual(scale.step.truncatingRemainder(dividingBy: 100), 0)
    }

    func testScaleLimitsGridDensity() {
        let scale = TokenChartAxisScale(dataMaximum: 999)

        XCTAssertEqual(scale.step, 200)
        XCTAssertEqual(scale.maximum, 1_000)
        XCTAssertEqual(scale.tickCount, 5)
    }

    func testScaleRejectsArbitraryRawHundredMultiples() {
        let scale = TokenChartAxisScale(dataMaximum: 12_345_678)

        XCTAssertEqual(scale.step, 5_000_000)
        XCTAssertEqual(scale.maximum, 15_000_000)
        XCTAssertEqual(scale.tickCount, 3)
    }

    func testAxisFormattingPreservesUsefulDecimalWithoutWrappingText() {
        XCTAssertEqual(formattedAxisTokenNumber(50_000), "50K")
        XCTAssertEqual(formattedAxisTokenNumber(1_500_000), "1.5M")
        XCTAssertEqual(formattedAxisTokenNumber(2_000_000_000), "2B")
    }

    func testTooltipPrefersRightSideOfHoveredPoint() {
        XCTAssertEqual(TokenChartLayout.tooltipOriginX(anchorX: 100, visibleWidth: 700), 112)
    }

    func testTooltipMovesLeftNearViewportTrailingEdge() {
        XCTAssertEqual(TokenChartLayout.tooltipOriginX(anchorX: 650, visibleWidth: 700), 460)
    }

    func testTooltipCanExtendBeyondChartWithoutMovingItsLayout() {
        XCTAssertEqual(TokenChartLayout.tooltipOffsetY, -8)
    }

    func testLineHoverUsesViewportLocationAndScrollOffset() throws {
        let hover = try XCTUnwrap(TokenChartHoverModel.hover(
            at: CGPoint(x: 130, y: 80),
            contentMinX: -100,
            contentWidth: 400,
            bucketCount: 5,
            mode: .line
        ))

        XCTAssertEqual(hover.index, 2)
        XCTAssertEqual(hover.anchorX, 110)
    }

    func testBarHoverUsesBucketSlotsAfterHorizontalScroll() throws {
        let hover = try XCTUnwrap(TokenChartHoverModel.hover(
            at: CGPoint(x: 130, y: 80),
            contentMinX: -100,
            contentWidth: 400,
            bucketCount: 10,
            mode: .bar
        ))

        XCTAssertEqual(hover.index, 5)
        XCTAssertEqual(hover.anchorX, 127)
    }

    func testHoverIgnoresAxisAndLabelsOutsidePlot() {
        XCTAssertNil(TokenChartHoverModel.hover(
            at: CGPoint(x: 20, y: 80),
            contentMinX: 0,
            contentWidth: 400,
            bucketCount: 5,
            mode: .line
        ))
        XCTAssertNil(TokenChartHoverModel.hover(
            at: CGPoint(x: 100, y: 160),
            contentMinX: 0,
            contentWidth: 400,
            bucketCount: 5,
            mode: .line
        ))
    }
}
