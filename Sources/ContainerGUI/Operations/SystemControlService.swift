import Foundation

final class SystemControlService<Controller: SystemControlling>: Sendable {
    private let controller: Controller
    private let coordinator: OperationCoordinator

    init(controller: Controller, coordinator: OperationCoordinator) {
        self.controller = controller
        self.coordinator = coordinator
    }

    func submitStart(idempotencyKey: String) async throws -> Operation {
        let operation = try await coordinator.create(
            idempotencyKey: idempotencyKey,
            fingerprint: "startSystem",
            kind: .startSystem,
            target: .system,
            safeRequestSummary: [:]
        )
        if operation.state == .queued {
            Task { await execute(operation: operation) }
        }
        return operation
    }

    private func execute(operation: Operation) async {
        do {
            do {
                try await coordinator.markRunning(operation.id)
            } catch OperationCoordinatorError.illegalTransition {
                // A concurrent replay may have already started this same operation.
                return
            }
            let health = try await controller.startSystem()
            try await coordinator.markVerifying(operation.id, exitCode: 0)
            let readback = OperationReadback(
                observedState: health.serviceState.rawValue,
                expectationMatched: health.serviceState == .healthy,
                observedAt: health.observedAt
            )
            if readback.expectationMatched {
                _ = try await coordinator.succeed(operation.id, readback: readback)
            } else {
                _ = try await coordinator.fail(
                    operation.id,
                    problem: ProblemDetail(code: .serviceUnavailable, operationID: operation.id),
                    readback: readback
                )
            }
        } catch {
            _ = try? await coordinator.fail(
                operation.id,
                problem: ProblemDetail(code: error.containerGUIProblem.code, operationID: operation.id)
            )
        }
    }
}
