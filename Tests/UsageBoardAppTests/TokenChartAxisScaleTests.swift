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
}
