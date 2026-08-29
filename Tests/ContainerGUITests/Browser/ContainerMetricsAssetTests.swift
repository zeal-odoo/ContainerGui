import Foundation
import XCTest

@testable import ContainerGUI

final class ContainerMetricsAssetTests: XCTestCase {
    func testDashboardHasAccessibleCPUAndMemoryColumns() throws {
        let html = try asset("index.html")

        XCTAssertTrue(html.contains("<th scope=\"col\">CPU</th>"))
        XCTAssertTrue(html.contains("<th scope=\"col\">内存</th>"))
    }

    func testScriptRefreshesMetricsIndependentlyAndRendersSafeStates() throws {
        let script = try asset("app.js")

        XCTAssertTrue(script.contains("metrics: \"/api/v1/containers/metrics\""))
        XCTAssertTrue(script.contains("metricsByID"))
        XCTAssertTrue(script.contains("metricsResult"))
        XCTAssertTrue(script.contains("formatPercent"))
        XCTAssertTrue(script.contains("formatBytes"))
        XCTAssertTrue(script.contains("采样中"))
        XCTAssertTrue(script.contains("未运行"))
        XCTAssertTrue(script.contains("暂不可用"))
        XCTAssertTrue(script.contains("Promise.allSettled"))
        XCTAssertTrue(script.contains("5000"))
    }

    func testCPUPercentageUsesTheContainersTotalAllocatedCapacity() throws {
        let script = try asset("app.js")

        XCTAssertTrue(script.contains("normalizeCPUPercent(metric.cpuPercent, cpuCount)"))
        XCTAssertTrue(script.contains("detail: `100% = ${cpuCount} 核`"))
        XCTAssertFalse(script.contains("detail: \"100% = 1 核\""))
    }

    func testMetricPresentationHasPrimaryAndSecondaryText() throws {
        let style = try asset("app.css")

        XCTAssertTrue(style.contains(".metric-value"))
        XCTAssertTrue(style.contains(".metric-detail"))
        XCTAssertTrue(style.contains("@media (max-width: 1200px)"))
    }

    func testAutomaticRefreshDoesNotCancelAndPileUpActiveReads() throws {
        let script = try asset("app.js")

        XCTAssertTrue(script.contains("if (state.refreshing) return;"))
        XCTAssertFalse(script.contains("if (state.refreshing) state.refreshController?.abort();"))
    }

    private func asset(_ name: String) throws -> String {
        let url = AppFactory.publicDirectoryURL.appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
