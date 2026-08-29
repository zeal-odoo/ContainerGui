import Foundation
import XCTest

@testable import ContainerGUI

final class Material3MotionAssetTests: XCTestCase {
    func testMotionSchemeDefinesSpatialAndEffectTokens() throws {
        let style = try asset("app.css")

        for token in [
            "--md-sys-motion-duration-dialog-enter",
            "--md-sys-motion-duration-dialog-exit",
            "--md-sys-motion-duration-pane-enter",
            "--md-sys-motion-easing-emphasized-decelerate",
            "--md-sys-motion-easing-emphasized-accelerate",
        ] {
            XCTAssertTrue(style.contains(token), "Missing Material motion token: \(token)")
        }
    }

    func testDialogsAnimateOpenCloseAndBackdrop() throws {
        let style = try asset("app.css")
        let script = try asset("app.js")

        XCTAssertTrue(style.contains("dialog[open]:not(.is-closing)"))
        XCTAssertTrue(style.contains("dialog[open].is-closing"))
        XCTAssertTrue(style.contains("@keyframes md-dialog-enter"))
        XCTAssertTrue(style.contains("@keyframes md-dialog-exit"))
        XCTAssertTrue(style.contains("@keyframes md-scrim-enter"))
        XCTAssertTrue(style.contains("@keyframes md-scrim-exit"))
        XCTAssertTrue(script.contains("function openDialog("))
        XCTAssertTrue(script.contains("function closeDialog("))
        XCTAssertTrue(script.contains("dialog.classList.add(\"is-closing\")"))
        XCTAssertTrue(script.contains("prefers-reduced-motion: reduce"))
        XCTAssertTrue(script.contains("event.key !== \"Escape\""))
    }

    func testButtonRevealedSurfacesUseProgressiveMotion() throws {
        let style = try asset("app.css")
        let script = try asset("app.js")

        XCTAssertTrue(style.contains("#detailContent.is-revealing"))
        XCTAssertTrue(style.contains("#detailContent.is-closing"))
        XCTAssertTrue(style.contains("#imageSectionBody.is-collapsed"))
        XCTAssertTrue(style.contains(".toast.is-hiding"))
        XCTAssertTrue(style.contains("scale(.96)"))
        XCTAssertTrue(script.contains("function revealDetailContent("))
        XCTAssertTrue(script.contains("function setImagesExpanded("))
        XCTAssertTrue(script.contains("function showToast("))
    }

    private func asset(_ name: String) throws -> String {
        try String(
            contentsOf: AppFactory.publicDirectoryURL.appendingPathComponent(name),
            encoding: .utf8
        )
    }
}
