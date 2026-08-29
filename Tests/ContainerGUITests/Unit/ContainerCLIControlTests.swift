import Foundation
import XCTest

@testable import ContainerGUI

final class ContainerCLIControlTests: XCTestCase {
    func testStartUsesExactIdentifierAndRequiresRunningReadback() async throws {
        let executor = ScriptedCommandExecutor(steps: [
            .success(versionResult()), .success(listResult(id: "demo", state: "stopped")),
            .success(emptySuccess()),
            .success(listResult(id: "demo", state: "running")),
        ])
        let client = makeClient(executor)

        let outcome = try await client.startContainer(id: "demo")

        XCTAssertTrue(outcome.matchedExpectation)
        XCTAssertEqual(outcome.observedContainer.state, .running)
        let requests = await executor.requests
        let mutation = try XCTUnwrap(requests.first(where: { $0.arguments.first == "start" }))
        XCTAssertEqual(mutation.executableURL.path, "/fixture/container")
        XCTAssertEqual(mutation.arguments, ["start", "demo"])
        XCTAssertFalse(mutation.arguments.contains("--all"))
        XCTAssertFalse(mutation.arguments.contains("--force"))
    }

    func testGracefulStopUsesTenSecondsAndNoBroadFlags() async throws {
        let executor = ScriptedCommandExecutor(steps: [
            .success(versionResult()), .success(listResult(id: "demo", state: "running")),
            .success(emptySuccess()),
            .success(listResult(id: "demo", state: "stopped")),
        ])
        let client = makeClient(executor)

        let outcome = try await client.stopContainer(id: "demo")

        XCTAssertTrue(outcome.matchedExpectation)
        let requests = await executor.requests
        let mutation = try XCTUnwrap(requests.first(where: { $0.arguments.first == "stop" }))
        XCTAssertEqual(mutation.arguments, ["stop", "--time", "10", "demo"])
        XCTAssertFalse(mutation.arguments.contains("--all"))
        XCTAssertFalse(mutation.arguments.contains("--force"))
    }

    func testDeleteUsesExactIdentifierWithoutForceAndRequiresAbsenceReadback() async throws {
        let executor = ScriptedCommandExecutor(steps: [
            .success(versionResult()), .success(listResult(id: "demo", state: "stopped")),
            .success(emptySuccess()),
            .success(emptyListResult()),
        ])

        let outcome = try await makeClient(executor).deleteContainer(id: "demo")

        XCTAssertEqual(outcome.exitCode, 0)
        XCTAssertTrue(outcome.targetAbsent)
        let requests = await executor.requests
        let mutation = try XCTUnwrap(requests.first(where: { $0.arguments.first == "delete" }))
        XCTAssertEqual(mutation.arguments, ["delete", "demo"])
        XCTAssertFalse(mutation.arguments.contains("--all"))
        XCTAssertFalse(mutation.arguments.contains("--force"))
    }

    func testDeleteRejectsRunningContainerBeforeMutation() async {
        let executor = ScriptedCommandExecutor(steps: [
            .success(versionResult()), .success(listResult(id: "demo", state: "running")),
        ])

        do {
            _ = try await makeClient(executor).deleteContainer(id: "demo")
            XCTFail("Expected state conflict")
        } catch {
            XCTAssertEqual((error as? ProblemDetail)?.code, .stateConflict)
        }

        let requests = await executor.requests
        XCTAssertFalse(requests.contains(where: { $0.arguments.first == "delete" }))
    }

    func testDeleteExitZeroWithoutAbsenceReadbackIsNotSuccess() async throws {
        let executor = ScriptedCommandExecutor(steps: [
            .success(versionResult()), .success(listResult(id: "demo", state: "created")),
            .success(emptySuccess()),
            .success(listResult(id: "demo", state: "created")),
        ])

        let outcome = try await makeClient(executor).deleteContainer(id: "demo")

        XCTAssertEqual(outcome.exitCode, 0)
        XCTAssertFalse(outcome.targetAbsent)
    }

    func testExitZeroWithoutStateChangeIsNotSuccess() async throws {
        let executor = ScriptedCommandExecutor(steps: [
            .success(versionResult()), .success(listResult(id: "demo", state: "stopped")),
            .success(emptySuccess()),
            .success(listResult(id: "demo", state: "stopped")),
        ])

        let outcome = try await makeClient(executor).startContainer(id: "demo")

        XCTAssertEqual(outcome.exitCode, 0)
        XCTAssertFalse(outcome.matchedExpectation)
        XCTAssertEqual(outcome.observedContainer.state, .stopped)
    }

    func testNonzeroAndTimeoutDoNotPerformSuccessReadback() async {
        let nonzero = ScriptedCommandExecutor(steps: [
            .success(versionResult()), .success(listResult(id: "demo", state: "stopped")),
            .success(CommandResult(stdout: Data(), stderr: Data("failed".utf8), exitCode: 7, duration: .zero)),
        ])
        do {
            _ = try await makeClient(nonzero).startContainer(id: "demo")
            XCTFail("Expected non-zero error")
        } catch {
            XCTAssertEqual(error as? ContainerCLIError, .nonZeroExit(7))
        }

        let timeout = ScriptedCommandExecutor(steps: [
            .success(versionResult()), .success(listResult(id: "demo", state: "running")),
            .failure(.timedOut),
        ])
        do {
            _ = try await makeClient(timeout).stopContainer(id: "demo")
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? CommandExecutionError, .timedOut)
        }
    }

    func testRecentLogsUseBoundedTailAndExactIdentifier() async throws {
        let executor = ScriptedCommandExecutor(steps: [
            .success(versionResult()), .success(listResult(id: "demo", state: "running")),
            .success(CommandResult(stdout: Data("line\n".utf8), stderr: Data(), exitCode: 0, duration: .zero)),
        ])

        let logs = try await makeClient(executor).recentLogs(id: "demo", tail: 25)

        XCTAssertEqual(logs.text, "line\n")
        let requests = await executor.requests
        let command = try XCTUnwrap(requests.first(where: { $0.arguments.first == "logs" }))
        XCTAssertEqual(command.arguments, ["logs", "-n", "25", "demo"])
        XCTAssertFalse(command.arguments.contains("--all"))
        XCTAssertFalse(command.arguments.contains("--force"))
    }

    func testFollowLogsUseFixedFollowShapeAndExactIdentifier() async throws {
        let executor = ScriptedCommandExecutor(steps: [
            .success(versionResult()), .success(listResult(id: "demo", state: "running")),
            .success(CommandResult(stdout: Data("line\n".utf8), stderr: Data(), exitCode: 0, duration: .zero)),
        ])

        let stream = try await makeClient(executor).followLogs(id: "demo", tail: 25)
        for try await _ in stream {}

        let requests = await executor.requests
        let command = try XCTUnwrap(requests.first(where: { $0.arguments.first == "logs" }))
        XCTAssertEqual(command.arguments, ["logs", "--follow", "-n", "25", "demo"])
        XCTAssertFalse(command.arguments.contains("--all"))
        XCTAssertFalse(command.arguments.contains("--force"))
    }

    func testInstallationProbeIsSharedAcrossConcurrentReads() async throws {
        let executor = ScriptedCommandExecutor(steps: [
            .success(versionResult()),
            .success(listResult(id: "demo", state: "running")),
            .success(listResult(id: "demo", state: "running")),
        ])
        let client = makeClient(executor)

        async let first = client.listContainers()
        async let second = client.listContainers()
        _ = try await (first, second)

        let requests = await executor.requests
        XCTAssertEqual(requests.filter { $0.arguments == ["--version"] }.count, 1)
        XCTAssertEqual(requests.filter { $0.arguments == ["list", "--all", "--format", "json"] }.count, 2)
    }

    func testHealthExecutionFailureInvalidatesInstallationProbe() async throws {
        let executor = ScriptedCommandExecutor(steps: [
            .success(versionResult()),
            .failure(.timedOut),
            .success(versionResult()),
            .success(listResult(id: "demo", state: "running")),
        ])
        let client = makeClient(executor)

        do {
            _ = try await client.systemHealth()
            XCTFail("Expected health timeout")
        } catch let error as CommandExecutionError {
            XCTAssertEqual(error, .timedOut)
        }
        _ = try await client.listContainers()

        let requests = await executor.requests
        XCTAssertEqual(requests.filter { $0.arguments == ["--version"] }.count, 2)
    }

    private func makeClient(_ executor: ScriptedCommandExecutor) -> ContainerCLIClient {
        ContainerCLIClient(
            executor: executor,
            executableURL: URL(fileURLWithPath: "/fixture/container"),
            queryTimeout: .seconds(5),
            mutationTimeout: .seconds(30),
            maximumOutputBytes: 1_000_000
        )
    }
}

private enum ScriptedStep: Sendable {
    case success(CommandResult)
    case failure(CommandExecutionError)
}

private actor ScriptedCommandExecutor: CommandExecuting {
    private var steps: [ScriptedStep]
    private(set) var requests: [CommandRequest] = []

    init(steps: [ScriptedStep]) { self.steps = steps }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        guard !steps.isEmpty else { throw CommandExecutionError.streamFailed }
        switch steps.removeFirst() {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }
}

private func versionResult() -> CommandResult {
    CommandResult(stdout: Data("container CLI version 1.3.1".utf8), stderr: Data(), exitCode: 0, duration: .zero)
}

private func emptySuccess() -> CommandResult {
    CommandResult(stdout: Data(), stderr: Data(), exitCode: 0, duration: .zero)
}

private func emptyListResult() -> CommandResult {
    CommandResult(stdout: Data("[]".utf8), stderr: Data(), exitCode: 0, duration: .zero)
}

private func listResult(id: String, state: String) -> CommandResult {
    let json = """
    [{"id":"\(id)","configuration":{"id":"\(id)","image":{"reference":"example.invalid/demo:1"}},"status":{"state":"\(state)","networks":[]}}]
    """
    return CommandResult(stdout: Data(json.utf8), stderr: Data(), exitCode: 0, duration: .zero)
}
