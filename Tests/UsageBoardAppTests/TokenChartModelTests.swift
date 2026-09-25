import XCTest
import UsageBoardCore
@testable import UsageBoardApp

final class TokenChartModelTests: XCTestCase {
    func testFallbackTotalSeriesAreExcludedFromModelSummaries() {
        // glm 回退序列以本地化总量名（总计/Total）进入 segments，会与总量摘要重复，必须排除。
        let buckets = [
            makeBucket([segment("总计", 100), segment("Total", 100), segment("glm-4.5", 40), segment("glm-5", 60)]),
        ]

        let models = TokenChartModel.aggregatedModels(in: buckets)

        XCTAssertEqual(models.map(\.name), ["glm-5", "glm-4.5"])
        XCTAssertEqual(models.map(\.total), [60, 40])
    }

    func testAggregatesAcrossBucketsAndSortsByTotalThenName() {
        let buckets = [
            makeBucket([segment("a", 10), segment("b", 5)]),
            makeBucket([segment("a", 7), segment("c", 5)]),
        ]

        let models = TokenChartModel.aggregatedModels(in: buckets)

        // a=17 降序第一；b 与 c 同为 5，按名称排序 b 在前。
        XCTAssertEqual(models.map(\.name), ["a", "b", "c"])
        XCTAssertEqual(models.map(\.total), [17, 5, 5])
    }

    func testNegativeTokensDoNotReduceTotals() {
        let buckets = [
            makeBucket([segment("a", 30), segment("a", -10)]),
        ]

        let models = TokenChartModel.aggregatedModels(in: buckets)

        XCTAssertEqual(models.first?.total, 30)
    }

    private func segment(_ model: String, _ tokens: Double) -> PluginChartSegment {
        PluginChartSegment(model: model, tokens: tokens)
    }

    private func makeBucket(_ segments: [PluginChartSegment]) -> PluginChartBucket {
        PluginChartBucket(id: "2026-09-25", label: "09-25", segments: segments)
    }
}
