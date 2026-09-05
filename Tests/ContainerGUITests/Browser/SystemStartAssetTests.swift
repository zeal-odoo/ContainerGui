import Foundation
import XCTest

@testable import ContainerGUI

final class SystemStartAssetTests: XCTestCase {
    func testSystemStartIsAnExplicitBilingualActionOnHealthCard() throws {
        let html = try asset("index.html")
        let script = try asset("app.js")
        let localization = try asset("i18n.js")
        XCTAssertTrue(html.contains("id=\"startSystemButton\""))
        XCTAssertTrue(html.contains("aria-describedby=\"systemStartHint\" hidden>启动 container</button>"))
        XCTAssertTrue(html.contains("id=\"systemOperationStatus\" class=\"operation-status\" role=\"status\" hidden"))
        XCTAssertTrue(script.contains("elements.startSystemButton.addEventListener(\"click\", startSystem)"))
        XCTAssertTrue(script.contains("systemStart: \"/api/v1/system/start\""))
        XCTAssertTrue(localization.contains("Start container service"))
        XCTAssertTrue(localization.contains("Starting container service…"))
        XCTAssertTrue(localization.contains("stopped containers are not started automatically"))
    }

    private func asset(_ name: String) throws -> String {
        try String(contentsOf: AppFactory.publicDirectoryURL.appendingPathComponent(name), encoding: .utf8)
    }
}
