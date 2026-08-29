import CryptoKit
import Foundation

final class ImageMutationService<Manager>: Sendable
where Manager: ImageReading, Manager: ResourceMutating {
    private let manager: Manager
    private let coordinator: OperationCoordinator

    init(manager: Manager, coordinator: OperationCoordinator) {
        self.manager = manager
        self.coordinator = coordinator
    }

    func submitPull(request: ImagePullRequest, idempotencyKey: String) async throws -> Operation {
        let request = try request.validated()
        let fingerprint = "pullImage:\(request.reference):\(request.platform ?? "")"
        if let existing = try await coordinator.existing(
            idempotencyKey: idempotencyKey,
            fingerprint: fingerprint
        ) { return existing }
        let operation = try await coordinator.create(
            idempotencyKey: idempotencyKey,
            fingerprint: fingerprint,
            kind: .pullImage,
            target: .image(reference: request.reference),
            safeRequestSummary: request.safeRequestSummary
        )
        Task { await execute(operation: operation, request: request) }
        return operation
    }

    private func execute(operation: Operation, request: ImagePullRequest) async {
        do {
            try await coordinator.markRunning(operation.id)
            let outcome = try await manager.pullImage(request)
            try await coordinator.markVerifying(operation.id, exitCode: outcome.exitCode)
            let readback = try makeReadback(outcome)
            if outcome.matchedExpectation {
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

    private func makeReadback(_ outcome: ImagePullOutcome) throws -> OperationReadback {
        let data = try JSONEncoder.containerGUI.encode(outcome.observedImage)
        let value = try JSONDecoder.containerGUI.decode(JSONValue.self, from: data)
        return OperationReadback(
            expectationMatched: outcome.matchedExpectation,
            observedImage: value,
            observedAt: outcome.observedImage.observedAt
        )
    }
}

final class ContainerCreationService<Manager>: Sendable
where Manager: ContainerControlling, Manager: ResourceMutating {
    private let manager: Manager
    private let coordinator: OperationCoordinator

    init(manager: Manager, coordinator: OperationCoordinator) {
        self.manager = manager
        self.coordinator = coordinator
    }

    func submitCreate(request: ContainerCreateRequest, idempotencyKey: String) async throws -> Operation {
        let request = try request.validated()
        let fingerprint = try requestFingerprint(request)
        if let existing = try await coordinator.existing(
            idempotencyKey: idempotencyKey,
            fingerprint: fingerprint
        ) { return existing }

        let current = try await manager.listContainers()
        guard !current.items.contains(where: {
            $0.id == request.name || $0.displayName == request.name
        }) else {
            throw ProblemDetail(code: .stateConflict)
        }
        let operation = try await coordinator.create(
            idempotencyKey: idempotencyKey,
            fingerprint: fingerprint,
            kind: .createContainer,
            target: .container(id: request.name),
            safeRequestSummary: request.safeRequestSummary
        )
        Task { await execute(operation: operation, request: request) }
        return operation
    }

    private func execute(operation: Operation, request: ContainerCreateRequest) async {
        do {
            try await coordinator.markRunning(operation.id)
            let outcome = try await manager.createContainer(request)
            try await coordinator.markVerifying(operation.id, exitCode: outcome.exitCode)
            let readback = try makeReadback(outcome)
            if outcome.matchedExpectation, outcome.observedContainer != nil {
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

    private func requestFingerprint(_ request: ContainerCreateRequest) throws -> String {
        let data = try JSONEncoder.containerGUI.encode(request)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func makeReadback(_ outcome: ContainerCreateOutcome) throws -> OperationReadback {
        let value: JSONValue?
        if let observed = outcome.observedContainer {
            let data = try JSONEncoder.containerGUI.encode(observed)
            value = try JSONDecoder.containerGUI.decode(JSONValue.self, from: data)
        } else {
            value = nil
        }
        return OperationReadback(
            expectationMatched: outcome.matchedExpectation,
            observedContainer: value,
            targetAbsent: outcome.observedContainer == nil,
            observedAt: outcome.observedContainer?.observedAt ?? Date()
        )
    }
}
