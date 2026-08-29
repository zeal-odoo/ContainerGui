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
        XCTAssertTrue(html.contains("id=\"imagePullProgress\""))
        XCTAssertTrue(html.contains("id=\"imagePullProgressBar\""))
        XCTAssertTrue(html.contains("<progress"))
        XCTAssertTrue(html.contains("name=\"platform\""))
        XCTAssertTrue(html.contains("aria-live=\"polite\""))
        XCTAssertTrue(script.contains("/api/v1/images"))
        XCTAssertTrue(script.contains("/api/v1/images/pull"))
        XCTAssertTrue(script.contains("loadImages"))
        XCTAssertTrue(script.contains("validateImagePull"))
        XCTAssertTrue(script.contains("pollOperation"))
        XCTAssertTrue(script.contains("renderImagePullProgress"))
        XCTAssertTrue(script.contains("operation.progress"))
        XCTAssertTrue(script.contains("Idempotency-Key"))
    }

    func testLocalImagesCanBeCollapsedAccessibly() throws {
        let html = try asset("index.html")
        let script = try asset("app.js")
        let styles = try asset("app.css")

        XCTAssertTrue(html.contains("id=\"toggleImagesButton\""))
        XCTAssertTrue(html.contains("class=\"image-title-row\""))
        XCTAssertTrue(html.contains("class=\"disclosure-button\""))
        XCTAssertTrue(html.contains("aria-expanded=\"true\""))
        XCTAssertTrue(html.contains("aria-controls=\"imageSectionBody\""))
        XCTAssertTrue(html.contains("aria-label=\"收起本机镜像\""))
        XCTAssertTrue(html.contains("src=\"/icons/chevron-right.svg\""))
        XCTAssertFalse(html.contains(">收起镜像</button>"))
        XCTAssertTrue(html.contains("id=\"imageSectionBody\""))
        let toggle = try functionBody("setImagesExpanded", in: script)
        XCTAssertTrue(toggle.contains("elements.imageSectionBody.hidden = !isExpanded"))
        XCTAssertTrue(toggle.contains("setAttribute(\"aria-expanded\", String(isExpanded))"))
        XCTAssertTrue(toggle.contains("isExpanded ? \"收起本机镜像\" : \"展开本机镜像\""))
        XCTAssertFalse(toggle.contains("textContent"))
        XCTAssertTrue(styles.contains(".disclosure-button[aria-expanded=\"true\"] img"))
        XCTAssertTrue(styles.contains("transform: rotate(90deg)"))
        XCTAssertTrue(script.contains("toggleImagesButton.addEventListener(\"click\""))
        XCTAssertTrue(try functionBody("submitImagePull", in: script).contains("setImagesExpanded(true)"))
        XCTAssertTrue(try functionBody("createContainer", in: script).contains("setImagesExpanded(true)"))
    }

    func testPullDialogOffersFullAddressAndDockerHubWithoutGHCR() throws {
        let html = try asset("index.html")
        let script = try asset("app.js")

        XCTAssertTrue(html.contains("id=\"pullImageRegistry\""))
        XCTAssertTrue(html.contains("name=\"registry\""))
        XCTAssertTrue(html.contains("<option value=\"\">完整地址 / 自动识别</option>"))
        XCTAssertTrue(html.contains("<option value=\"dockerHub\">Docker Hub</option>"))
        XCTAssertFalse(html.contains("GitHub Container Registry"))
        XCTAssertFalse(html.contains("<option value=\"ghcr\""))
        XCTAssertTrue(html.contains("目标架构（可选）"))
        XCTAssertTrue(script.contains("resolveImageReference"))
        XCTAssertTrue(script.contains("docker.io/library/"))
        XCTAssertFalse(script.contains("registry === \"ghcr\""))
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
        XCTAssertTrue(html.contains("主机端口范围为 1024...65535"))
        XCTAssertTrue(html.contains("name=\"environment\""))
        XCTAssertTrue(html.contains("data-sensitive=\"true\""))
        XCTAssertTrue(html.contains("name=\"arguments\""))
        XCTAssertTrue(html.contains("name=\"startAfterCreate\""))
        XCTAssertTrue(html.contains("127.0.0.1"))
        XCTAssertTrue(script.contains("createContainer"))
        XCTAssertTrue(script.contains("parsePortLines"))
        XCTAssertTrue(script.contains("hostPort < 1024"))
        XCTAssertTrue(script.contains("主机端口必须使用 1024...65535；1024 以下需要 root 权限"))
        XCTAssertTrue(script.contains("parseEnvironmentLines"))
        XCTAssertTrue(script.contains("startAfterCreate"))
        XCTAssertTrue(script.contains("/api/v1/containers"))
    }

    func testRemoteRegistrySearchIsExplicitAndKeepsAllLocalImagesVisible() throws {
        let html = try asset("index.html")
        let script = try asset("app.js")

        XCTAssertTrue(html.contains("id=\"remoteRegistrySection\""))
        XCTAssertTrue(html.contains("id=\"remoteRegistryForm\""))
        XCTAssertTrue(html.contains("Docker Hub 搜索关键词"))
        XCTAssertFalse(html.contains("id=\"remoteRegistryProvider\""))
        XCTAssertFalse(html.contains("id=\"dockerHubSearchFields\""))
        XCTAssertFalse(html.contains("id=\"ghcrSearchFields\""))
        XCTAssertFalse(html.contains("id=\"ghcrOwner\""))
        XCTAssertTrue(html.contains("id=\"remoteRepositoryResults\""))
        XCTAssertTrue(html.contains("id=\"remoteTagResults\""))
        XCTAssertTrue(html.contains("id=\"loadMoreRepositoriesButton\""))
        XCTAssertTrue(html.contains("id=\"loadMoreTagsButton\""))
        XCTAssertTrue(script.contains("/api/v1/registry-search/repositories"))
        XCTAssertTrue(script.contains("/api/v1/registry-search/tags"))
        XCTAssertTrue(script.contains("remoteRegistryForm.addEventListener(\"submit\", searchRemoteRepositories)"))
        XCTAssertTrue(script.contains("for (const image of snapshot.items)"))
        XCTAssertFalse(html.contains("id=\"localImagePagination\""))
    }

    func testRemotePaginationDeduplicatesAndExactTagOnlyFillsPullDialog() throws {
        let script = try asset("app.js")

        XCTAssertTrue(script.contains("appendUniqueBy"))
        XCTAssertTrue(script.contains("loadMoreRemoteRepositories"))
        XCTAssertTrue(script.contains("loadMoreRemoteTags"))
        XCTAssertTrue(script.contains("openRemoteRepository"))
        XCTAssertTrue(script.contains("selectRemoteTag"))
        let selection = try functionBody("selectRemoteTag", in: script)
        XCTAssertTrue(selection.contains("elements.pullImageReference.value = tag.reference"))
        XCTAssertTrue(selection.contains("elements.pullImageDialog.showModal()"))
        XCTAssertFalse(selection.contains("ENDPOINTS.imagePull"))
        XCTAssertFalse(selection.contains("submitImagePull"))
    }

    func testRemoteErrorsReplaceLoadingStates() throws {
        let script = try asset("app.js")

        XCTAssertTrue(script.contains("elements.remoteRepositoryStatus.hidden = true;\n    elements.remoteRepositoryError.hidden = false;"))
        XCTAssertTrue(script.contains("elements.remoteTagStatus.hidden = true;\n    elements.remoteTagError.hidden = false;"))
    }

    private func asset(_ name: String) throws -> String {
        try String(contentsOf: AppFactory.publicDirectoryURL.appendingPathComponent(name), encoding: .utf8)
    }

    private func functionBody(_ name: String, in script: String) throws -> String {
        let start = try XCTUnwrap(script.range(of: "function \(name)("))
        let remaining = script[start.lowerBound...]
        let end = remaining.dropFirst().range(of: "\nfunction ")?.lowerBound ?? script.endIndex
        return String(script[start.lowerBound..<end])
    }
}
