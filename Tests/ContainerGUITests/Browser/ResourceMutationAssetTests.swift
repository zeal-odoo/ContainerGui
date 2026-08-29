import Foundation
import XCTest

@testable import ContainerGUI

final class ResourceMutationAssetTests: XCTestCase {
    func testImageTablePullDialogAndOperationStatusAreAccessible() throws {
        let html = try asset("index.html")
        let script = try asset("app.js")

        XCTAssertTrue(html.contains("id=\"imagesSection\""))
        XCTAssertTrue(html.contains("id=\"imageTableBody\""))
        XCTAssertTrue(html.contains("id=\"pullImageDialog\""))
        XCTAssertTrue(html.contains("id=\"pullImageForm\""))
        XCTAssertTrue(html.contains("name=\"platform\""))
        XCTAssertTrue(html.contains("aria-live=\"polite\""))
        XCTAssertTrue(script.contains("/api/v1/images"))
        XCTAssertTrue(script.contains("/api/v1/images/pull"))
        XCTAssertTrue(script.contains("loadImages"))
        XCTAssertTrue(script.contains("validateImagePull"))
        XCTAssertTrue(script.contains("pollOperation"))
        XCTAssertTrue(script.contains("Idempotency-Key"))
    }

    func testPullDialogOffersDockerHubAndGHCRRegistryShortcuts() throws {
        let html = try asset("index.html")
        let script = try asset("app.js")

        XCTAssertTrue(html.contains("id=\"pullImageRegistry\""))
        XCTAssertTrue(html.contains("name=\"registry\""))
        XCTAssertTrue(html.contains("<option value=\"dockerHub\">Docker Hub</option>"))
        XCTAssertTrue(html.contains("<option value=\"ghcr\">GitHub Container Registry (GHCR)</option>"))
        XCTAssertTrue(html.contains("目标架构（可选）"))
        XCTAssertTrue(script.contains("resolveImageReference"))
        XCTAssertTrue(script.contains("docker.io/library/"))
        XCTAssertTrue(script.contains("ghcr.io/"))
        XCTAssertTrue(script.contains("body.reference = resolvedReference"))
    }

    func testCreateDialogUsesLocalImagesLoopbackPortsAndSensitiveInputs() throws {
        let html = try asset("index.html")
        let script = try asset("app.js")

        XCTAssertTrue(html.contains("id=\"createContainerDialog\""))
        XCTAssertTrue(html.contains("id=\"createContainerForm\""))
        XCTAssertTrue(html.contains("id=\"localImageOptions\""))
        XCTAssertTrue(html.contains("name=\"cpus\""))
        XCTAssertTrue(html.contains("name=\"memoryMiB\""))
        XCTAssertTrue(html.contains("name=\"ports\""))
        XCTAssertTrue(html.contains("name=\"environment\""))
        XCTAssertTrue(html.contains("data-sensitive=\"true\""))
        XCTAssertTrue(html.contains("name=\"arguments\""))
        XCTAssertTrue(html.contains("name=\"startAfterCreate\""))
        XCTAssertTrue(html.contains("127.0.0.1"))
        XCTAssertTrue(script.contains("createContainer"))
        XCTAssertTrue(script.contains("parsePortLines"))
        XCTAssertTrue(script.contains("parseEnvironmentLines"))
        XCTAssertTrue(script.contains("startAfterCreate"))
        XCTAssertTrue(script.contains("/api/v1/containers"))
    }

    private func asset(_ name: String) throws -> String {
        try String(contentsOf: AppFactory.publicDirectoryURL.appendingPathComponent(name), encoding: .utf8)
    }
}
