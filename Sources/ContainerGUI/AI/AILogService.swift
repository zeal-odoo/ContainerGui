import CryptoKit
import Darwin
import Foundation

protocol AIModelStoring: Sendable {
    func status() async -> AIModelInstallation
    func install() async throws
    func cancel() async
    func verifiedDirectory() async throws -> URL
}

extension AIModelStore: AIModelStoring {}

struct AILogResult: Codable, Sendable {
    let text: String
    let evidence: String
    let observedAt: Date
    let inputTokens: Int
    let outputTokens: Int
    let elapsedSeconds: Double
}

struct AILogStatus: Codable, Sendable {
    let enabled: Bool
    let phase: String
    let containerId: String?
    let language: String
    let model: AIModelInstallation
    let workerPID: Int32?
    let error: String?
    let result: AILogResult?
    let historyError: String?
    let historyRecordId: UUID?
}

actor AILogService {
    private let reader: any ContainerLogReading
    private let history: AILogHistoryStore
    private let store: any AIModelStoring
    private let worker: any AIWorkerRunning
    private let memoryAvailable: @Sendable () -> Bool
    private let leaseSeconds: Double
    private let minimumInterval: Double
    private var enabled = false
    private var phase = "off"
    private var containerID: String?
    private var language = "zh"
    private var error: String?
    private var result: AILogResult?
    private var historyError: String?
    private var historyRecordID: UUID?
    private var generation = 0
    private var work: Task<Void, Never>?
    private var leaseTask: Task<Void, Never>?
    private let clock = ContinuousClock()
    private var leaseDeadline = ContinuousClock.now
    private var lastAnalysis = ContinuousClock.now.advanced(by: .seconds(-3_600))
    private var lastDigest: SHA256.Digest?

    init(reader: any ContainerLogReading, history: AILogHistoryStore, store: any AIModelStoring = AIModelStore(),
         worker: any AIWorkerRunning = AIWorkerProcess(),
         memoryAvailable: @escaping @Sendable () -> Bool = AILogService.hasMemoryHeadroom,
         leaseSeconds: Double = 60, minimumInterval: Double = 10) {
        self.reader = reader
        self.history = history
        self.store = store
        self.worker = worker
        self.memoryAvailable = memoryAvailable
        self.leaseSeconds = leaseSeconds
        self.minimumInterval = minimumInterval
    }

    func status() async -> AILogStatus {
        let model = await store.status()
        let pid = await worker.pid()
        return AILogStatus(enabled: enabled, phase: phase, containerId: containerID,
                           language: language, model: model, workerPID: pid, error: error, result: result,
                           historyError: historyError, historyRecordId: historyRecordID)
    }

    func install(confirmed: Bool) throws {
        guard confirmed else { throw ProblemDetail(code: .confirmationMismatch) }
        guard !enabled, phase == "off" || phase == "error", work == nil, error != "worker_stop_failed" else {
            throw ProblemDetail(code: .operationInProgress)
        }
        phase = "downloading"
        error = nil
        generation += 1
        let current = generation
        renewLease()
        work = Task {
            do {
                try await store.install()
                guard current == generation else { return }
                phase = "off"
                work = nil
                leaseTask?.cancel()
                leaseTask = nil
            } catch {
                guard current == generation else { return }
                self.error = Self.safeCode(error)
                phase = "error"
                work = nil
                leaseTask?.cancel()
                leaseTask = nil
            }
        }
    }

    func enable(containerID: String, language: String) async throws {
        guard containerID.range(of: #"^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$"#, options: .regularExpression) != nil,
              language == "zh" || language == "en" else { throw ProblemDetail(code: .validationFailed) }
        guard !enabled, phase == "off" || phase == "error", work == nil, error != "worker_stop_failed" else { throw ProblemDetail(code: .operationInProgress) }
        guard memoryAvailable() else {
            error = "insufficient_memory"
            throw ProblemDetail(code: .serviceUnavailable, message: "insufficient_memory")
        }
        // Reserve before awaiting so another window cannot launch a second model.
        enabled = true
        phase = "loading"
        self.containerID = containerID
        self.language = language
        error = nil
        result = nil
        lastDigest = nil
        lastAnalysis = clock.now.advanced(by: .seconds(-3_600))
        generation += 1
        let current = generation
        renewLease()
        work = Task {
            do {
                // The official CLI validates that this container still exists.
                _ = try await reader.recentLogs(id: containerID, tail: 0)
                try Task.checkCancellation()
                let directory = try await store.verifiedDirectory()
                try Task.checkCancellation()
                guard current == generation, enabled else { return }
                try await worker.start(directory: directory)
                guard current == generation, enabled else { return }
                phase = "ready"
                work = nil
            } catch {
                await failed(error, generation: current)
            }
        }
    }

    func heartbeat() {
        if enabled || phase == "downloading" { renewLease() }
    }

    func analyse() {
        guard enabled, phase == "ready", work == nil, let containerID,
              lastAnalysis.duration(to: clock.now) >= .seconds(minimumInterval) else { return }
        guard memoryAvailable() else {
            let current = generation
            work = Task { await failed(AILogFailure.insufficientMemory, generation: current) }
            return
        }
        lastAnalysis = clock.now
        phase = "analysing"
        error = nil
        let current = generation
        work = Task {
            do {
                let logs = try await reader.recentLogs(id: containerID, tail: 200)
                try Task.checkCancellation()
                guard current == generation, enabled else { return }
                let evidence = try await AILogEvidence.prepareForAnalysis(logs.text)
                guard current == generation, enabled else { return }
                let digest = SHA256.hash(data: Data(evidence.utf8))
                guard !evidence.isEmpty else {
                    result = nil
                    lastDigest = nil
                    error = "no_recent_logs"
                    phase = "ready"
                    work = nil
                    return
                }
                guard digest != lastDigest else {
                    phase = "ready"
                    work = nil
                    return
                }
                let answer = try await worker.generate(evidence: evidence, language: language)
                guard current == generation, enabled else { return }
                let completed = AILogResult(text: AILogEvidence.prepare(answer.text), evidence: evidence,
                                     observedAt: logs.observedAt, inputTokens: answer.inputTokens,
                                     outputTokens: answer.outputTokens, elapsedSeconds: answer.elapsedSeconds)
                let record = AILogHistoryRecord(containerId: containerID, language: language, result: completed)
                // A completed result can be archived while disable awaits old work, but
                // no late save may revive the model/session or its temporary result.
                do {
                    try await history.append(record)
                    historyError = nil
                    historyRecordID = record.id
                } catch {
                    historyError = "history_save_failed"
                    historyRecordID = nil
                }
                guard current == generation, enabled else { return }
                result = completed
                lastDigest = digest
                phase = "ready"
                work = nil
            } catch { await failed(error, generation: current) }
        }
    }

    func disable() async throws {
        guard phase != "stopping" else { throw ProblemDetail(code: .operationInProgress) }
        generation += 1
        enabled = false
        phase = "stopping"
        let previous = work
        work?.cancel()
        leaseTask?.cancel()
        leaseTask = nil
        result = nil
        lastDigest = nil
        await store.cancel()
        do {
            try await worker.stop()
            // Old work cannot spawn after the generation/cancellation checks.
            await previous?.value
            // Also cover a dependency that completed a queued start despite cancellation.
            if await worker.pid() != nil { try await worker.stop() }
            work = nil
            containerID = nil
            error = nil
            phase = "off"
        } catch {
            work = nil
            self.error = "worker_stop_failed"
            phase = "error"
            throw ProblemDetail(code: .serviceUnavailable, message: "worker_stop_failed")
        }
    }

    private func failed(_ failure: Error, generation current: Int) async {
        guard current == generation else { return }
        enabled = false
        phase = "stopping"
        leaseTask?.cancel()
        leaseTask = nil
        do {
            try await worker.stop()
            guard current == generation else { return }
            error = Self.safeCode(failure)
        } catch {
            guard current == generation else { return }
            self.error = "worker_stop_failed"
        }
        phase = "error"
        work = nil
    }

    private func renewLease() {
        leaseDeadline = clock.now.advanced(by: .seconds(leaseSeconds))
        guard leaseTask == nil else { return }
        leaseTask = Task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(min(5, max(0.01, leaseSeconds / 2)))) } catch { return }
                if clock.now >= leaseDeadline {
                    // Detach the task before disable cancels the lease it is running in.
                    leaseTask = nil
                    try? await disable()
                    return
                }
            }
        }
    }

    private static func safeCode(_ error: Error) -> String {
        if let value = error as? AIModelStoreError { return value.rawValue }
        if let value = error as? AIWorkerFailure { return value.rawValue }
        if error is AILogFailure { return "insufficient_memory" }
        if error is CancellationError { return "cancelled" }
        return "analysis_unavailable"
    }

    static func hasMemoryHeadroom() -> Bool {
        #if arch(arm64)
        guard ProcessInfo.processInfo.physicalMemory >= 8_000_000_000 else { return false }
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return false }
        let available = (UInt64(statistics.free_count) + UInt64(statistics.inactive_count)) * UInt64(getpagesize())
        return available >= 3 * 1_024 * 1_024 * 1_024
        #else
        return false
        #endif
    }
}

private enum AILogFailure: Error { case insufficientMemory }
