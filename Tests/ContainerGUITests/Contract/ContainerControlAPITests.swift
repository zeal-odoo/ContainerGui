import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import XCTest

@testable import ContainerGUI

final class ContainerControlAPITests: XCTestCase {
    private let origin = "http://127.0.0.1:8787"
    private let idempotencyName = HTTPField.Name("Idempotency-Key")!

    func testStartAcceptanceReplayAndOperationPolling() async throws {
        let controller = StubController(state: .stopped)
        let app = makeApplication(controller: controller)
        let key = UUID().uuidString
        let expectedOrigin = origin
        let headerName = idempotencyName

        try await app.testLocal { client in
            let headers: HTTPFields = [.origin: expectedOrigin, .contentType: "application/json", headerName: key]
            let first: ContainerGUI.Operation = try await client.execute(uri: "/api/v1/containers/demo/start", method: .post, headers: headers, body: ByteBuffer(string: "{}")) { response in
                XCTAssertEqual(response.status, .accepted)
                let operation = try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
                XCTAssertEqual(response.headers[.location], "/api/v1/operations/\(operation.id.uuidString)")
                return operation
            }
            let replay: ContainerGUI.Operation = try await client.execute(uri: "/api/v1/containers/demo/start", method: .post, headers: headers, body: ByteBuffer(string: "{}")) { response in
                XCTAssertEqual(response.status, .accepted)
                return try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
            }
            XCTAssertEqual(first.id, replay.id)

            try await Task.sleep(for: .milliseconds(120))
            try await client.execute(uri: "/api/v1/operations/\(first.id.uuidString)", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let operation = try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
                XCTAssertEqual(operation.state, .succeeded)
                XCTAssertEqual(operation.readback?.expectationMatched, true)
            }
        }
    }

    func testRestartAcceptanceReplayOrderAndFinalRunningReadback() async throws {
        let controller = StubController(state: .running)
        let app = makeApplication(controller: controller)
        let key = UUID().uuidString
        let expectedOrigin = origin
        let headerName = idempotencyName

        try await app.testLocal { client in
            let headers: HTTPFields = [.origin: expectedOrigin, .contentType: "application/json", headerName: key]
            let body = ByteBuffer(string: "{\"confirmationTarget\":\"demo\"}")
            let first: ContainerGUI.Operation = try await client.execute(
                uri: "/api/v1/containers/demo/restart",
                method: .post,
                headers: headers,
                body: body
            ) { response in
                XCTAssertEqual(response.status, .accepted)
                let operation = try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
                XCTAssertEqual(operation.kind.rawValue, "restartContainer")
                return operation
            }
            let replay: ContainerGUI.Operation = try await client.execute(
                uri: "/api/v1/containers/demo/restart",
                method: .post,
                headers: headers,
                body: body
            ) { response in
                XCTAssertEqual(response.status, .accepted)
                return try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
            }
            XCTAssertEqual(first.id, replay.id)

            try await Task.sleep(for: .milliseconds(120))
            try await client.execute(uri: "/api/v1/operations/\(first.id.uuidString)", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let operation = try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
                XCTAssertEqual(operation.state, .succeeded)
                XCTAssertEqual(operation.readback?.expectationMatched, true)
                XCTAssertEqual(operation.readback?.observedContainer?.objectValue?["state"]?.stringValue, "running")
            }
        }

        let calls = await controller.calls
        XCTAssertEqual(calls, ["stop", "start"])
    }

    func testRestartRejectsWrongConfirmationAndStoppedTarget() async throws {
        let runningController = StubController(state: .running)
        let runningApp = makeApplication(controller: runningController)
        let expectedOrigin = origin
        let headerName = idempotencyName

        try await runningApp.testLocal { client in
            let headers: HTTPFields = [.origin: expectedOrigin, .contentType: "application/json", headerName: UUID().uuidString]
            try await client.execute(
                uri: "/api/v1/containers/demo/restart",
                method: .post,
                headers: headers,
                body: ByteBuffer(string: "{\"confirmationTarget\":\"wrong\"}")
            ) { response in
                XCTAssertEqual(response.status, .unprocessableContent)
                let problem = try JSONDecoder.containerGUI.decode(ProblemDetail.self, from: response.body)
                XCTAssertEqual(problem.code, .confirmationMismatch)
            }
        }
        let runningCalls = await runningController.calls
        XCTAssertEqual(runningCalls, [])

        let stoppedController = StubController(state: .stopped)
        let stoppedApp = makeApplication(controller: stoppedController)
        try await stoppedApp.testLocal { client in
            let headers: HTTPFields = [.origin: expectedOrigin, .contentType: "application/json", headerName: UUID().uuidString]
            try await client.execute(
                uri: "/api/v1/containers/demo/restart",
                method: .post,
                headers: headers,
                body: ByteBuffer(string: "{\"confirmationTarget\":\"demo\"}")
            ) { response in
                XCTAssertEqual(response.status, .conflict)
                let problem = try JSONDecoder.containerGUI.decode(ProblemDetail.self, from: response.body)
                XCTAssertEqual(problem.code, .stateConflict)
            }
        }
        let stoppedCalls = await stoppedController.calls
        XCTAssertEqual(stoppedCalls, [])
    }

    func testRestartStopFailureDoesNotStartAndReportsActualState() async throws {
        let controller = StubController(state: .running, failure: .stop)
        let app = makeApplication(controller: controller)
        let expectedOrigin = origin
        let headerName = idempotencyName

        try await app.testLocal { client in
            let headers: HTTPFields = [.origin: expectedOrigin, .contentType: "application/json", headerName: UUID().uuidString]
            let operation: ContainerGUI.Operation = try await client.execute(
                uri: "/api/v1/containers/demo/restart",
                method: .post,
                headers: headers,
                body: ByteBuffer(string: "{\"confirmationTarget\":\"demo\"}")
            ) { response in
                XCTAssertEqual(response.status, .accepted)
                return try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
            }

            try await Task.sleep(for: .milliseconds(120))
            try await client.execute(uri: "/api/v1/operations/\(operation.id.uuidString)", method: .get) { response in
                let completed = try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
                XCTAssertEqual(completed.state, .failed)
                XCTAssertEqual(completed.error?.code, .cliExitNonzero)
                XCTAssertEqual(completed.readback?.observedContainer?.objectValue?["state"]?.stringValue, "running")
            }
        }

        let calls = await controller.calls
        XCTAssertEqual(calls, ["stop"])
    }

    func testRestartStartFailureReportsStoppedReadback() async throws {
        let controller = StubController(state: .running, failure: .start)
        let app = makeApplication(controller: controller)
        let expectedOrigin = origin
        let headerName = idempotencyName

        try await app.testLocal { client in
            let headers: HTTPFields = [.origin: expectedOrigin, .contentType: "application/json", headerName: UUID().uuidString]
            let operation: ContainerGUI.Operation = try await client.execute(
                uri: "/api/v1/containers/demo/restart",
                method: .post,
                headers: headers,
                body: ByteBuffer(string: "{\"confirmationTarget\":\"demo\"}")
            ) { response in
                XCTAssertEqual(response.status, .accepted)
                return try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
            }

            try await Task.sleep(for: .milliseconds(120))
            try await client.execute(uri: "/api/v1/operations/\(operation.id.uuidString)", method: .get) { response in
                let completed = try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
                XCTAssertEqual(completed.state, .failed)
                XCTAssertEqual(completed.error?.code, .cliExitNonzero)
                XCTAssertEqual(completed.readback?.observedContainer?.objectValue?["state"]?.stringValue, "stopped")
            }
        }

        let calls = await controller.calls
        XCTAssertEqual(calls, ["stop", "start"])
    }

    func testRestartStateReadbackMismatchFailsWithoutFalseSuccess() async throws {
        let expectedOrigin = origin
        let headerName = idempotencyName
        let cases: [(StubFailure, [String], String)] = [
            (.stopMismatch, ["stop"], "running"),
            (.startMismatch, ["stop", "start"], "stopped"),
        ]

        for (failure, expectedCalls, expectedState) in cases {
            let controller = StubController(state: .running, failure: failure)
            let app = makeApplication(controller: controller)
            try await app.testLocal { client in
                let headers: HTTPFields = [.origin: expectedOrigin, .contentType: "application/json", headerName: UUID().uuidString]
                let operation: ContainerGUI.Operation = try await client.execute(
                    uri: "/api/v1/containers/demo/restart",
                    method: .post,
                    headers: headers,
                    body: ByteBuffer(string: "{\"confirmationTarget\":\"demo\"}")
                ) { response in
                    XCTAssertEqual(response.status, .accepted)
                    return try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
                }

                try await Task.sleep(for: .milliseconds(120))
                try await client.execute(uri: "/api/v1/operations/\(operation.id.uuidString)", method: .get) { response in
                    let completed = try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
                    XCTAssertEqual(completed.state, .failed)
                    XCTAssertEqual(completed.error?.code, .stateConflict)
                    XCTAssertEqual(completed.readback?.expectationMatched, false)
                    XCTAssertEqual(completed.readback?.observedContainer?.objectValue?["state"]?.stringValue, expectedState)
                }
            }

            let calls = await controller.calls
            XCTAssertEqual(calls, expectedCalls)
        }
    }

    func testRestartHoldsTargetLockAgainstOtherControlOperations() async throws {
        let controller = StubController(state: .running, delay: .milliseconds(250))
        let app = makeApplication(controller: controller)
        let expectedOrigin = origin
        let headerName = idempotencyName

        try await app.testLocal { client in
            let restartHeaders: HTTPFields = [.origin: expectedOrigin, .contentType: "application/json", headerName: UUID().uuidString]
            let body = ByteBuffer(string: "{\"confirmationTarget\":\"demo\"}")
            try await client.execute(uri: "/api/v1/containers/demo/restart", method: .post, headers: restartHeaders, body: body) { response in
                XCTAssertEqual(response.status, .accepted)
            }

            let stopHeaders: HTTPFields = [.origin: expectedOrigin, .contentType: "application/json", headerName: UUID().uuidString]
            try await client.execute(uri: "/api/v1/containers/demo/stop", method: .post, headers: stopHeaders, body: body) { response in
                XCTAssertEqual(response.status, .conflict)
                let problem = try JSONDecoder.containerGUI.decode(ProblemDetail.self, from: response.body)
                XCTAssertEqual(problem.code, .operationInProgress)
            }
        }
    }

    func testIdempotencyConflictAndSameTargetConflict() async throws {
        let controller = StubController(state: .stopped, delay: .milliseconds(250))
        let app = makeApplication(controller: controller)
        let expectedOrigin = origin
        let headerName = idempotencyName

        try await app.testLocal { client in
            let sharedKey = UUID().uuidString
            let startHeaders: HTTPFields = [.origin: expectedOrigin, .contentType: "application/json", headerName: sharedKey]
            try await client.execute(uri: "/api/v1/containers/demo/start", method: .post, headers: startHeaders, body: ByteBuffer(string: "{}")) { response in
                XCTAssertEqual(response.status, .accepted)
            }
            let stopBody = ByteBuffer(string: "{\"confirmationTarget\":\"demo\"}")
            try await client.execute(uri: "/api/v1/containers/demo/stop", method: .post, headers: startHeaders, body: stopBody) { response in
                XCTAssertEqual(response.status, .conflict)
                let problem = try JSONDecoder.containerGUI.decode(ProblemDetail.self, from: response.body)
                XCTAssertEqual(problem.code, .idempotencyConflict)
            }

            let secondHeaders: HTTPFields = [.origin: expectedOrigin, .contentType: "application/json", headerName: UUID().uuidString]
            try await client.execute(uri: "/api/v1/containers/demo/start", method: .post, headers: secondHeaders, body: ByteBuffer(string: "{}")) { response in
                XCTAssertEqual(response.status, .conflict)
                let problem = try JSONDecoder.containerGUI.decode(ProblemDetail.self, from: response.body)
                XCTAssertEqual(problem.code, .operationInProgress)
            }
        }
    }

    func testStopRequiresExactConfirmation() async throws {
        let controller = StubController(state: .running)
        let app = makeApplication(controller: controller)
        let expectedOrigin = origin
        let headerName = idempotencyName

        try await app.testLocal { client in
            let headers: HTTPFields = [.origin: expectedOrigin, .contentType: "application/json", headerName: UUID().uuidString]
            try await client.execute(
                uri: "/api/v1/containers/demo/stop",
                method: .post,
                headers: headers,
                body: ByteBuffer(string: "{\"confirmationTarget\":\"wrong\"}")
            ) { response in
                XCTAssertEqual(response.status, .unprocessableContent)
                let problem = try JSONDecoder.containerGUI.decode(ProblemDetail.self, from: response.body)
                XCTAssertEqual(problem.code, .confirmationMismatch)
            }
        }
    }

    func testDeleteRequiresStoppedStateExactConfirmationAndAbsenceReadback() async throws {
        let controller = StubController(state: .stopped)
        let app = makeApplication(controller: controller)
        let expectedOrigin = origin
        let headerName = idempotencyName

        try await app.testLocal { client in
            let headers: HTTPFields = [.origin: expectedOrigin, .contentType: "application/json", headerName: UUID().uuidString]
            let operation: ContainerGUI.Operation = try await client.execute(
                uri: "/api/v1/containers/demo/delete",
                method: .post,
                headers: headers,
                body: ByteBuffer(string: "{\"confirmationTarget\":\"demo\"}")
            ) { response in
                XCTAssertEqual(response.status, .accepted)
                return try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
            }

            try await Task.sleep(for: .milliseconds(120))
            try await client.execute(uri: "/api/v1/operations/\(operation.id.uuidString)", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let completed = try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
                XCTAssertEqual(completed.kind, .deleteContainer)
                XCTAssertEqual(completed.state, .succeeded)
                XCTAssertEqual(completed.readback?.expectationMatched, true)
                XCTAssertEqual(completed.readback?.targetAbsent, true)
            }
        }

        let deleteCount = await controller.deleteCount
        XCTAssertEqual(deleteCount, 1)
    }

    func testDeleteRejectsRunningContainerWithoutCallingCLI() async throws {
        let controller = StubController(state: .running)
        let app = makeApplication(controller: controller)
        let expectedOrigin = origin
        let headerName = idempotencyName

        try await app.testLocal { client in
            let headers: HTTPFields = [.origin: expectedOrigin, .contentType: "application/json", headerName: UUID().uuidString]
            try await client.execute(
                uri: "/api/v1/containers/demo/delete",
                method: .post,
                headers: headers,
                body: ByteBuffer(string: "{\"confirmationTarget\":\"demo\"}")
            ) { response in
                XCTAssertEqual(response.status, .conflict)
                let problem = try JSONDecoder.containerGUI.decode(ProblemDetail.self, from: response.body)
                XCTAssertEqual(problem.code, .stateConflict)
            }
        }

        let deleteCount = await controller.deleteCount
        XCTAssertEqual(deleteCount, 0)
    }

    func testDeleteRejectsMismatchedConfirmation() async throws {
        let controller = StubController(state: .stopped)
        let app = makeApplication(controller: controller)
        let expectedOrigin = origin
        let headerName = idempotencyName

        try await app.testLocal { client in
            let headers: HTTPFields = [.origin: expectedOrigin, .contentType: "application/json", headerName: UUID().uuidString]
            try await client.execute(
                uri: "/api/v1/containers/demo/delete",
                method: .post,
                headers: headers,
                body: ByteBuffer(string: "{\"confirmationTarget\":\"wrong\"}")
            ) { response in
                XCTAssertEqual(response.status, .unprocessableContent)
                let problem = try JSONDecoder.containerGUI.decode(ProblemDetail.self, from: response.body)
                XCTAssertEqual(problem.code, .confirmationMismatch)
            }
        }

        let deleteCount = await controller.deleteCount
        XCTAssertEqual(deleteCount, 0)
    }

    private func makeApplication(controller: some ContainerControlling) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router()
        router.middlewares.add(ErrorMiddleware())
        router.middlewares.add(SafetyMiddleware(policy: RequestSafetyPolicy(expectedOrigin: origin, maximumBodyBytes: 64 * 1024)))
        let coordinator = OperationCoordinator()
        let service = ContainerControlService(controller: controller, coordinator: coordinator)
        OperationRoutes.register(on: router, coordinator: coordinator)
        ContainerControlRoutes.registerControl(on: router, service: service)
        return Application(router: router)
    }
}

private enum StubFailure {
    case none
    case stop
    case start
    case stopMismatch
    case startMismatch
}

private actor StubController: ContainerControlling {
    private var state: ContainerState
    private var isPresent = true
    private(set) var deleteCount = 0
    private(set) var calls: [String] = []
    private let delay: Duration
    private let failure: StubFailure

    init(state: ContainerState, delay: Duration = .zero, failure: StubFailure = .none) {
        self.state = state
        self.delay = delay
        self.failure = failure
    }

    func listContainers() async throws -> ContainerList {
        ContainerList(items: isPresent ? [summary()] : [], observedAt: Date())
    }

    func startContainer(id _: String) async throws -> ContainerControlOutcome {
        calls.append("start")
        try await Task.sleep(for: delay)
        if failure == .start { throw ProblemDetail(code: .cliExitNonzero) }
        if failure == .startMismatch {
            return ContainerControlOutcome(exitCode: 0, observedContainer: summary(), matchedExpectation: false)
        }
        state = .running
        return ContainerControlOutcome(exitCode: 0, observedContainer: summary(), matchedExpectation: true)
    }

    func stopContainer(id _: String) async throws -> ContainerControlOutcome {
        calls.append("stop")
        try await Task.sleep(for: delay)
        if failure == .stop { throw ProblemDetail(code: .cliExitNonzero) }
        if failure == .stopMismatch {
            return ContainerControlOutcome(exitCode: 0, observedContainer: summary(), matchedExpectation: false)
        }
        state = .stopped
        return ContainerControlOutcome(exitCode: 0, observedContainer: summary(), matchedExpectation: true)
    }

    func deleteContainer(id _: String) async throws -> ContainerDeleteOutcome {
        try await Task.sleep(for: delay)
        deleteCount += 1
        isPresent = false
        return ContainerDeleteOutcome(exitCode: 0, targetAbsent: true, observedAt: Date())
    }

    private func summary() -> ContainerSummary {
        ContainerSummary(
            id: "demo", displayName: "demo", imageReference: "example.invalid/demo:1",
            state: state, rawState: state.rawValue, ipv4Address: nil, ipv6Address: nil,
            createdAt: nil, observedAt: Date()
        )
    }
}
