import Foundation
import XCTest

@testable import ContainerGUI

final class DashboardAssetTests: XCTestCase {
    func testDashboardHasChineseSemanticAndAccessibleStates() throws {
        let html = try asset("index.html")

        XCTAssertTrue(html.contains("lang=\"zh-Hans\""))
        XCTAssertTrue(html.contains("<main"))
        XCTAssertTrue(html.contains("容器概览"))
        XCTAssertFalse(html.contains("手动刷新"))
        XCTAssertFalse(html.contains("id=\"refreshButton\""))
        XCTAssertTrue(html.contains("aria-live=\"polite\""))
        XCTAssertTrue(html.contains("id=\"loadingState\""))
        XCTAssertTrue(html.contains("id=\"emptyState\""))
        XCTAssertTrue(html.contains("id=\"errorState\""))
        XCTAssertTrue(html.contains("<button"))
    }

    func testDashboardScriptUsesVersionedReadAPIAndFiveSecondRefresh() throws {
        let script = try asset("app.js")

        XCTAssertTrue(script.contains("/api/v1/system/health"))
        XCTAssertTrue(script.contains("/api/v1/containers"))
        XCTAssertTrue(script.contains("setInterval"))
        XCTAssertTrue(script.contains("5000"))
        XCTAssertTrue(script.contains("visibilitychange"))
        XCTAssertFalse(script.contains("refreshButton"))
        XCTAssertTrue(script.contains("AbortController"))
        XCTAssertTrue(script.contains("textContent"))
    }

    func testDashboardShowsApplicationVersionFromRootAPI() throws {
        let html = try asset("index.html")
        let script = try asset("app.js")

        XCTAssertTrue(html.contains("id=\"appVersionBadge\""))
        XCTAssertTrue(script.contains("appVersionBadge"))
        XCTAssertTrue(script.contains("appInfo: \"/api/v1\""))
        XCTAssertTrue(script.contains("`GUI v${appInfo.version}`"))
        XCTAssertTrue(script.contains("GUI 版本未知"))
    }

    private func asset(_ name: String) throws -> String {
        let url = AppFactory.publicDirectoryURL.appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
