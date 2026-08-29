import Foundation
import XCTest

@testable import ContainerGUI

final class ContainerControlAssetTests: XCTestCase {
    func testLegalActionsConfirmationProgressAndLogsArePresent() throws {
        let html = try asset("index.html")
        let script = try asset("app.js")

        XCTAssertTrue(html.contains("id=\"confirmDialog\""))
        XCTAssertTrue(html.contains("id=\"confirmTarget\""))
        XCTAssertTrue(html.contains("最近日志"))
        XCTAssertTrue(html.contains("实时跟随"))
        XCTAssertTrue(script.contains("startContainer"))
        XCTAssertTrue(script.contains("stopContainer"))
        XCTAssertTrue(script.contains("restartContainer"))
        XCTAssertTrue(script.contains("重启容器"))
        XCTAssertTrue(script.contains("确认重启"))
        XCTAssertTrue(script.contains("submitContainerOperation(\"restart\""))
        XCTAssertTrue(script.contains("deleteContainer"))
        XCTAssertTrue(script.contains("删除容器"))
        XCTAssertTrue(script.contains("确认删除"))
        XCTAssertTrue(script.contains("submitContainerOperation(\"delete\""))
        XCTAssertTrue(script.contains("crypto.randomUUID"))
        XCTAssertTrue(script.contains("Idempotency-Key"))
        XCTAssertTrue(script.contains("confirmationTarget"))
        XCTAssertTrue(script.contains("/api/v1/operations/"))
        XCTAssertTrue(script.contains("EventSource"))
        XCTAssertTrue(script.contains("reconnect"))
        XCTAssertTrue(script.contains("operation.state"))
    }

    private func asset(_ name: String) throws -> String {
        try String(contentsOf: AppFactory.publicDirectoryURL.appendingPathComponent(name), encoding: .utf8)
    }
}
