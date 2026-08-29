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

    func testLocalImagesOfferOnlySafeExactDeleteActions() throws {
        let html = try asset("index.html")
        let script = try asset("app.js")

        XCTAssertTrue(html.contains("<th>操作</th>"))
        XCTAssertTrue(script.contains("imageDelete: \"/api/v1/images/delete\""))
        let render = try functionBody("renderImages", in: script)
        XCTAssertTrue(render.contains("删除镜像"))
        XCTAssertTrue(render.contains("imageDeletionBlockReason"))
        let deletion = try functionBody("deleteImage", in: script)
        XCTAssertTrue(deletion.contains("requestConfirmation"))
        XCTAssertTrue(deletion.contains("image.name"))
        XCTAssertTrue(deletion.contains("不会使用 --all 或 --force"))
        let submission = try functionBody("submitImageDelete", in: script)
        XCTAssertTrue(submission.contains("ENDPOINTS.imageDelete"))
        XCTAssertTrue(submission.contains("confirmationTarget: image.name"))
        XCTAssertTrue(submission.contains("Idempotency-Key"))
        XCTAssertTrue(script.contains("正在使用"))
        XCTAssertTrue(script.contains("系统镜像"))
        let referenceMatch = try functionBody("imageReferenceMatches", in: script)
        XCTAssertTrue(referenceMatch.contains("lastIndexOf(\"@\")"))
        XCTAssertTrue(referenceMatch.contains("image.digest"))
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
        XCTAssertTrue(html.contains("id=\"createCPUs\" name=\"cpus\" type=\"number\" min=\"1\" max=\"1024\" step=\"1\""))
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
        XCTAssertTrue(script.contains("Number.isInteger(cpus)"))
        XCTAssertTrue(script.contains("hostPort < 1024"))
        XCTAssertTrue(script.contains("主机端口必须使用 1024...65535；1024 以下需要 root 权限"))
        XCTAssertTrue(script.contains("parseEnvironmentLines"))
        XCTAssertTrue(script.contains("startAfterCreate"))
        XCTAssertTrue(script.contains("/api/v1/containers"))
    }

    func testCreateDialogOffersGenericAndOdooSpecificDirectoryConfiguration() throws {
        let html = try asset("index.html")
        let script = try asset("app.js")
        let helper = try asset("odoo-create-form.js")

        XCTAssertTrue(html.contains("src=\"/odoo-create-form.js\""))
        XCTAssertTrue(html.contains("id=\"createSharedDirectorySection\""))
        XCTAssertTrue(html.contains("id=\"createSharedDirectoryLabel\""))
        XCTAssertTrue(html.contains("id=\"createSharedHostPath\""))
        XCTAssertTrue(html.contains("id=\"createSharedContainerPath\""))
        XCTAssertTrue(html.contains("value=\"/workspace\""))
        XCTAssertTrue(html.contains("本机与容器之间"))

        XCTAssertTrue(helper.contains("isOfficialOdooImage"))
        XCTAssertTrue(helper.contains("docker.io/library/odoo"))
        XCTAssertTrue(helper.contains("/mnt/extra-addons"))
        XCTAssertTrue(script.contains("updateImageSpecificCreateFields"))
        XCTAssertTrue(script.contains("createImage.addEventListener(\"input\", updateImageSpecificCreateFields)"))
        XCTAssertTrue(script.contains("createImage.addEventListener(\"change\", updateImageSpecificCreateFields)"))

        let builder = try functionBody("buildCreateRequest", in: script)
        XCTAssertTrue(builder.contains("request.sharedDirectory"))
        XCTAssertTrue(builder.contains("hostPath"))
        XCTAssertTrue(builder.contains("containerPath"))
    }

    func testCreateDialogShowsDatabaseEndpointOnlyForOfficialOdooImages() throws {
        let html = try asset("index.html")
        let script = try asset("app.js")

        XCTAssertTrue(html.contains("id=\"createOdooDatabaseFields\""))
        XCTAssertTrue(html.contains("id=\"createOdooDatabaseHost\""))
        XCTAssertTrue(html.contains("value=\"db\""))
        XCTAssertTrue(html.contains("id=\"createOdooDatabasePort\""))
        XCTAssertTrue(html.contains("value=\"5432\""))
        XCTAssertTrue(html.contains("hidden"))

        let updater = try functionBody("updateImageSpecificCreateFields", in: script)
        XCTAssertTrue(updater.contains("elements.createOdooDatabaseFields.hidden = !mode.showDatabase"))
        let builder = try functionBody("buildCreateRequest", in: script)
        XCTAssertTrue(builder.contains("request.odooDatabase"))
        XCTAssertTrue(builder.contains("HOST"))
        XCTAssertTrue(builder.contains("PORT"))
    }

    func testCreateDialogOffersSimpleStructuredSSHConfiguration() throws {
        let html = try asset("index.html")
        let script = try asset("app.js")

        XCTAssertTrue(html.contains("id=\"createSSHEnabled\""))
        XCTAssertTrue(html.contains("启用 SSH（仅公钥登录）"))
        XCTAssertTrue(html.contains("id=\"createSSHFields\""))
        XCTAssertTrue(html.contains("id=\"createSSHHostPort\""))
        XCTAssertTrue(html.contains("value=\"2222\""))
        XCTAssertTrue(html.contains("id=\"createSSHUsername\""))
        XCTAssertTrue(html.contains("value=\"dev\""))
        XCTAssertTrue(html.contains("id=\"createSSHPublicKey\""))
        XCTAssertTrue(html.contains("id=\"createSSHPublicKeyFile\""))
        XCTAssertTrue(html.contains("accept=\".pub,text/plain\""))
        XCTAssertTrue(html.contains("只绑定到 127.0.0.1"))
        XCTAssertTrue(html.contains("密码登录始终禁用"))

        XCTAssertTrue(script.contains("updateSSHFields"))
        XCTAssertTrue(script.contains("readSSHPublicKeyFile"))
        XCTAssertTrue(script.contains("validateSSHPublicKey"))
        let builder = try functionBody("buildCreateRequest", in: script)
        XCTAssertTrue(builder.contains("request.ssh"))
        XCTAssertTrue(builder.contains("hostPort"))
        XCTAssertTrue(builder.contains("username"))
        XCTAssertTrue(builder.contains("publicKey"))
        XCTAssertFalse(builder.contains("entrypoint"))
        XCTAssertFalse(builder.contains("sshd -D"))
    }

    func testCreateDialogOffersExplicitRootPublicKeyMode() throws {
        let html = try asset("index.html")
        let script = try asset("app.js")

        XCTAssertTrue(html.contains("id=\"createSSHLoginAsRoot\""))
        XCTAssertTrue(html.contains("使用 root 登录（仅公钥）"))
        XCTAssertTrue(html.contains("高权限"))
        XCTAssertTrue(html.contains("密码登录保持禁用"))

        let rootUpdater = try functionBody("updateSSHRootMode", in: script)
        XCTAssertTrue(rootUpdater.contains("elements.createSSHLoginAsRoot.checked"))
        XCTAssertTrue(rootUpdater.contains("elements.createSSHUsername.value = \"root\""))
        XCTAssertTrue(rootUpdater.contains("elements.createSSHUsername.disabled = !sshEnabled || loginAsRoot"))

        let builder = try functionBody("buildCreateRequest", in: script)
        XCTAssertTrue(builder.contains("loginAsRoot"))
        XCTAssertTrue(builder.contains("elements.createSSHLoginAsRoot.checked"))
        XCTAssertFalse(builder.localizedCaseInsensitiveContains("rootPassword"))
        XCTAssertFalse(builder.contains("privateKey"))
    }

    func testRootModeIsDefaultOffAndRestoresStandardUsername() throws {
        let html = try asset("index.html")
        let script = try asset("app.js")

        XCTAssertTrue(html.contains("id=\"createSSHLoginAsRoot\" name=\"sshLoginAsRoot\" type=\"checkbox\" disabled"))
        XCTAssertFalse(html.contains("id=\"createSSHLoginAsRoot\" name=\"sshLoginAsRoot\" type=\"checkbox\" checked"))

        let sshUpdater = try functionBody("updateSSHFields", in: script)
        XCTAssertTrue(sshUpdater.contains("if (!enabled) elements.createSSHLoginAsRoot.checked = false"))
        XCTAssertTrue(sshUpdater.contains("elements.createSSHLoginAsRoot.disabled = !enabled"))

        let rootUpdater = try functionBody("updateSSHRootMode", in: script)
        XCTAssertTrue(rootUpdater.contains("dataset.standardUsername"))
        XCTAssertTrue(rootUpdater.contains("elements.createSSHUsername.dataset.standardUsername || \"dev\""))
        XCTAssertTrue(script.contains("createSSHLoginAsRoot.addEventListener(\"change\", updateSSHRootMode)"))
    }

    func testCreateDialogCanGenerateLocalSSHKeyPair() throws {
        let html = try asset("index.html")
        let script = try asset("app.js")
        let keyGenerator = try asset("ssh-key-generator.js")

        XCTAssertTrue(html.contains("src=\"/ssh-key-generator.js\""))
        XCTAssertTrue(html.contains("id=\"generateSSHKeyPairButton\""))
        XCTAssertTrue(html.contains("id=\"generatedSSHKeyStatus\""))
        XCTAssertTrue(html.contains("只下载一次"))
        XCTAssertTrue(keyGenerator.contains("crypto.subtle.generateKey"))
        XCTAssertTrue(keyGenerator.contains("modulusLength: 3072"))
        XCTAssertTrue(keyGenerator.contains("exportKey(\"pkcs8\""))
        XCTAssertTrue(keyGenerator.contains("ssh-rsa"))
        XCTAssertFalse(keyGenerator.contains("fetch("))
        XCTAssertTrue(script.contains("generateAndDownloadSSHKeyPair"))
        XCTAssertTrue(script.contains("ContainerGUIKeyGenerator.generateOpenSSHKeyPair"))
        XCTAssertTrue(script.contains("downloadPrivateKey"))
        XCTAssertTrue(script.contains("elements.createSSHPublicKey.value = publicKey"))
        XCTAssertFalse(try functionBody("buildCreateRequest", in: script).contains("privateKey"))
    }

    func testCreateDialogOffersKeepAlivePresetWithoutRawTyping() throws {
        let html = try asset("index.html")
        let script = try asset("app.js")

        XCTAssertTrue(html.contains("id=\"createKeepAlive\""))
        XCTAssertTrue(html.contains("保持容器运行"))
        XCTAssertTrue(html.contains("/bin/bash -lc"))
        XCTAssertTrue(html.contains("exec sleep infinity"))
        XCTAssertTrue(script.contains("const KEEP_ALIVE_ARGUMENTS = [\"/bin/bash\", \"-lc\", \"exec sleep infinity\"]"))
        let updater = try functionBody("updateProcessModeFields", in: script)
        XCTAssertTrue(updater.contains("elements.createKeepAlive.disabled = sshEnabled"))
        XCTAssertTrue(updater.contains("elements.createArguments.disabled = sshEnabled || keepAlive"))
        let builder = try functionBody("buildCreateRequest", in: script)
        XCTAssertTrue(builder.contains("elements.createKeepAlive.checked"))
        XCTAssertTrue(builder.contains("KEEP_ALIVE_ARGUMENTS"))
    }

    func testContainerDetailShowsDerivedSSHStatusAndCopyableCommand() throws {
        let html = try asset("index.html")
        let script = try asset("app.js")

        XCTAssertTrue(html.contains("id=\"sshConnectionPanel\""))
        XCTAssertTrue(html.contains("id=\"sshStatusLabel\""))
        XCTAssertTrue(html.contains("id=\"sshConnectionCommand\""))
        XCTAssertTrue(html.contains("id=\"copySSHCommandButton\""))
        XCTAssertTrue(html.contains("aria-live=\"polite\""))
        XCTAssertTrue(script.contains("/ssh"))
        XCTAssertTrue(script.contains("loadSSHStatus"))
        XCTAssertTrue(script.contains("renderSSHStatus"))
        XCTAssertTrue(script.contains("初始化中"))
        XCTAssertTrue(script.contains("可连接"))
        XCTAssertTrue(script.contains("navigator.clipboard.writeText"))
        XCTAssertTrue(try functionBody("loadDetail", in: script).contains("loadSSHStatus"))
    }

    func testSSHFormPreventsConflictingAdvancedInputsBeforeSubmission() throws {
        let script = try asset("app.js")

        let toggle = try functionBody("updateSSHFields", in: script)
        XCTAssertTrue(toggle.contains("updateProcessModeFields"))
        XCTAssertTrue(toggle.contains("elements.createStartAfter.checked = true"))
        XCTAssertTrue(toggle.contains("elements.createStartAfter.disabled = true"))

        let builder = try functionBody("buildCreateRequest", in: script)
        XCTAssertTrue(builder.contains("SSH 主机端口不能与其他端口映射重复"))
        XCTAssertTrue(builder.contains("username === \"root\""))
        XCTAssertTrue(builder.contains("CONTAINER_GUI_SSH_USER"))
        XCTAssertTrue(builder.contains("CONTAINER_GUI_SSH_AUTHORIZED_KEY"))
        XCTAssertTrue(builder.contains("request.startAfterCreate = true"))
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
        XCTAssertTrue(selection.contains("openDialog(elements.pullImageDialog, elements.pullImageReference)"))
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
