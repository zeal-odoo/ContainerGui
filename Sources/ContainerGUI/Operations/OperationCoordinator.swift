import Foundation

enum OperationCoordinatorError: Error, Equatable, Sendable {
    case idempotencyConflict
    case operationInProgress
    case globalLimitReached
    case operationNotFound
    case illegalTransition
    case readbackRequired
    case readbackMismatch
}

actor OperationCoordinator {
    private struct IdempotencyRecord: Sendable {
        let fingerprint: String
        let operationID: UUID
    }

    private var operations: [UUID: Operation] = [:]
    private var idempotency: [String: IdempotencyRecord] = [:]
    private var targetLocks: [OperationTarget: UUID] = [:]
    private let maximumConcurrentMutations: Int
    private let maximumOperationRecords: Int
    private let operationTTL: Duration

    init(
        maximumConcurrentMutations: Int = 4,
        maximumOperationRecords: Int = 1_000,
        operationTTL: Duration = .seconds(15 * 60)
    ) {
        self.maximumConcurrentMutations = maximumConcurrentMutations
        self.maximumOperationRecords = maximumOperationRecords
        self.operationTTL = operationTTL
    }

    func create(
        idempotencyKey: String,
        fingerprint: String,
        kind: OperationKind,
        target: OperationTarget,
        safeRequestSummary: [String: JSONValue],
        now: Date = Date()
    ) throws -> Operation {
        purgeExpiredInternal(now: now)
        if let record = idempotency[idempotencyKey] {
            guard record.fingerprint == fingerprint else {
                throw OperationCoordinatorError.idempotencyConflict
            }
            guard let operation = operations[record.operationID] else {
                idempotency[idempotencyKey] = nil
                return try create(
                    idempotencyKey: idempotencyKey,
                    fingerprint: fingerprint,
                    kind: kind,
                    target: target,
                    safeRequestSummary: safeRequestSummary,
                    now: now
                )
            }
            return operation
        }
        guard targetLocks[target] == nil else {
            throw OperationCoordinatorError.operationInProgress
        }

        evictToCapacity()
        let operation = Operation(
            id: UUID(),
            kind: kind,
            target: target,
            state: .queued,
            requestedAt: now,
            startedAt: nil,
            finishedAt: nil,
            safeRequestSummary: safeRequestSummary.mapValues { $0.redacted() },
            exitCode: nil,
            error: nil,
            readback: nil
        )
        operations[operation.id] = operation
        idempotency[idempotencyKey] = IdempotencyRecord(
            fingerprint: fingerprint,
            operationID: operation.id
        )
        targetLocks[target] = operation.id
        return operation
    }

    func existing(
        idempotencyKey: String,
        fingerprint: String,
        now: Date = Date()
    ) throws -> Operation? {
        purgeExpiredInternal(now: now)
        guard let record = idempotency[idempotencyKey] else { return nil }
        guard record.fingerprint == fingerprint else {
            throw OperationCoordinatorError.idempotencyConflict
        }
        return operations[record.operationID]
    }

    func markRunning(_ id: UUID, now: Date = Date()) throws {
        guard var operation = operations[id] else { throw OperationCoordinatorError.operationNotFound }
        guard operation.state == .queued else { throw OperationCoordinatorError.illegalTransition }
        let runningCount = operations.values.filter { $0.state == .running }.count
        guard runningCount < maximumConcurrentMutations else {
            throw OperationCoordinatorError.globalLimitReached
        }
        operation.state = .running
        operation.startedAt = now
        operations[id] = operation
    }

    func markVerifying(_ id: UUID, exitCode: Int32, now _: Date = Date()) throws {
        guard var operation = operations[id] else { throw OperationCoordinatorError.operationNotFound }
        guard operation.state == .running || operation.state == .cancelled else {
            throw OperationCoordinatorError.illegalTransition
        }
        operation.state = .verifying
        operation.exitCode = exitCode
        operations[id] = operation
    }

    @discardableResult
    func succeed(
        _ id: UUID,
        readback: OperationReadback?,
        now: Date = Date()
    ) throws -> Operation {
        guard var operation = operations[id] else { throw OperationCoordinatorError.operationNotFound }
        guard operation.state == .verifying else { throw OperationCoordinatorError.illegalTransition }
        guard let readback else { throw OperationCoordinatorError.readbackRequired }
        guard readback.expectationMatched else { throw OperationCoordinatorError.readbackMismatch }
        operation.state = .succeeded
        operation.readback = readback
        operation.finishedAt = now
        operations[id] = operation
        targetLocks[operation.target] = nil
        return operation
    }

    @discardableResult
    func fail(
        _ id: UUID,
        problem: ProblemDetail,
        readback: OperationReadback? = nil,
        now: Date = Date()
    ) throws -> Operation {
        guard var operation = operations[id] else { throw OperationCoordinatorError.operationNotFound }
        guard !operation.state.isTerminal else { throw OperationCoordinatorError.illegalTransition }
        operation.state = .failed
        operation.error = problem
        operation.readback = readback
        operation.finishedAt = now
        operations[id] = operation
        targetLocks[operation.target] = nil
        return operation
    }

    func operation(id: UUID, now: Date = Date()) -> Operation? {
        purgeExpiredInternal(now: now)
        return operations[id]
    }

    func purgeExpired(now: Date = Date()) {
        purgeExpiredInternal(now: now)
    }

    private func purgeExpiredInternal(now: Date) {
        let ttlSeconds = operationTTL.components.seconds
        let expired = operations.values.filter { operation in
            operation.state.isTerminal && operation.finishedAt.map {
                now.timeIntervalSince($0) > Double(ttlSeconds)
            } == true
        }
        remove(expired.map(\.id))
    }

    private func evictToCapacity() {
        guard operations.count >= maximumOperationRecords else { return }
        let candidates = operations.values
            .filter { $0.state.isTerminal }
            .sorted { ($0.finishedAt ?? $0.requestedAt) < ($1.finishedAt ?? $1.requestedAt) }
        let required = operations.count - maximumOperationRecords + 1
        remove(candidates.prefix(required).map(\.id))
    }

    private func remove<S: Sequence>(_ ids: S) where S.Element == UUID {
        let idSet = Set(ids)
        operations = operations.filter { !idSet.contains($0.key) }
        idempotency = idempotency.filter { !idSet.contains($0.value.operationID) }
    }
}
