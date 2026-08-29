import Foundation

struct CommandRequest: Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]?
    let timeout: Duration
    let maximumOutputBytes: Int

    init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: Duration,
        maximumOutputBytes: Int
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.timeout = timeout
        self.maximumOutputBytes = maximumOutputBytes
    }
}

struct CommandResult: Sendable, Equatable {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32
    let duration: Duration

    var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

enum CommandStreamEvent: Sendable, Equatable {
    case stdout(Data)
    case stderr(Data)
    case dropped(Int)
    case exited(Int32)
}

enum CommandExecutionError: Error, Equatable, Sendable {
    case launchFailed
    case timedOut
    case cancelled
    case outputLimitExceeded(limit: Int)
    case streamFailed
}

protocol CommandExecuting: Sendable {
    func run(_ request: CommandRequest) async throws -> CommandResult
    func stream(_ request: CommandRequest) -> AsyncThrowingStream<CommandStreamEvent, Error>
}

extension CommandExecuting {
    func stream(_ request: CommandRequest) -> AsyncThrowingStream<CommandStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await run(request)
                    if !result.stdout.isEmpty { continuation.yield(.stdout(result.stdout)) }
                    if !result.stderr.isEmpty { continuation.yield(.stderr(result.stderr)) }
                    continuation.yield(.exited(result.exitCode))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
