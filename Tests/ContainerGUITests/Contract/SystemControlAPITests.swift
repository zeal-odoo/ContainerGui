import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import XCTest

@testable import ContainerGUI

final class SystemControlAPITests: XCTestCase {
    func testAcceptedStartCanBePolledAndReplayed() async throws {
        let starter = StubSystemStarter()
        let coordinator = OperationCoordinator()
        let app = makeApplication(starter: starter, coordinator: coordinator)
        let headers: HTTPFields = [
            .origin: "http://127.0.0.1:8787", .contentType: "application/json",
            HTTPField.Name("Idempotency-Key")!: UUID().uuidString,
        ]
        try await app.testLocal { client in
            let first: ContainerGUI.Operation = try await client.execute(
                uri: "/api/v1/system/start", method: .post, headers: headers, body: ByteBuffer(string: "{}")
            ) { response in
                XCTAssertEqual(response.status, .accepted)
                let operation = try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
                XCTAssertEqual(operation.kind, .startSystem)
                XCTAssertEqual(operation.target, .system)
                XCTAssertEqual(response.headers[.location], "/api/v1/operations/\(operation.id.uuidString)")
                return operation
            }
            try await client.execute(
                uri: "/api/v1/system/start", method: .post, headers: headers, body: ByteBuffer(string: "{}")
            ) { response in
                XCTAssertEqual(response.status, .accepted)
                let replay = try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
                XCTAssertEqual(replay.id, first.id)
            }
            let completed = try await finishedOperation(first.id, coordinator: coordinator)
            XCTAssertEqual(completed.state, .succeeded)
            XCTAssertEqual(completed.readback?.observedSystemState, "healthy")
            XCTAssertEqual(completed.readback?.expectationMatched, true)
            try await client.execute(uri: "/api/v1/operations/\(first.id.uuidString)", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
            }
        }
        let calls = await starter.calls
        XCTAssertEqual(calls, 1)
    }

    func testConcurrentReplayStartsOnlyOnceAndLocksSystemTarget() async throws {
        let starter = StubSystemStarter(delay: .milliseconds(300))
        let coordinator = OperationCoordinator()
        let service = SystemControlService(controller: starter, coordinator: coordinator)
        let key = UUID().uuidString
        async let first = service.submitStart(idempotencyKey: key)
        async let replay = service.submitStart(idempotencyKey: key)
        let (a, b) = try await (first, replay)
        XCTAssertEqual(a.id, b.id)
        do {
            _ = try await service.submitStart(idempotencyKey: UUID().uuidString)
            XCTFail("The system target must be locked")
        } catch {
            XCTAssertEqual(error.containerGUIProblem.code, .operationInProgress)
        }
        _ = try await finishedOperation(a.id, coordinator: coordinator)
        let calls = await starter.calls
        XCTAssertEqual(calls, 1)
    }

    func testUnhealthyReadbackAndTimeoutFailAndReleaseLock() async throws {
        for failure in [false, true] {
            let starter = StubSystemStarter(state: .stopped, fail: failure)
            let coordinator = OperationCoordinator()
            let service = SystemControlService(controller: starter, coordinator: coordinator)
            let first = try await service.submitStart(idempotencyKey: UUID().uuidString)
            let completed = try await finishedOperation(first.id, coordinator: coordinator)
            XCTAssertEqual(completed.state, .failed)
            XCTAssertEqual(completed.error?.code, failure ? .cliTimeout : .serviceUnavailable)
            if !failure {
                XCTAssertEqual(completed.readback?.observedSystemState, "stopped")
                XCTAssertEqual(completed.readback?.expectationMatched, false)
            }
            let retry = try await service.submitStart(idempotencyKey: UUID().uuidString)
            XCTAssertNotEqual(first.id, retry.id)
            _ = try await finishedOperation(retry.id, coordinator: coordinator)
        }
    }

    func testInvalidRequestsNeverReachSystemStarter() async throws {
        let starter = StubSystemStarter()
        let app = makeApplication(starter: starter, coordinator: OperationCoordinator())
        let key = HTTPField.Name("Idempotency-Key")!
        let valid: HTTPFields = [
            .origin: "http://127.0.0.1:8787", .contentType: "application/json", key: UUID().uuidString,
        ]
        try await app.testLocal { client in
            var foreign = valid
            foreign[.origin] = "https://attacker.invalid"
            var missingOrigin = valid
            missingOrigin[.origin] = nil
            var missingKey = valid
            missingKey[key] = nil
            var wrongType = valid
            wrongType[.contentType] = "text/plain"
            let cases: [(HTTPFields, String, HTTPResponse.Status)] = [
                (foreign, "{}", .forbidden), (missingOrigin, "{}", .forbidden),
                (missingKey, "{}", .unprocessableContent), (wrongType, "{}", .unprocessableContent),
                (valid, "{\"arguments\":[\"--app-root\",\"/tmp/other\"]}", .unprocessableContent),
                (valid, "[]", .unprocessableContent), (valid, "invalid", .unprocessableContent),
            ]
            for (headers, body, expected) in cases {
                try await client.execute(uri: "/api/v1/system/start", method: .post, headers: headers, body: ByteBuffer(string: body)) { response in
                    XCTAssertEqual(response.status, expected)
                }
            }
            try await client.execute(uri: "/api/v1/system/start", method: .get) { response in
                XCTAssertNotEqual(response.status, .accepted)
            }
        }
        try await app.testLocal(authority: "attacker.invalid:8787") { client in
            try await client.execute(uri: "/api/v1/system/start", method: .post, headers: valid, body: ByteBuffer(string: "{}")) { response in
                XCTAssertEqual(response.status, .forbidden)
            }
        }
        let calls = await starter.calls
        XCTAssertEqual(calls, 0)
    }

    private func makeApplication(starter: StubSystemStarter, coordinator: OperationCoordinator) -> some ApplicationProtocol {
        let router = Router()
        router.middlewares.add(ErrorMiddleware())
        router.middlewares.add(SafetyMiddleware(policy: RequestSafetyPolicy(
            expectedOrigin: "http://127.0.0.1:8787", maximumBodyBytes: 64 * 1024
        )))
        SystemControlRoutes.register(on: router, service: SystemControlService(controller: starter, coordinator: coordinator))
        OperationRoutes.register(on: router, coordinator: coordinator)
        return Application(router: router)
    }
}

private func finishedOperation(_ id: UUID, coordinator: OperationCoordinator) async throws -> ContainerGUI.Operation {
    for _ in 0..<200 {
        if let operation = await coordinator.operation(id: id), operation.state.isTerminal { return operation }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw ProblemDetail(code: .cliTimeout)
}

private actor StubSystemStarter: SystemControlling {
    private let state: SystemServiceState
    private let fail: Bool
    private let delay: Duration
    private(set) var calls = 0

    init(state: SystemServiceState = .healthy, fail: Bool = false, delay: Duration = .zero) {
        self.state = state
        self.fail = fail
        self.delay = delay
    }

    func startSystem() async throws -> SystemHealth {
        calls += 1
        try await Task.sleep(for: delay)
        if fail { throw CommandExecutionError.timedOut }
        return SystemHealth(
            tool: CLIInstallation(versionText: "1.3.1", semanticVersion: "1.3.1", compatibility: .supported, checkedAt: Date()),
            serviceState: state, apiServerVersion: nil, apiServerBuild: nil, apiServerCommit: nil,
            diagnosticCode: nil, diagnosticMessage: nil, observedAt: Date()
        )
    }
}
