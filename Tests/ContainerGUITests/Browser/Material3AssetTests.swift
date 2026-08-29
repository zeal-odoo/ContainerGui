import Foundation
import XCTest

@testable import ContainerGUI

final class Material3AssetTests: XCTestCase {
    func testMaterial3SemanticDesignTokensAreDefined() throws {
        let style = try asset("app.css")
        let requiredTokens = [
            "--md-sys-color-primary",
            "--md-sys-color-on-primary",
            "--md-sys-color-primary-container",
            "--md-sys-color-on-primary-container",
            "--md-sys-color-secondary-container",
            "--md-sys-color-on-secondary-container",
            "--md-sys-color-error",
            "--md-sys-color-error-container",
            "--md-sys-color-surface",
            "--md-sys-color-surface-container-low",
            "--md-sys-color-surface-container-high",
            "--md-sys-color-on-surface",
            "--md-sys-color-on-surface-variant",
            "--md-sys-color-outline",
            "--md-sys-color-outline-variant",
            "--md-sys-typescale-display-large-size",
            "--md-sys-typescale-title-large-size",
            "--md-sys-typescale-body-medium-size",
            "--md-sys-typescale-label-medium-size",
            "--md-sys-shape-corner-medium",
            "--md-sys-shape-corner-extra-large",
            "--md-sys-shape-corner-full",
            "--md-sys-elevation-level-1",
            "--md-sys-elevation-level-3",
        ]

        for token in requiredTokens {
            XCTAssertTrue(style.contains(token), "Missing Material 3 token: \(token)")
        }
    }

    func testMaterial3ComponentsExposeInteractionAndModalStates() throws {
        let style = try asset("app.css")

        XCTAssertTrue(style.contains(".button:hover:not(:disabled)"))
        XCTAssertTrue(style.contains(".button:active:not(:disabled)"))
        XCTAssertTrue(style.contains(".button.secondary"))
        XCTAssertTrue(style.contains(".button.danger"))
        XCTAssertTrue(style.contains(".icon-button:hover:not(:disabled)"))
        XCTAssertTrue(style.contains(".form-field input:focus"))
        XCTAssertTrue(style.contains("[aria-invalid=\"true\"]"))
        XCTAssertTrue(style.contains("dialog::backdrop"))
        XCTAssertTrue(style.contains(".pill.running"))
        XCTAssertTrue(style.contains(".operation-status.error"))
        XCTAssertTrue(style.contains("progress::-webkit-progress-value"))
    }

    func testThemeAdaptiveAndReducedMotionContractsArePresent() throws {
        let style = try asset("app.css")

        XCTAssertTrue(style.contains("@media (prefers-color-scheme: dark)"))
        XCTAssertTrue(style.contains("@media (prefers-reduced-motion: reduce)"))
        XCTAssertTrue(style.contains("@media (max-width: 1200px)"))
        XCTAssertTrue(style.contains("@media (max-width: 900px)"))
        XCTAssertTrue(style.contains("@media (max-width: 600px)"))
        XCTAssertTrue(style.contains("overflow-x: hidden"))
        XCTAssertTrue(style.contains("color-scheme: light"))
        XCTAssertTrue(style.contains("color-scheme: dark"))
    }

    func testRestrainedGlassSurfacesHaveBlurAndOpaqueFallback() throws {
        let style = try asset("app.css")

        XCTAssertTrue(style.contains("--md-sys-glass-blur"))
        XCTAssertTrue(style.contains(".topbar"))
        XCTAssertTrue(style.contains(".detail-panel"))
        XCTAssertTrue(style.contains("dialog"))
        XCTAssertTrue(style.contains("-webkit-backdrop-filter"))
        XCTAssertTrue(style.contains("backdrop-filter"))
        XCTAssertTrue(style.contains("@supports not ((backdrop-filter"))
        XCTAssertTrue(style.contains("@media (prefers-reduced-transparency: reduce)"))
    }

    func testHTMLDeclaresLocalThemeMetadataWithoutRemoteDependencies() throws {
        let html = try asset("index.html")
        let style = try asset("app.css")

        XCTAssertTrue(html.contains("<meta name=\"color-scheme\" content=\"light dark\">"))
        XCTAssertTrue(html.contains("<meta name=\"theme-color\""))
        XCTAssertFalse(html.contains("href=\"https://"))
        XCTAssertFalse(html.contains("href=\"http://"))
        XCTAssertFalse(html.contains("src=\"https://"))
        XCTAssertFalse(html.contains("src=\"http://"))
        XCTAssertFalse(html.localizedCaseInsensitiveContains("fonts.googleapis.com"))
        XCTAssertFalse(html.localizedCaseInsensitiveContains("material-symbols"))
        XCTAssertFalse(style.contains("@import"))
        XCTAssertFalse(style.contains("url(http"))
    }

    func testExistingBehaviorHooksRemainAvailable() throws {
        let html = try asset("index.html")

        for identifier in [
            "appVersionBadge",
            "healthCard",
            "containerRows",
            "detailPanel",
            "toggleImagesButton",
            "createContainerDialog",
            "pullImageDialog",
            "confirmDialog",
        ] {
            XCTAssertTrue(html.contains("id=\"\(identifier)\""), "Missing behavior hook: \(identifier)")
        }
    }

    private func asset(_ name: String) throws -> String {
        try String(
            contentsOf: AppFactory.publicDirectoryURL.appendingPathComponent(name),
            encoding: .utf8
        )
    }
}
