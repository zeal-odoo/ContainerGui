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

        try await app.test(.router) { client in
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

    func testIdempotencyConflictAndSameTargetConflict() async throws {
        let controller = StubController(state: .stopped, delay: .milliseconds(250))
        let app = makeApplication(controller: controller)
        let expectedOrigin = origin
        let headerName = idempotencyName

        try await app.test(.router) { client in
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

        try await app.test(.router) { client in
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

private actor StubController: ContainerControlling {
    private var state: ContainerState
    private let delay: Duration

    init(state: ContainerState, delay: Duration = .zero) {
        self.state = state
        self.delay = delay
    }

    func listContainers() async throws -> ContainerList {
        ContainerList(items: [summary()], observedAt: Date())
    }

    func startContainer(id _: String) async throws -> ContainerControlOutcome {
        try await Task.sleep(for: delay)
        state = .running
        return ContainerControlOutcome(exitCode: 0, observedContainer: summary(), matchedExpectation: true)
    }

    func stopContainer(id _: String) async throws -> ContainerControlOutcome {
        try await Task.sleep(for: delay)
        state = .stopped
        return ContainerControlOutcome(exitCode: 0, observedContainer: summary(), matchedExpectation: true)
    }

    private func summary() -> ContainerSummary {
        ContainerSummary(
            id: "demo", displayName: "demo", imageReference: "example.invalid/demo:1",
            state: state, rawState: state.rawValue, ipv4Address: nil, ipv6Address: nil,
            createdAt: nil, observedAt: Date()
        )
    }
}
