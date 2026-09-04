import Foundation
import XCTest

@testable import ContainerGUI

final class UpdateReminderAssetTests: XCTestCase {
    func testHeaderAndDialogExposeManualAndAutomaticUpdateFlow() throws {
        let html = try asset("index.html")

        XCTAssertTrue(html.contains("id=\"checkUpdatesButton\""))
        XCTAssertTrue(html.contains("id=\"updateDialog\""))
        XCTAssertTrue(html.contains("id=\"updateCurrentVersion\""))
        XCTAssertTrue(html.contains("id=\"updateLatestVersion\""))
        XCTAssertTrue(html.contains("id=\"updateReleaseLink\""))
        XCTAssertTrue(html.contains("target=\"_blank\""))
        XCTAssertTrue(html.contains("rel=\"noopener noreferrer\""))
        XCTAssertTrue(html.contains("src=\"/update-check.js?v=\(AppVersion.current)\""))
        XCTAssertTrue(html.contains("检查更新"))
        XCTAssertTrue(html.contains("前往 GitHub 下载 PKG"))
    }

    func testApplicationUsesThrottleDeduplicationAndExplicitNavigationOnly() throws {
        let script = try asset("app.js")
        let helper = try asset("update-check.js")

        XCTAssertTrue(script.contains("updateCheck: \"/api/v1/update-check\""))
        XCTAssertTrue(script.contains("async function checkForUpdates({ automatic = false } = {})"))
        XCTAssertTrue(script.contains("state.updateChecking"))
        XCTAssertTrue(script.contains("shouldRunAutomaticCheck"))
        XCTAssertTrue(script.contains("recordAutomaticCheck"))
        XCTAssertTrue(script.contains("elements.checkUpdatesButton.addEventListener(\"click\""))
        XCTAssertTrue(script.contains("checkForUpdates({ automatic: true })"))
        XCTAssertFalse(script.contains("window.location ="))
        XCTAssertFalse(script.contains("location.href ="))
        XCTAssertTrue(helper.contains("const AUTO_UPDATE_CHECK_INTERVAL_MS = 24 * 60 * 60 * 1000"))
        XCTAssertTrue(helper.contains("function validatedReleaseURL"))
        XCTAssertTrue(helper.contains("github.com"))
        XCTAssertTrue(helper.contains("/zeal-odoo/ContainerGui/releases/"))
    }

    func testUpdateFlowHasMaterialMotionReducedMotionAndBilingualCopy() throws {
        let style = try asset("app.css")
        let localization = try asset("i18n.js")

        XCTAssertTrue(style.contains(".update-check-button"))
        XCTAssertTrue(style.contains(".update-version-grid"))
        XCTAssertTrue(style.contains("dialog[open]:not(.is-closing)"))
        XCTAssertTrue(style.contains("prefers-reduced-motion: reduce"))
        for copy in [
            "检查更新", "正在检查更新…", "发现新版本", "当前已是最新版本",
            "暂时无法检查更新，请稍后重试。", "前往 GitHub 下载 PKG",
            "Check for updates", "Checking for updates…", "Update available",
            "Container GUI is up to date", "Open GitHub to download the PKG",
        ] {
            XCTAssertTrue(localization.contains(copy), "Missing localized update copy: \(copy)")
        }
    }

    private func asset(_ name: String) throws -> String {
        try String(
            contentsOf: AppFactory.publicDirectoryURL.appendingPathComponent(name),
            encoding: .utf8
        )
    }
}
