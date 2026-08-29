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

    func testSerializesSameImageTarget() async throws {
        let coordinator = OperationCoordinator()
        let target = OperationTarget.image(reference: "postgres:latest")
        _ = try await coordinator.create(
            idempotencyKey: "key-1",
            fingerprint: "pull:postgres:latest",
            kind: .pullImage,
            target: target,
            safeRequestSummary: ["reference": .string("postgres:latest")]
        )

        do {
            _ = try await coordinator.create(
                idempotencyKey: "key-2",
                fingerprint: "pull:postgres:latest:linux/arm64",
                kind: .pullImage,
                target: target,
                safeRequestSummary: ["reference": .string("postgres:latest")]
            )
            XCTFail("Expected image target serialization")
        } catch {
            XCTAssertEqual(error as? OperationCoordinatorError, .operationInProgress)
        }
    }

    func testImageTargetAndReadbackRoundTrip() throws {
        let observedImage: JSONValue = .object([
            "name": .string("docker.io/library/postgres:latest"),
            "digest": .string("sha256:" + String(repeating: "a", count: 64)),
        ])
        let operation = Operation(
            id: UUID(),
            kind: .pullImage,
            target: .image(reference: "postgres:latest"),
            state: .succeeded,
            requestedAt: Date(timeIntervalSince1970: 100),
            startedAt: Date(timeIntervalSince1970: 101),
            finishedAt: Date(timeIntervalSince1970: 102),
            safeRequestSummary: ["reference": .string("postgres:latest")],
            exitCode: 0,
            error: nil,
            readback: OperationReadback(
                expectationMatched: true,
                observedImage: observedImage,
                observedAt: Date(timeIntervalSince1970: 102)
            )
        )

        let encoded = try JSONEncoder.containerGUI.encode(operation)
        let decoded = try JSONDecoder.containerGUI.decode(Operation.self, from: encoded)

        XCTAssertEqual(decoded.target, .image(reference: "postgres:latest"))
        XCTAssertEqual(decoded.readback?.observedImage, observedImage)
    }

    func testTracksMonotonicImagePullProgressAndMarksVerificationComplete() async throws {
        let coordinator = OperationCoordinator()
        let operation = try await coordinator.create(
            idempotencyKey: "pull-progress",
            fingerprint: "pull:postgres:latest",
            kind: .pullImage,
            target: .image(reference: "postgres:latest"),
            safeRequestSummary: ["reference": .string("postgres:latest")]
        )
        try await coordinator.markRunning(operation.id)
        try await coordinator.updateProgress(operation.id, progress: ImagePullProgress(
            phase: .fetching,
            percentComplete: 40,
            completedUnits: 4,
            totalUnits: 10
        ))
        try await coordinator.updateProgress(operation.id, progress: ImagePullProgress(
            phase: .fetching,
            percentComplete: 20,
            completedUnits: 2,
            totalUnits: 10
        ))

        let observedRunning = await coordinator.operation(id: operation.id)
        var current = try XCTUnwrap(observedRunning)
        XCTAssertEqual(current.progress?.percentComplete, 40)
        try await coordinator.markVerifying(operation.id, exitCode: 0)
        let observedVerifying = await coordinator.operation(id: operation.id)
        current = try XCTUnwrap(observedVerifying)
        XCTAssertEqual(current.progress?.phase, .verifying)
        XCTAssertEqual(current.progress?.percentComplete, 100)
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
