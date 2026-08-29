import Foundation
import Hummingbird

actor LogSessionLimiter {
    private let maximumSessions: Int
    private var tokens: Set<UUID> = []

    init(maximumSessions: Int = 8) { self.maximumSessions = maximumSessions }

    func acquire() throws -> UUID {
        guard tokens.count < maximumSessions else {
            throw ProblemDetail(code: .logSessionLimit)
        }
        let token = UUID()
        tokens.insert(token)
        return token
    }

    func release(_ token: UUID) { tokens.remove(token) }
}

enum LogEventStream {
    private struct TextPayload: Encodable { let text: String }
    private struct WarningPayload: Encodable { let message: String }
    private struct EndPayload: Encodable { let exitCode: Int32 }

    static func make(
        source: AsyncThrowingStream<CommandStreamEvent, Error>,
        keepaliveInterval: Duration = .seconds(15),
        bufferedChunks: Int = 64,
        onTermination: (@Sendable () async -> Void)? = nil
    ) -> AsyncThrowingStream<ByteBuffer, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(max(1, bufferedChunks))) { continuation in
            let producer = Task {
                let keepalive = Task {
                    while !Task.isCancelled {
                        try await Task.sleep(for: keepaliveInterval)
                        continuation.yield(ByteBuffer(string: ": keepalive\n\n"))
                    }
                }
                defer {
                    keepalive.cancel()
                    if let onTermination { Task { await onTermination() } }
                }
                do {
                    for try await event in source {
                        try Task.checkCancellation()
                        let buffer: ByteBuffer
                        switch event {
                        case .stdout(let data):
                            buffer = try encode(event: "log", payload: TextPayload(text: String(decoding: data, as: UTF8.self)))
                        case .stderr(let data):
                            buffer = try encode(event: "warning", payload: WarningPayload(message: String(decoding: data, as: UTF8.self)))
                        case .dropped(let count):
                            buffer = try encode(event: "warning", payload: WarningPayload(message: "已丢弃 \(count) 个日志分片"))
                        case .exited(let code):
                            continuation.yield(try encode(event: "end", payload: EndPayload(exitCode: code)))
                            continuation.finish()
                            return
                        }
                        if case .dropped = continuation.yield(buffer) {
                            continuation.yield(try encode(event: "warning", payload: WarningPayload(message: "浏览器读取较慢，部分日志已丢弃")))
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    private static func encode<T: Encodable>(event: String, payload: T) throws -> ByteBuffer {
        let data = try JSONEncoder.containerGUI.encode(payload)
        return ByteBuffer(string: "event: \(event)\ndata: \(String(decoding: data, as: UTF8.self))\n\n")
    }
}
