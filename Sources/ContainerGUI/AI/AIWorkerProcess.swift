import Darwin
import Foundation

struct AIWorkerAnswer: Codable, Sendable {
    let id: String
    let text: String
    let inputTokens: Int
    let outputTokens: Int
    let elapsedSeconds: Double
    let error: String?
}

enum AIWorkerFailure: String, Error {
    case busy = "worker_busy"
    case protocolInvalid = "worker_protocol_invalid"
    case exited = "worker_exited"
    case timeout = "worker_timeout"
    case stopFailed = "worker_stop_failed"
    case runtimeFailed = "model_runtime_failed"
}

protocol AIWorkerRunning: Sendable {
    func start(directory: URL) async throws
    func generate(evidence: String, language: String) async throws -> AIWorkerAnswer
    func stop() async throws
    func pid() async -> Int32?
}

actor AIWorkerProcess: AIWorkerRunning {
    private let executable: URL
    private let arguments: [String]?
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var outputTask: Task<Void, Never>?
    private var buffer = Data()
    private var epoch = UUID()
    private var stopping = false
    private var ready = false
    private var readyWaiter: CheckedContinuation<Void, Error>?
    private var answerWaiter: CheckedContinuation<AIWorkerAnswer, Error>?
    private var requestID: String?
    private var timeoutTask: Task<Void, Never>?

    init(executable: URL = Bundle.main.executableURL!, arguments: [String]? = nil) {
        self.executable = executable
        self.arguments = arguments
    }

    func pid() async -> Int32? { process?.isRunning == true ? process?.processIdentifier : nil }

    func start(directory: URL) async throws {
        try Task.checkCancellation()
        guard process == nil, !stopping else { throw AIWorkerFailure.busy }
        let child = Process()
        let input = Pipe()
        let output = Pipe()
        let epoch = UUID()
        self.epoch = epoch
        buffer.removeAll(keepingCapacity: false)
        ready = false
        child.executableURL = executable
        child.arguments = arguments ?? ["--ai-log-worker", directory.path]
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        child.qualityOfService = .utility
        // Do not inherit application credentials or external model configuration.
        child.environment = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path, "TMPDIR": NSTemporaryDirectory()]
        child.terminationHandler = { _ in Task { await self.exited(epoch: epoch) } }
        self.process = child
        self.input = input
        self.output = output
        let (chunks, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(4))
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
            } else if case .dropped = continuation.yield(data) {
                handle.readabilityHandler = nil
                continuation.finish()
            }
        }
        // One consumer preserves pipe byte order and bounds queued output chunks.
        outputTask = Task {
            for await chunk in chunks { received(chunk, epoch: epoch) }
            if self.epoch == epoch { fail(AIWorkerFailure.exited) }
        }
        do { try Task.checkCancellation(); try child.run() } catch {
            cleanup()
            if error is CancellationError { throw error }
            throw AIWorkerFailure.exited
        }
        try await withCheckedThrowingContinuation { continuation in
            readyWaiter = continuation
            armTimeout(epoch: epoch)
        }
    }

    func generate(evidence: String, language: String) async throws -> AIWorkerAnswer {
        guard ready, !stopping, process?.isRunning == true, answerWaiter == nil else { throw AIWorkerFailure.busy }
        struct Request: Encodable { let id: String; let evidence: String; let language: String }
        let id = UUID().uuidString
        let data = try JSONEncoder().encode(Request(id: id, evidence: evidence, language: language))
        guard data.count < 32_768 else { throw AIWorkerFailure.protocolInvalid }
        return try await withCheckedThrowingContinuation { continuation in
            requestID = id
            answerWaiter = continuation
            armTimeout(epoch: epoch)
            do { try input?.fileHandleForWriting.write(contentsOf: data + Data([10])) }
            catch { fail(AIWorkerFailure.exited) }
        }
    }

    func stop() async throws {
        guard !stopping else { throw AIWorkerFailure.busy }
        stopping = true
        defer { stopping = false }
        fail(CancellationError())
        guard let child = process else { cleanup(); return }
        try? input?.fileHandleForWriting.close()
        if child.isRunning { child.terminate() }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while child.isRunning && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        let killDeadline = clock.now.advanced(by: .seconds(2))
        while child.isRunning && clock.now < killDeadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard !child.isRunning else { throw AIWorkerFailure.stopFailed }
        cleanup()
    }

    private func received(_ data: Data, epoch: UUID) {
        guard epoch == self.epoch, !stopping, process != nil else { return }
        guard !data.isEmpty else { return }
        guard buffer.count + data.count <= 32_768 else { fail(AIWorkerFailure.protocolInvalid); return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if !ready {
                struct Ready: Decodable { let event: String }
                guard (try? JSONDecoder().decode(Ready.self, from: line).event) == "ready" else {
                    fail(AIWorkerFailure.protocolInvalid)
                    return
                }
                ready = true
                timeoutTask?.cancel()
                readyWaiter?.resume()
                readyWaiter = nil
            } else {
                guard let answer = try? JSONDecoder().decode(AIWorkerAnswer.self, from: line),
                      answer.id == requestID, answerWaiter != nil,
                      answer.inputTokens >= 0, answer.inputTokens <= 2_048,
                      answer.outputTokens >= 0, answer.outputTokens <= 256,
                      answer.elapsedSeconds.isFinite, answer.elapsedSeconds >= 0 else {
                    fail(AIWorkerFailure.protocolInvalid)
                    return
                }
                timeoutTask?.cancel()
                if answer.error != nil { answerWaiter?.resume(throwing: AIWorkerFailure.runtimeFailed) }
                else { answerWaiter?.resume(returning: answer) }
                answerWaiter = nil
                requestID = nil
            }
        }
    }

    private func armTimeout(epoch: UUID) {
        timeoutTask?.cancel()
        timeoutTask = Task {
            do { try await Task.sleep(for: .seconds(120)) } catch { return }
            if self.epoch == epoch { fail(AIWorkerFailure.timeout) }
        }
    }

    private func exited(epoch: UUID) {
        guard self.epoch == epoch else { return }
        fail(AIWorkerFailure.exited)
        if !stopping { cleanup() }
    }

    private func fail(_ error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        readyWaiter?.resume(throwing: error)
        readyWaiter = nil
        answerWaiter?.resume(throwing: error)
        answerWaiter = nil
        requestID = nil
    }

    private func cleanup() {
        outputTask?.cancel()
        outputTask = nil
        output?.fileHandleForReading.readabilityHandler = nil
        try? output?.fileHandleForReading.close()
        try? input?.fileHandleForWriting.close()
        process?.terminationHandler = nil
        process = nil
        input = nil
        output = nil
        ready = false
        buffer.removeAll(keepingCapacity: false)
        epoch = UUID()
    }
}
