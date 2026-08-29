import Foundation
import XCTest

@testable import ContainerGUI

final class ImageAndCreationCLITests: XCTestCase {
    private let observedAt = Date(timeIntervalSince1970: 1_787_987_200)

    func testImagePullRequestValidatesReferenceAndPlatform() throws {
        let request = ImagePullRequest(
            reference: "registry.example:5000/team/demo:1",
            platform: "linux/arm64"
        )

        XCTAssertEqual(try request.validated(), request)

        assertValidationError(
            try ImagePullRequest(reference: "-bad image", platform: "darwin/arm64").validated(),
            fields: ["platform", "reference"]
        )
    }

    func testContainerCreateRequestValidatesFieldsAndRedactsEnvironmentValues() throws {
        let secret = "do-not-echo-this-secret"
        let request = ContainerCreateRequest(
            name: "demo-postgres",
            image: "postgres:latest",
            cpus: 2,
            memoryMiB: 2048,
            ports: [PortMapping(hostPort: 15432, containerPort: 5432)],
            environment: [EnvironmentEntry(name: "POSTGRES_PASSWORD", value: secret)],
            arguments: ["postgres", "-c", "shared_buffers=256MB"],
            startAfterCreate: true
        )

        XCTAssertEqual(try request.validated(), request)
        let encodedSummary = String(
            decoding: try JSONEncoder.containerGUI.encode(JSONValue.object(request.safeRequestSummary)),
            as: UTF8.self
        )
        XCTAssertTrue(encodedSummary.contains("POSTGRES_PASSWORD"))
        XCTAssertEqual(
            request.safeRequestSummary["ports"],
            .array([.string("127.0.0.1:15432:5432/tcp")])
        )
        XCTAssertFalse(encodedSummary.contains(secret))

        let invalid = ContainerCreateRequest(
            name: "-bad name",
            image: "bad image",
            cpus: 0,
            memoryMiB: 0,
            ports: [
                PortMapping(hostPort: 8080, containerPort: 80),
                PortMapping(hostPort: 8080, containerPort: 81),
            ],
            environment: [
                EnvironmentEntry(name: "1BAD", value: "first"),
                EnvironmentEntry(name: "1BAD", value: "second"),
            ],
            arguments: ["contains\0nul"]
        )
        assertValidationError(
            try invalid.validated(),
            fields: ["arguments", "cpus", "environment", "image", "memoryMiB", "name", "ports"]
        )
    }

    func testContainerCreateRejectsPrivilegedHostPort() throws {
        let request = ContainerCreateRequest(
            name: "ubuntu-test",
            image: "ubuntu:26.04",
            ports: [PortMapping(hostPort: 100, containerPort: 22)]
        )

        XCTAssertThrowsError(try request.validated()) { error in
            guard let problem = error as? ProblemDetail else {
                return XCTFail("Expected ProblemDetail")
            }
            XCTAssertEqual(problem.code, .validationFailed)
            XCTAssertEqual(
                problem.fieldErrors,
                [FieldError(field: "ports", message: "主机端口必须使用 1024...65535；1024 以下需要 root 权限")]
            )
        }
    }

    func testContainerCreateRejectsFractionalCPUCount() throws {
        let request = ContainerCreateRequest(
            name: "ubuntu-test",
            image: "ubuntu:26.04",
            cpus: 2.5
        )

        XCTAssertThrowsError(try request.validated()) { error in
            guard let problem = error as? ProblemDetail else {
                return XCTFail("Expected ProblemDetail")
            }
            XCTAssertEqual(problem.code, .validationFailed)
            XCTAssertEqual(
                problem.fieldErrors,
                [FieldError(field: "cpus", message: "CPU 必须为 1...1024 的整数")]
            )
        }
    }

    func testContainerCreateDecodesOptionalDirectoryAndOdooDatabaseWithoutLeakingValues() throws {
        let oldBody = Data(#"{"name":"legacy","image":"ubuntu:26.04"}"#.utf8)
        let legacy = try JSONDecoder.containerGUI.decode(ContainerCreateRequest.self, from: oldBody)
        XCTAssertNil(legacy.sharedDirectory)
        XCTAssertNil(legacy.odooDatabase)

        let hostPath = "/private/tmp/container-gui-sensitive-addons"
        let request = ContainerCreateRequest(
            name: "odoo-test",
            image: "docker.io/library/odoo:19.0",
            sharedDirectory: SharedDirectoryConfiguration(
                hostPath: hostPath,
                containerPath: "/mnt/extra-addons"
            ),
            odooDatabase: OdooDatabaseConfiguration(host: "db.internal", port: 55_432)
        )
        let encoded = try JSONEncoder.containerGUI.encode(request)
        let decoded = try JSONDecoder.containerGUI.decode(ContainerCreateRequest.self, from: encoded)
        XCTAssertEqual(decoded, request)

        let summary = String(
            decoding: try JSONEncoder.containerGUI.encode(JSONValue.object(request.safeRequestSummary)),
            as: UTF8.self
        )
        XCTAssertEqual(
            request.safeRequestSummary["sharedDirectory"]?.objectValue?["containerPath"],
            .string("/mnt/extra-addons")
        )
        XCTAssertEqual(request.safeRequestSummary["odooDatabaseConfigured"], .bool(true))
        XCTAssertFalse(summary.contains(hostPath))
        XCTAssertFalse(summary.contains("db.internal"))
        XCTAssertFalse(summary.contains("55432"))
    }

    func testSharedDirectoryValidationRequiresSafeExistingDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("container-gui-mount-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = ContainerCreateRequest(
            name: "generic",
            image: "ubuntu:26.04",
            sharedDirectory: SharedDirectoryConfiguration(
                hostPath: directory.path,
                containerPath: "/workspace"
            )
        )
        XCTAssertEqual(try valid.validated(), valid)

        let missing = ContainerCreateRequest(
            name: "missing",
            image: "ubuntu:26.04",
            sharedDirectory: SharedDirectoryConfiguration(
                hostPath: directory.appendingPathComponent("absent").path,
                containerPath: "/workspace"
            )
        )
        assertValidationError(try missing.validated(), fields: ["sharedDirectory.hostPath"])

        let unsafe = ContainerCreateRequest(
            name: "unsafe",
            image: "ubuntu:26.04",
            sharedDirectory: SharedDirectoryConfiguration(
                hostPath: "/",
                containerPath: "../workspace"
            )
        )
        assertValidationError(
            try unsafe.validated(),
            fields: ["sharedDirectory.containerPath", "sharedDirectory.hostPath"]
        )
    }

    func testOfficialOdooClassificationIsExactAndRequiresAddonsTarget() throws {
        for reference in [
            "odoo",
            "odoo:19.0",
            "odoo@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "docker.io/library/odoo:19.0-20260817",
        ] {
            XCTAssertTrue(ContainerCreateRequest.isOfficialOdooImageReference(reference), reference)
        }
        for reference in [
            "owner/odoo:19.0",
            "ghcr.io/example/odoo:19.0",
            "docker.io/library/my-odoo:19.0",
            "odoo-helper:latest",
        ] {
            XCTAssertFalse(ContainerCreateRequest.isOfficialOdooImageReference(reference), reference)
        }

        let directory = FileManager.default.temporaryDirectory
        let wrongTarget = ContainerCreateRequest(
            name: "odoo-wrong-target",
            image: "docker.io/library/odoo:19.0",
            sharedDirectory: SharedDirectoryConfiguration(
                hostPath: directory.path,
                containerPath: "/workspace"
            )
        )
        assertValidationError(
            try wrongTarget.validated(),
            fields: ["sharedDirectory.containerPath"]
        )
    }

    func testOdooDatabaseValidationRejectsInvalidNonOdooAndEnvironmentConflicts() throws {
        let invalidEndpoint = ContainerCreateRequest(
            name: "odoo-invalid-db",
            image: "odoo:19.0",
            odooDatabase: OdooDatabaseConfiguration(host: "https://db host/path", port: 0)
        )
        assertValidationError(
            try invalidEndpoint.validated(),
            fields: ["odooDatabase.host", "odooDatabase.port"]
        )

        let nonOdoo = ContainerCreateRequest(
            name: "ubuntu-db",
            image: "ubuntu:26.04",
            odooDatabase: OdooDatabaseConfiguration(host: "db", port: 5432)
        )
        assertValidationError(try nonOdoo.validated(), fields: ["odooDatabase"])

        let conflict = ContainerCreateRequest(
            name: "odoo-conflict",
            image: "odoo:19.0",
            environment: [EnvironmentEntry(name: "HOST", value: "other")],
            odooDatabase: OdooDatabaseConfiguration(host: "db", port: 5432)
        )
        assertValidationError(try conflict.validated(), fields: ["environment"])
    }

    func testParsesImageListAndInspectFixtures() throws {
        let list = try CLIOutputParser.parseImageList(
            data: fixture("images-list.json"),
            observedAt: observedAt
        )
        let inspected = try CLIOutputParser.parseImageInspect(
            data: fixture("image-inspect.json"),
            observedAt: observedAt
        )

        XCTAssertEqual(list.items.map(\.name), [
            "docker.io/library/postgres:latest",
            "example.invalid/demo:1",
        ])
        XCTAssertEqual(list.items[0].platforms, [ImagePlatform(os: "linux", architecture: "arm64", variant: "v8")])
        XCTAssertEqual(list.items[0].sizeBytes, 166_985_592)
        XCTAssertEqual(inspected.name, "docker.io/library/postgres:latest")
        XCTAssertEqual(inspected.platforms.map(\.identifier), ["linux/arm64/v8", "linux/amd64"])
        XCTAssertEqual(inspected.observedAt, observedAt)
    }

    func testParsesPlainImagePullProgressIntoOverallPercentage() throws {
        let fetching = try XCTUnwrap(CLIOutputParser.parseImagePullProgress(
            line: "[1/2] Fetching image 37% (19 of 31 blobs, 6.9/18.2 MB, 4.3 MB/s) [5s]",
            observedAt: observedAt
        ))
        let unpacking = try XCTUnwrap(CLIOutputParser.parseImagePullProgress(
            line: "[2/2] Unpacking image for platform linux/arm64/v8 0% [8s]",
            observedAt: observedAt
        ))
        let completed = try XCTUnwrap(CLIOutputParser.parseImagePullProgress(
            line: "[2/2] Unpacking image for platform linux/arm64/v8 100% (440 entries, 3.9 MB) [11s]",
            observedAt: observedAt
        ))

        XCTAssertEqual(fetching.phase, .fetching)
        XCTAssertEqual(fetching.percentComplete, 19)
        XCTAssertEqual(fetching.completedUnits, 19)
        XCTAssertEqual(fetching.totalUnits, 31)
        XCTAssertEqual(unpacking.phase, .unpacking)
        XCTAssertEqual(unpacking.percentComplete, 50)
        XCTAssertEqual(completed.percentComplete, 100)
        XCTAssertNil(CLIOutputParser.parseImagePullProgress(line: "unrelated output"))
    }

    func testPullUsesFixedArgumentsLongTimeoutAndInspectReadback() async throws {
        let progressOutput = """
        [1/2] Fetching image 37% (19 of 31 blobs, 6.9/18.2 MB, 4.3 MB/s) [5s]
        [2/2] Unpacking image for platform linux/arm64/v8 0% [8s]
        [2/2] Unpacking image for platform linux/arm64/v8 100% (440 entries, 3.9 MB) [11s]
        """
        let executor = ResourceScriptedCommandExecutor(steps: [
            .success(resourceVersionResult()),
            .success(CommandResult(
                stdout: Data(),
                stderr: Data(progressOutput.utf8),
                exitCode: 0,
                duration: .zero
            )),
            .success(CommandResult(
                stdout: try fixture("image-inspect.json"),
                stderr: Data(),
                exitCode: 0,
                duration: .zero
            )),
        ])
        let client = resourceClient(executor)
        let progress = ImagePullProgressRecorder()

        let outcome = try await client.pullImage(
            ImagePullRequest(reference: "postgres:latest", platform: "linux/arm64"),
            progress: { update in await progress.append(update) }
        )

        XCTAssertTrue(outcome.matchedExpectation)
        XCTAssertEqual(outcome.observedImage.name, "docker.io/library/postgres:latest")
        let requests = await executor.requests
        XCTAssertEqual(requests[1].arguments, [
            "image", "pull", "--progress", "plain", "--platform", "linux/arm64", "postgres:latest",
        ])
        XCTAssertEqual(requests[1].timeout, .seconds(30 * 60))
        XCTAssertEqual(requests[2].arguments, ["image", "inspect", "postgres:latest"])
        let updates = await progress.values
        XCTAssertEqual(updates.map(\.percentComplete), [19, 50, 100])
    }

    func testDeleteImageUsesExactReferenceWithoutBroadFlagsAndRequiresAbsenceReadback() async throws {
        let executor = ResourceScriptedCommandExecutor(steps: [
            .success(resourceVersionResult()),
            .success(CommandResult(
                stdout: try fixture("images-list.json"),
                stderr: Data(),
                exitCode: 0,
                duration: .zero
            )),
            .success(resourceContainerListResult()),
            .success(resourceEmptySuccess()),
            .success(CommandResult(stdout: Data("[]".utf8), stderr: Data(), exitCode: 0, duration: .zero)),
        ])

        let outcome = try await resourceClient(executor).deleteImage(reference: "example.invalid/demo:1")

        XCTAssertEqual(outcome.exitCode, 0)
        XCTAssertTrue(outcome.targetAbsent)
        let requests = await executor.requests
        let mutation = try XCTUnwrap(requests.first(where: { $0.arguments.prefix(2) == ["image", "delete"] }))
        XCTAssertEqual(mutation.arguments, ["image", "delete", "example.invalid/demo:1"])
        XCTAssertFalse(mutation.arguments.contains("--all"))
        XCTAssertFalse(mutation.arguments.contains("--force"))
    }

    func testDeleteImageRejectsContainerReferenceBeforeMutation() async throws {
        let executor = ResourceScriptedCommandExecutor(steps: [
            .success(resourceVersionResult()),
            .success(CommandResult(
                stdout: try fixture("images-list.json"),
                stderr: Data(),
                exitCode: 0,
                duration: .zero
            )),
            .success(resourceContainerListResult(
                id: "demo",
                state: "stopped",
                imageReference: "postgres:latest"
            )),
        ])

        do {
            _ = try await resourceClient(executor).deleteImage(reference: "docker.io/library/postgres:latest")
            XCTFail("Expected state conflict")
        } catch let problem as ProblemDetail {
            XCTAssertEqual(problem.code, .stateConflict)
        }

        let requests = await executor.requests
        XCTAssertFalse(requests.contains(where: { $0.arguments.prefix(2) == ["image", "delete"] }))
    }

    func testDeleteImageRejectsContainerDigestReferenceBeforeMutation() async throws {
        let digest = "sha256:" + String(repeating: "a", count: 64)
        let executor = ResourceScriptedCommandExecutor(steps: [
            .success(resourceVersionResult()),
            .success(CommandResult(
                stdout: try fixture("images-list.json"),
                stderr: Data(),
                exitCode: 0,
                duration: .zero
            )),
            .success(resourceContainerListResult(
                id: "demo",
                imageReference: "docker.io/library/postgres@\(digest)"
            )),
        ])

        do {
            _ = try await resourceClient(executor).deleteImage(reference: "docker.io/library/postgres:latest")
            XCTFail("Expected state conflict")
        } catch let problem as ProblemDetail {
            XCTAssertEqual(problem.code, .stateConflict)
        }

        let requests = await executor.requests
        XCTAssertFalse(requests.contains(where: { $0.arguments.prefix(2) == ["image", "delete"] }))
    }

    func testDeleteImageRejectsAppleSystemImageBeforeMutation() async throws {
        let executor = ResourceScriptedCommandExecutor(steps: [
            .success(resourceVersionResult()),
            .success(resourceImageListResult(reference: "ghcr.io/apple/containerization/vminit:0.33.3")),
        ])

        do {
            _ = try await resourceClient(executor).deleteImage(
                reference: "ghcr.io/apple/containerization/vminit:0.33.3"
            )
            XCTFail("Expected state conflict")
        } catch let problem as ProblemDetail {
            XCTAssertEqual(problem.code, .stateConflict)
        }

        let requests = await executor.requests
        XCTAssertFalse(requests.contains(where: { $0.arguments.prefix(2) == ["image", "delete"] }))
    }

    func testDeleteImageExitZeroWithoutAbsenceReadbackIsNotSuccess() async throws {
        let list = CommandResult(
            stdout: try fixture("images-list.json"),
            stderr: Data(),
            exitCode: 0,
            duration: .zero
        )
        let executor = ResourceScriptedCommandExecutor(steps: [
            .success(resourceVersionResult()),
            .success(list),
            .success(resourceContainerListResult()),
            .success(resourceEmptySuccess()),
            .success(list),
        ])

        let outcome = try await resourceClient(executor).deleteImage(reference: "example.invalid/demo:1")

        XCTAssertEqual(outcome.exitCode, 0)
        XCTAssertFalse(outcome.targetAbsent)
    }

    func testCreateUsesOnlyFixedOptionsBeforeImageAndReadsBackTarget() async throws {
        let executor = ResourceScriptedCommandExecutor(steps: [
            .success(resourceVersionResult()),
            .success(resourceEmptySuccess()),
            .success(resourceContainerListResult(id: "demo", state: "created")),
        ])
        let request = ContainerCreateRequest(
            name: "demo",
            image: "postgres:latest",
            cpus: 2,
            memoryMiB: 2048,
            ports: [
                PortMapping(hostPort: 15432, containerPort: 5432),
                PortMapping(hostPort: 15353, containerPort: 53, protocolName: "udp"),
            ],
            environment: [EnvironmentEntry(name: "POSTGRES_PASSWORD", value: "secret-value")],
            arguments: ["postgres", "-c", "shared_buffers=256MB"]
        )

        let outcome = try await resourceClient(executor).createContainer(request)

        XCTAssertTrue(outcome.matchedExpectation)
        XCTAssertEqual(outcome.observedContainer?.state, .created)
        let requests = await executor.requests
        XCTAssertEqual(requests[1].arguments, [
            "create", "--name", "demo",
            "--cpus", "2",
            "--memory", "2048M",
            "--publish", "127.0.0.1:15432:5432/tcp",
            "--publish", "127.0.0.1:15353:53/udp",
            "--env", "POSTGRES_PASSWORD=secret-value",
            "--", "postgres:latest", "postgres", "-c", "shared_buffers=256MB",
        ])
        XCTAssertEqual(requests[1].timeout, .seconds(30))
        XCTAssertEqual(requests[2].arguments, ["list", "--all", "--format", "json"])
    }

    func testCreateAddsOneBindMountAndOdooDatabaseEnvironmentBeforeImage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("container-gui-odoo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executor = ResourceScriptedCommandExecutor(steps: [
            .success(resourceVersionResult()),
            .success(resourceEmptySuccess()),
            .success(resourceContainerListResult(
                id: "odoo-demo",
                state: "created",
                imageReference: "docker.io/library/odoo:19.0"
            )),
        ])
        let request = ContainerCreateRequest(
            name: "odoo-demo",
            image: "docker.io/library/odoo:19.0",
            environment: [EnvironmentEntry(name: "USER", value: "odoo")],
            sharedDirectory: SharedDirectoryConfiguration(
                hostPath: directory.path,
                containerPath: "/mnt/extra-addons"
            ),
            odooDatabase: OdooDatabaseConfiguration(host: "postgres-odoo-apple", port: 15432)
        )

        let outcome = try await resourceClient(executor).createContainer(request)

        XCTAssertTrue(outcome.matchedExpectation)
        let requests = await executor.requests
        XCTAssertEqual(requests[1].arguments, [
            "create", "--name", "odoo-demo",
            "--mount", "type=bind,source=\(directory.path),target=/mnt/extra-addons",
            "--env", "HOST=postgres-odoo-apple",
            "--env", "PORT=15432",
            "--env", "USER=odoo",
            "--", "docker.io/library/odoo:19.0",
        ])
    }

    func testCreateOptionallyStartsOnlyAfterCreatedReadback() async throws {
        let executor = ResourceScriptedCommandExecutor(steps: [
            .success(resourceVersionResult()),
            .success(resourceEmptySuccess()),
            .success(resourceContainerListResult(id: "demo", state: "created")),
            .success(resourceEmptySuccess()),
            .success(resourceContainerListResult(id: "demo", state: "running")),
        ])
        let request = ContainerCreateRequest(
            name: "demo",
            image: "postgres:latest",
            startAfterCreate: true
        )

        let outcome = try await resourceClient(executor).createContainer(request)

        XCTAssertTrue(outcome.matchedExpectation)
        XCTAssertEqual(outcome.observedContainer?.state, .running)
        let requests = await executor.requests
        XCTAssertEqual(requests[1].arguments, ["create", "--name", "demo", "--", "postgres:latest"])
        XCTAssertEqual(requests[2].arguments, ["list", "--all", "--format", "json"])
        XCTAssertEqual(requests[3].arguments, ["start", "demo"])
        XCTAssertEqual(requests[4].arguments, ["list", "--all", "--format", "json"])
    }

    func testSSHCreateUsesOnlyFixedBootstrapArgumentsAndStartsAfterReadback() async throws {
        let publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhY fixture@example"
        let executor = ResourceScriptedCommandExecutor(steps: [
            .success(resourceVersionResult()),
            .success(resourceEmptySuccess()),
            .success(resourceContainerListResult(id: "ssh-demo", state: "created")),
            .success(resourceEmptySuccess()),
            .success(resourceContainerListResult(id: "ssh-demo", state: "running")),
        ])
        let request = ContainerCreateRequest(
            name: "ssh-demo",
            image: "docker.io/library/ubuntu:26.04",
            ports: [PortMapping(hostPort: 8080, containerPort: 80)],
            environment: [EnvironmentEntry(name: "APP_MODE", value: "development")],
            startAfterCreate: true,
            ssh: SSHCreateConfiguration(hostPort: 2222, username: "dev", publicKey: publicKey)
        )

        let outcome = try await resourceClient(executor).createContainer(request)

        XCTAssertTrue(outcome.matchedExpectation)
        XCTAssertEqual(outcome.observedContainer?.state, .running)
        let requests = await executor.requests
        XCTAssertEqual(requests[1].arguments, [
            "create", "--name", "ssh-demo",
            "--publish", "127.0.0.1:8080:80/tcp",
            "--publish", "127.0.0.1:2222:22/tcp",
            "--label", "\(SSHContainerLabels.enabled)=true",
            "--label", "\(SSHContainerLabels.hostPort)=2222",
            "--label", "\(SSHContainerLabels.username)=dev",
            "--env", "APP_MODE=development",
            "--env", "\(SSHCreateConfiguration.userEnvironmentName)=dev",
            "--env", "\(SSHCreateConfiguration.publicKeyEnvironmentName)=\(publicKey)",
            "--init", "--entrypoint", "/bin/sh",
            "--", "docker.io/library/ubuntu:26.04", "-c", SSHContainerBootstrap.script,
        ])
        XCTAssertFalse(SSHContainerBootstrap.script.contains(publicKey))
        XCTAssertFalse(SSHContainerBootstrap.script.contains("fixture@example"))
        XCTAssertFalse(SSHContainerBootstrap.script.contains("Subsystem sftp"))
        XCTAssertEqual(requests[3].arguments, ["start", "ssh-demo"])
    }

    func testRootSSHCreateUsesExplicitRootIdentityAndFixedBootstrap() async throws {
        let publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhY fixture@example"
        let executor = ResourceScriptedCommandExecutor(steps: [
            .success(resourceVersionResult()),
            .success(resourceEmptySuccess()),
            .success(resourceContainerListResult(id: "root-ssh-demo", state: "created")),
            .success(resourceEmptySuccess()),
            .success(resourceContainerListResult(id: "root-ssh-demo", state: "running")),
        ])
        let request = ContainerCreateRequest(
            name: "root-ssh-demo",
            image: "docker.io/library/ubuntu:26.04",
            startAfterCreate: true,
            ssh: SSHCreateConfiguration(
                hostPort: 2001,
                username: "root",
                publicKey: publicKey,
                loginAsRoot: true
            )
        )

        _ = try await resourceClient(executor).createContainer(request)

        let requests = await executor.requests
        XCTAssertEqual(requests[1].arguments, [
            "create", "--name", "root-ssh-demo",
            "--publish", "127.0.0.1:2001:22/tcp",
            "--label", "\(SSHContainerLabels.enabled)=true",
            "--label", "\(SSHContainerLabels.hostPort)=2001",
            "--label", "\(SSHContainerLabels.username)=root",
            "--env", "\(SSHCreateConfiguration.userEnvironmentName)=root",
            "--env", "\(SSHCreateConfiguration.publicKeyEnvironmentName)=\(publicKey)",
            "--init", "--entrypoint", "/bin/sh",
            "--", "docker.io/library/ubuntu:26.04", "-c", SSHContainerBootstrap.script,
        ])
        XCTAssertFalse(requests[1].arguments.contains(where: { $0.contains("CONTAINER_GUI_SSH_ROOT_PASSWORD") }))
    }

    func testInvalidCreateDoesNotExecuteCLI() async {
        let executor = ResourceScriptedCommandExecutor(steps: [])

        do {
            _ = try await resourceClient(executor).createContainer(
                ContainerCreateRequest(name: "-bad", image: "bad image")
            )
            XCTFail("Expected validation error")
        } catch let problem as ProblemDetail {
            XCTAssertEqual(problem.code, .validationFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let requests = await executor.requests
        XCTAssertTrue(requests.isEmpty)
    }

    private func assertValidationError<T>(
        _ expression: @autoclosure () throws -> T,
        fields expectedFields: Set<String>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try expression()
            XCTFail("Expected validation failure", file: file, line: line)
        } catch let problem as ProblemDetail {
            XCTAssertEqual(problem.code, .validationFailed, file: file, line: line)
            XCTAssertEqual(Set(problem.fieldErrors?.map(\.field) ?? []), expectedFields, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "Fixtures/CLI/1.3.1/resources"
            )
        )
        return try Data(contentsOf: url)
    }

    private func resourceClient(_ executor: ResourceScriptedCommandExecutor) -> ContainerCLIClient {
        ContainerCLIClient(
            executor: executor,
            executableURL: URL(fileURLWithPath: "/fixture/container"),
            queryTimeout: .seconds(5),
            mutationTimeout: .seconds(30),
            imagePullTimeout: .seconds(30 * 60),
            maximumOutputBytes: 1_000_000
        )
    }
}

private actor ImagePullProgressRecorder {
    private(set) var values: [ImagePullProgress] = []

    func append(_ value: ImagePullProgress) {
        values.append(value)
    }
}

private enum ResourceScriptedStep: Sendable {
    case success(CommandResult)
    case failure(CommandExecutionError)
}

private actor ResourceScriptedCommandExecutor: CommandExecuting {
    private var steps: [ResourceScriptedStep]
    private(set) var requests: [CommandRequest] = []

    init(steps: [ResourceScriptedStep]) { self.steps = steps }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        guard !steps.isEmpty else { throw CommandExecutionError.streamFailed }
        switch steps.removeFirst() {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }
}

private func resourceVersionResult() -> CommandResult {
    CommandResult(
        stdout: Data("container CLI version 1.3.1".utf8),
        stderr: Data(),
        exitCode: 0,
        duration: .zero
    )
}

private func resourceEmptySuccess() -> CommandResult {
    CommandResult(stdout: Data(), stderr: Data(), exitCode: 0, duration: .zero)
}

private func resourceContainerListResult(
    id: String? = nil,
    state: String = "stopped",
    imageReference: String = "postgres:latest"
) -> CommandResult {
    guard let id else {
        return CommandResult(stdout: Data("[]".utf8), stderr: Data(), exitCode: 0, duration: .zero)
    }
    let json = """
    [{"id":"\(id)","configuration":{"id":"\(id)","image":{"reference":"\(imageReference)"}},"status":{"state":"\(state)","networks":[]}}]
    """
    return CommandResult(stdout: Data(json.utf8), stderr: Data(), exitCode: 0, duration: .zero)
}

private func resourceImageListResult(reference: String) -> CommandResult {
    let json = """
    [{"configuration":{"descriptor":{"digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"name":"\(reference)"},"id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","variants":[{"platform":{"architecture":"arm64","os":"linux"},"size":1024}]}]
    """
    return CommandResult(stdout: Data(json.utf8), stderr: Data(), exitCode: 0, duration: .zero)
}
