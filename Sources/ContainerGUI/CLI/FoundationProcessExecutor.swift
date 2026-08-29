import Foundation

final class FoundationProcessExecutor: CommandExecuting, @unchecked Sendable {
    private final class StreamState: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var timeoutTask: Task<Void, Never>?
        private var finished = false

        func install(process: Process, timeoutTask: Task<Void, Never>) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                timeoutTask.cancel()
                return
            }
            self.process = process
            self.timeoutTask = timeoutTask
            lock.unlock()
        }

        func finish(_ action: () -> Void) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            let timeoutTask = self.timeoutTask
            lock.unlock()
            timeoutTask?.cancel()
            action()
        }

        func cancel() {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            let process = self.process
            let timeoutTask = self.timeoutTask
            lock.unlock()
            timeoutTask?.cancel()
            if process?.isRunning == true { process?.terminate() }
        }
    }

    private actor OutputAccumulator {
        let limit: Int
        var stdout = Data()
        var stderr = Data()

        init(limit: Int) {
            self.limit = limit
        }

        func append(_ data: Data, toStdout: Bool) throws {
            guard stdout.count + stderr.count + data.count <= limit else {
                throw CommandExecutionError.outputLimitExceeded(limit: limit)
            }
            if toStdout { stdout.append(data) } else { stderr.append(data) }
        }

        func snapshot() -> (Data, Data) { (stdout, stderr) }
    }

    private enum ProcessEvent: Sendable {
        case stdoutEnded
        case stderrEnded
        case exited(Int32)
        case timeout
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        guard request.maximumOutputBytes > 0 else {
            throw CommandExecutionError.outputLimitExceeded(limit: request.maximumOutputBytes)
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.environment = request.environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let clock = ContinuousClock()
        let started = clock.now
        do {
            try process.run()
        } catch {
            throw CommandExecutionError.launchFailed
        }

        let accumulator = OutputAccumulator(limit: request.maximumOutputBytes)
        do {
            let exitCode = try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: ProcessEvent.self) { group in
                    group.addTask {
                        try await Self.drain(stdoutPipe.fileHandleForReading, accumulator: accumulator, toStdout: true)
                        return .stdoutEnded
                    }
                    group.addTask {
                        try await Self.drain(stderrPipe.fileHandleForReading, accumulator: accumulator, toStdout: false)
                        return .stderrEnded
                    }
                    group.addTask {
                        process.waitUntilExit()
                        return .exited(process.terminationStatus)
                    }
                    group.addTask {
                        try await Task.sleep(for: request.timeout)
                        return .timeout
                    }

                    var stdoutEnded = false
                    var stderrEnded = false
                    var status: Int32?
                    while let event = try await group.next() {
                        try Task.checkCancellation()
                        switch event {
                        case .stdoutEnded: stdoutEnded = true
                        case .stderrEnded: stderrEnded = true
                        case .exited(let code): status = code
                        case .timeout:
                            Self.terminate(process)
                            group.cancelAll()
                            throw CommandExecutionError.timedOut
                        }
                        if stdoutEnded, stderrEnded, let status {
                            group.cancelAll()
                            return status
                        }
                    }
                    throw CommandExecutionError.streamFailed
                }
            } onCancel: {
                Self.terminate(process)
            }

            if Task.isCancelled { throw CommandExecutionError.cancelled }
            let (stdout, stderr) = await accumulator.snapshot()
            return CommandResult(
                stdout: stdout,
                stderr: stderr,
                exitCode: exitCode,
                duration: started.duration(to: clock.now)
            )
        } catch is CancellationError {
            Self.terminate(process)
            throw CommandExecutionError.cancelled
        } catch let error as CommandExecutionError {
            Self.terminate(process)
            if Task.isCancelled { throw CommandExecutionError.cancelled }
            throw error
        } catch {
            Self.terminate(process)
            if Task.isCancelled { throw CommandExecutionError.cancelled }
            throw CommandExecutionError.streamFailed
        }
    }

    func stream(_ request: CommandRequest) -> AsyncThrowingStream<CommandStreamEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let state = StreamState()
            process.executableURL = request.executableURL
            process.arguments = request.arguments
            process.environment = request.environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let yieldEvent: @Sendable (CommandStreamEvent) -> Void = { event in
                if case .dropped = continuation.yield(event) {
                    continuation.yield(.dropped(1))
                }
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil }
                else { yieldEvent(.stdout(data)) }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil }
                else { yieldEvent(.stderr(data)) }
            }
            process.terminationHandler = { process in
                let remainingOut = stdoutPipe.fileHandleForReading.availableData
                let remainingError = stderrPipe.fileHandleForReading.availableData
                if !remainingOut.isEmpty { yieldEvent(.stdout(remainingOut)) }
                if !remainingError.isEmpty { yieldEvent(.stderr(remainingError)) }
                state.finish {
                    yieldEvent(.exited(process.terminationStatus))
                    continuation.finish()
                }
            }

            do {
                try process.run()
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(for: request.timeout)
                        state.finish {
                            if process.isRunning { process.terminate() }
                            continuation.finish(throwing: CommandExecutionError.timedOut)
                        }
                    } catch {}
                }
                state.install(process: process, timeoutTask: timeoutTask)
            } catch {
                state.finish { continuation.finish(throwing: CommandExecutionError.launchFailed) }
            }

            continuation.onTermination = { _ in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                state.cancel()
            }
        }
    }

    private static func drain(
        _ handle: FileHandle,
        accumulator: OutputAccumulator,
        toStdout: Bool
    ) async throws {
        while true {
            try Task.checkCancellation()
            let data = try handle.read(upToCount: 64 * 1024) ?? Data()
            if data.isEmpty { return }
            try await accumulator.append(data, toStdout: toStdout)
        }
    }

    private static func terminate(_ process: Process) {
        if process.isRunning {
            process.terminate()
        }
    }
}
