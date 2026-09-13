import Foundation
import XCTest

@testable import ContainerGUI

final class SystemStartCLITests: XCTestCase {
    func test141RecognizesNonzeroClosedStatesAndCanReadBackStart() async throws {
        for status in ["not running", "unregistered"] {
            let executor = SystemStartExecutor(status: status, statusExitCode: 1, version: "1.4.1")
            let client = makeClient(executor)
            let closed = try await client.systemHealth()
            XCTAssertTrue([SystemServiceState.stopped, .unregistered].contains(closed.serviceState))
            XCTAssertNil(closed.diagnosticCode)
            let started = try await client.startSystem()
            XCTAssertEqual(started.serviceState, .healthy)
            XCTAssertEqual(started.tool.semanticVersion, "1.4.1")
        }
    }

    func testNonzeroExitWithClosedStatusIsStillRecognized() async throws {
        for status in ["stopped", "unregistered"] {
            let executor = SystemStartExecutor(status: status, statusExitCode: 1)
            let health = try await makeClient(executor).systemHealth()
            XCTAssertEqual(health.serviceState.rawValue, status)
            XCTAssertNil(health.diagnosticCode)
        }
    }

    func testNonzeroExitCannotClaimHealthyOrUnknownState() async throws {
        for status in ["running", "unexpected"] {
            let executor = SystemStartExecutor(status: status, statusExitCode: 1)
            let health = try await makeClient(executor).systemHealth()
            XCTAssertEqual(health.serviceState, .unavailable)
            XCTAssertEqual(health.diagnosticCode, "CLI_EXIT_NONZERO")
        }
    }

    func testStartUsesFixedNoninteractiveCommandAndHealthReadback() async throws {
        let executor = SystemStartExecutor(status: "unregistered", statusExitCode: 1)
        let health = try await makeClient(executor).startSystem()
        XCTAssertEqual(health.serviceState, .healthy)
        let requests = await executor.requests
        XCTAssertEqual(requests.map(\.arguments), [
            ["--version"], ["system", "status", "--format", "json"],
            ["system", "start", "--disable-kernel-install", "--timeout", "20"],
            ["system", "status", "--format", "json"],
        ])
        XCTAssertEqual(requests[2].timeout, .seconds(30))
        XCTAssertTrue(requests.allSatisfy { $0.executableURL.path == "/fixture/container" })
    }

    func testHealthySystemIsNotStartedAgain() async throws {
        let executor = SystemStartExecutor(status: "running")
        let health = try await makeClient(executor).startSystem()
        XCTAssertEqual(health.serviceState, .healthy)
        let requests = await executor.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testUnsupportedInstallationAndUnknownStateCannotStart() async throws {
        let missing = ContainerCLIClient(executor: SystemStartExecutor(), executableURL: nil)
        do {
            _ = try await missing.startSystem()
            XCTFail("Missing CLI must be rejected")
        } catch {
            XCTAssertEqual(error.containerGUIProblem.code, .cliNotFound)
        }
        let executor = SystemStartExecutor(status: "unexpected")
        do {
            _ = try await makeClient(executor).startSystem()
            XCTFail("Unknown state must not permit a mutation")
        } catch {
            XCTAssertEqual(error.containerGUIProblem.code, .serviceUnavailable)
        }
        let requests = await executor.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testNonzeroAndTimeoutAreNotSuccess() async throws {
        for failure in [SystemStartExecutor.Failure.nonzero, .timeout] {
            let executor = SystemStartExecutor(failure: failure)
            do {
                _ = try await makeClient(executor).startSystem()
                XCTFail("Failed CLI start must throw")
            } catch {
                XCTAssertEqual(error.containerGUIProblem.code, failure == .timeout ? .cliTimeout : .cliExitNonzero)
            }
            let requests = await executor.requests
            XCTAssertEqual(requests.count, 3)
        }
    }

    func testExitZeroStillReturnsActualUnhealthyState() async throws {
        let executor = SystemStartExecutor(readback: "stopped")
        let health = try await makeClient(executor).startSystem()
        XCTAssertEqual(health.serviceState, .stopped)
    }

    private func makeClient(_ executor: SystemStartExecutor) -> ContainerCLIClient {
        ContainerCLIClient(executor: executor, executableURL: URL(fileURLWithPath: "/fixture/container"))
    }
}

private actor SystemStartExecutor: CommandExecuting {
    enum Failure { case nonzero, timeout }
    private var status: String
    private let readback: String
    private let failure: Failure?
    private var statusExitCode: Int32
    private let version: String
    private(set) var requests: [CommandRequest] = []

    init(status: String = "stopped", readback: String = "running", failure: Failure? = nil, statusExitCode: Int32 = 0, version: String = "1.3.1") {
        self.status = status
        self.readback = readback
        self.failure = failure
        self.statusExitCode = statusExitCode
        self.version = version
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        let output: String
        switch request.arguments {
        case ["--version"]: output = "container CLI version \(version)"
        case ["system", "status", "--format", "json"]:
            return CommandResult(stdout: Data("{\"status\":\"\(status)\"}".utf8), stderr: Data(), exitCode: statusExitCode, duration: .zero)
        case ["system", "start", "--disable-kernel-install", "--timeout", "20"]:
            if failure == .timeout { throw CommandExecutionError.timedOut }
            if failure == .nonzero {
                return CommandResult(stdout: Data(), stderr: Data("private diagnostic".utf8), exitCode: 1, duration: .zero)
            }
            status = readback
            statusExitCode = 0
            output = ""
        default: throw CommandExecutionError.streamFailed
        }
        return CommandResult(stdout: Data(output.utf8), stderr: Data(), exitCode: 0, duration: .zero)
    }
}
