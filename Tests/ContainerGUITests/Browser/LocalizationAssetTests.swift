import Foundation
import XCTest

@testable import ContainerGUI

final class LocalizationAssetTests: XCTestCase {
    func testHeaderExposesChineseAndEnglishLanguageChoices() throws {
        let html = try asset("index.html")

        XCTAssertTrue(html.contains("id=\"languageSwitch\""))
        XCTAssertTrue(html.contains("data-language=\"zh\""))
        XCTAssertTrue(html.contains("data-language=\"en\""))
        XCTAssertTrue(html.contains(">中文</button>"))
        XCTAssertTrue(html.contains(">English</button>"))
    }

    func testLocalizationRuntimeLoadsBeforeApplicationRuntime() throws {
        let html = try asset("index.html")
        let localizationIndex = try XCTUnwrap(html.range(of: "src=\"/i18n.js?v=2.16.0\"")?.lowerBound)
        let applicationIndex = try XCTUnwrap(html.range(of: "src=\"/app.js?v=2.16.0\"")?.lowerBound)

        XCTAssertLessThan(localizationIndex, applicationIndex)
    }

    func testLanguageSwitchUsesMaterialInteractionStates() throws {
        let style = try asset("app.css")

        XCTAssertTrue(style.contains(".language-switch"))
        XCTAssertTrue(style.contains(".language-switch button[aria-pressed=\"true\"]"))
        XCTAssertTrue(style.contains(".language-switch button:focus-visible"))
    }

    private func asset(_ name: String) throws -> String {
        try String(
            contentsOf: AppFactory.publicDirectoryURL.appendingPathComponent(name),
            encoding: .utf8
        )
    }
}
