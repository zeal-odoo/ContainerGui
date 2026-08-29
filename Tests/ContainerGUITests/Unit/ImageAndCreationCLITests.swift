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

    func testPullUsesFixedArgumentsLongTimeoutAndInspectReadback() async throws {
        let executor = ResourceScriptedCommandExecutor(steps: [
            .success(resourceVersionResult()),
            .success(resourceEmptySuccess()),
            .success(CommandResult(
                stdout: try fixture("image-inspect.json"),
                stderr: Data(),
                exitCode: 0,
                duration: .zero
            )),
        ])
        let client = resourceClient(executor)

        let outcome = try await client.pullImage(
            ImagePullRequest(reference: "postgres:latest", platform: "linux/arm64")
        )

        XCTAssertTrue(outcome.matchedExpectation)
        XCTAssertEqual(outcome.observedImage.name, "docker.io/library/postgres:latest")
        let requests = await executor.requests
        XCTAssertEqual(requests[1].arguments, [
            "image", "pull", "--progress", "none", "--platform", "linux/arm64", "postgres:latest",
        ])
        XCTAssertEqual(requests[1].timeout, .seconds(30 * 60))
        XCTAssertEqual(requests[2].arguments, ["image", "inspect", "postgres:latest"])
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
            cpus: 2.5,
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
            "--cpus", "2.5",
            "--memory", "2048M",
            "--publish", "127.0.0.1:15432:5432/tcp",
            "--publish", "127.0.0.1:15353:53/udp",
            "--env", "POSTGRES_PASSWORD=secret-value",
            "--", "postgres:latest", "postgres", "-c", "shared_buffers=256MB",
        ])
        XCTAssertEqual(requests[1].timeout, .seconds(30))
        XCTAssertEqual(requests[2].arguments, ["list", "--all", "--format", "json"])
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

private func resourceContainerListResult(id: String, state: String) -> CommandResult {
    let json = """
    [{"id":"\(id)","configuration":{"id":"\(id)","image":{"reference":"postgres:latest"}},"status":{"state":"\(state)","networks":[]}}]
    """
    return CommandResult(stdout: Data(json.utf8), stderr: Data(), exitCode: 0, duration: .zero)
}
