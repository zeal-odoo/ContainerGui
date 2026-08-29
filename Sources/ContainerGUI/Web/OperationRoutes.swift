import Foundation
import Hummingbird

final class ContainerControlService<Controller: ContainerControlling>: Sendable {
    private let controller: Controller
    private let coordinator: OperationCoordinator

    init(controller: Controller, coordinator: OperationCoordinator) {
        self.controller = controller
        self.coordinator = coordinator
    }

    func submitStart(id: String, idempotencyKey: String) async throws -> Operation {
        let fingerprint = "startContainer:\(id)"
        if let existing = try await coordinator.existing(
            idempotencyKey: idempotencyKey,
            fingerprint: fingerprint
        ) { return existing }
        let current = try await currentContainer(id: id)
        guard current.state == .stopped || current.state == .created else {
            throw ProblemDetail(code: .stateConflict)
        }
        let operation = try await coordinator.create(
            idempotencyKey: idempotencyKey,
            fingerprint: fingerprint,
            kind: .startContainer,
            target: .container(id: id),
            safeRequestSummary: ["containerId": .string(id)]
        )
        Task { await execute(operation: operation, expectedState: .running) }
        return operation
    }

    func submitStop(id: String, confirmationTarget: String, idempotencyKey: String) async throws -> Operation {
        guard confirmationTarget == id else { throw ProblemDetail(code: .confirmationMismatch) }
        let fingerprint = "stopContainer:\(id)"
        if let existing = try await coordinator.existing(
            idempotencyKey: idempotencyKey,
            fingerprint: fingerprint
        ) { return existing }
        let current = try await currentContainer(id: id)
        guard current.state == .running else { throw ProblemDetail(code: .stateConflict) }
        let operation = try await coordinator.create(
            idempotencyKey: idempotencyKey,
            fingerprint: fingerprint,
            kind: .stopContainer,
            target: .container(id: id),
            safeRequestSummary: ["containerId": .string(id), "graceSeconds": .number(10)]
        )
        Task { await execute(operation: operation, expectedState: .stopped) }
        return operation
    }

    private func execute(operation: Operation, expectedState: ContainerState) async {
        do {
            try await coordinator.markRunning(operation.id)
            let outcome: ContainerControlOutcome
            switch operation.kind {
            case .startContainer:
                outcome = try await controller.startContainer(id: operation.target.id)
            case .stopContainer:
                outcome = try await controller.stopContainer(id: operation.target.id)
            default:
                throw ProblemDetail(code: .internalError)
            }
            try await coordinator.markVerifying(operation.id, exitCode: outcome.exitCode)
            let readback = try makeReadback(outcome)
            if outcome.matchedExpectation && outcome.observedContainer.state == expectedState {
                _ = try await coordinator.succeed(operation.id, readback: readback)
            } else {
                _ = try await coordinator.fail(
                    operation.id,
                    problem: ProblemDetail(code: .stateConflict, operationID: operation.id),
                    readback: readback
                )
            }
        } catch {
            _ = try? await coordinator.fail(
                operation.id,
                problem: ProblemDetail(
                    code: error.containerGUIProblem.code,
                    operationID: operation.id
                )
            )
        }
    }

    private func currentContainer(id: String) async throws -> ContainerSummary {
        let list = try await controller.listContainers()
        guard let current = list.items.first(where: { $0.id == id }) else {
            throw ProblemDetail(code: .targetNotFound)
        }
        return current
    }

    private func makeReadback(_ outcome: ContainerControlOutcome) throws -> OperationReadback {
        let data = try JSONEncoder.containerGUI.encode(outcome.observedContainer)
        let value = try JSONDecoder.containerGUI.decode(JSONValue.self, from: data)
        return OperationReadback(
            expectationMatched: outcome.matchedExpectation,
            observedContainer: value,
            observedAt: outcome.observedContainer.observedAt
        )
    }
}

enum OperationRoutes {
    static func register(
        on router: Router<BasicRequestContext>,
        coordinator: OperationCoordinator
    ) {
        router.get("/api/v1/operations/:operationId") { _, context in
            let rawID = try context.parameters.require("operationId")
            guard let id = UUID(uuidString: rawID),
                  let operation = await coordinator.operation(id: id) else {
                throw ProblemDetail(code: .targetNotFound)
            }
            return try makeJSONResponse(operation)
        }
    }
}
