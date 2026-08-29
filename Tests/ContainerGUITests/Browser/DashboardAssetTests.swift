import Foundation
import XCTest

@testable import ContainerGUI

final class DashboardAssetTests: XCTestCase {
    func testDashboardHasChineseSemanticAndAccessibleStates() throws {
        let html = try asset("index.html")

        XCTAssertTrue(html.contains("lang=\"zh-Hans\""))
        XCTAssertTrue(html.contains("<main"))
        XCTAssertTrue(html.contains("容器概览"))
        XCTAssertTrue(html.contains("手动刷新"))
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
        XCTAssertTrue(script.contains("AbortController"))
        XCTAssertTrue(script.contains("textContent"))
    }

    private func asset(_ name: String) throws -> String {
        let url = AppFactory.publicDirectoryURL.appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
