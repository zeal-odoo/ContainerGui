import Foundation
import XCTest

@testable import ContainerGUI

final class OperationCoordinatorTests: XCTestCase {
    private let target = OperationTarget.container(id: "container-001")

    func testIdempotencyReplaysAndConflicts() async throws {
        let coordinator = OperationCoordinator()
        let first = try await coordinator.create(
            idempotencyKey: "key-1",
            fingerprint: "start:container-001",
            kind: .startContainer,
            target: target,
            safeRequestSummary: [:]
        )
        let replay = try await coordinator.create(
            idempotencyKey: "key-1",
            fingerprint: "start:container-001",
            kind: .startContainer,
            target: target,
            safeRequestSummary: [:]
        )

        XCTAssertEqual(first.id, replay.id)
        do {
            _ = try await coordinator.create(
                idempotencyKey: "key-1",
                fingerprint: "stop:container-001",
                kind: .stopContainer,
                target: target,
                safeRequestSummary: [:]
            )
            XCTFail("Expected idempotency conflict")
        } catch {
            XCTAssertEqual(error as? OperationCoordinatorError, .idempotencyConflict)
        }
    }

    func testSerializesSameTarget() async throws {
        let coordinator = OperationCoordinator()
        _ = try await coordinator.create(
            idempotencyKey: "key-1",
            fingerprint: "start:container-001",
            kind: .startContainer,
            target: target,
            safeRequestSummary: [:]
        )

        do {
            _ = try await coordinator.create(
                idempotencyKey: "key-2",
                fingerprint: "stop:container-001",
                kind: .stopContainer,
                target: target,
                safeRequestSummary: [:]
            )
            XCTFail("Expected target serialization")
        } catch {
            XCTAssertEqual(error as? OperationCoordinatorError, .operationInProgress)
        }
    }

    func testEnforcesGlobalMutationLimit() async throws {
        let coordinator = OperationCoordinator(maximumConcurrentMutations: 2)
        var ids: [UUID] = []
        for index in 0..<2 {
            let operation = try await coordinator.create(
                idempotencyKey: "key-\(index)",
                fingerprint: "start:c-\(index)",
                kind: .startContainer,
                target: .container(id: "c-\(index)"),
                safeRequestSummary: [:]
            )
            try await coordinator.markRunning(operation.id)
            ids.append(operation.id)
        }

        let third = try await coordinator.create(
            idempotencyKey: "key-3",
            fingerprint: "start:c-3",
            kind: .startContainer,
            target: .container(id: "c-3"),
            safeRequestSummary: [:]
        )
        do {
            try await coordinator.markRunning(third.id)
            XCTFail("Expected global limit")
        } catch {
            XCTAssertEqual(error as? OperationCoordinatorError, .globalLimitReached)
        }
        XCTAssertEqual(ids.count, 2)
    }

    func testRequiresLegalTransitionsAndMatchedReadback() async throws {
        let coordinator = OperationCoordinator()
        let operation = try await coordinator.create(
            idempotencyKey: "key-1",
            fingerprint: "start:container-001",
            kind: .startContainer,
            target: target,
            safeRequestSummary: [:]
        )

        do {
            try await coordinator.markVerifying(operation.id, exitCode: 0)
            XCTFail("Expected illegal transition")
        } catch {
            XCTAssertEqual(error as? OperationCoordinatorError, .illegalTransition)
        }
        try await coordinator.markRunning(operation.id)
        try await coordinator.markVerifying(operation.id, exitCode: 0)
        do {
            _ = try await coordinator.succeed(operation.id, readback: nil)
            XCTFail("Expected readback requirement")
        } catch {
            XCTAssertEqual(error as? OperationCoordinatorError, .readbackRequired)
        }
        do {
            _ = try await coordinator.succeed(
                operation.id,
                readback: OperationReadback(observedState: "stopped", expectationMatched: false)
            )
            XCTFail("Expected readback mismatch")
        } catch {
            XCTAssertEqual(error as? OperationCoordinatorError, .readbackMismatch)
        }
        let completed = try await coordinator.succeed(
            operation.id,
            readback: OperationReadback(observedState: "running", expectationMatched: true)
        )
        XCTAssertEqual(completed.state, .succeeded)
        XCTAssertNotNil(completed.finishedAt)
    }

    func testEvictsExpiredTerminalRecords() async throws {
        let coordinator = OperationCoordinator(operationTTL: .seconds(1))
        let createdAt = Date(timeIntervalSince1970: 100)
        let operation = try await coordinator.create(
            idempotencyKey: "key-1",
            fingerprint: "start:container-001",
            kind: .startContainer,
            target: target,
            safeRequestSummary: [:],
            now: createdAt
        )
        try await coordinator.markRunning(operation.id, now: createdAt)
        try await coordinator.markVerifying(operation.id, exitCode: 0, now: createdAt)
        _ = try await coordinator.succeed(
            operation.id,
            readback: OperationReadback(observedState: "running", expectationMatched: true),
            now: createdAt
        )

        await coordinator.purgeExpired(now: createdAt.addingTimeInterval(2))
        let evicted = await coordinator.operation(id: operation.id)
        XCTAssertNil(evicted)
    }
}
