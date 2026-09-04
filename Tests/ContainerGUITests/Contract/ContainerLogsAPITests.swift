import Foundation
import Hummingbird
import HummingbirdTesting
import XCTest

@testable import ContainerGUI

final class ContainerLogsAPITests: XCTestCase {
    func testRecentLogsAndSSEEvents() async throws {
        let reader = StubLogReader()
        let router = Router()
        router.middlewares.add(ErrorMiddleware())
        ContainerControlRoutes.registerLogs(on: router, reader: reader, limiter: LogSessionLimiter(maximumSessions: 8))
        let app = Application(router: router)

        try await app.testLocal { client in
            try await client.execute(uri: "/api/v1/containers/demo/logs?tail=25", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let logs = try JSONDecoder.containerGUI.decode(RecentLogs.self, from: response.body)
                XCTAssertEqual(logs.containerID, "demo")
                XCTAssertEqual(logs.text, "recent line\n")
            }
            try await client.execute(uri: "/api/v1/containers/demo/logs/stream?tail=25", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers[.contentType], "text/event-stream; charset=utf-8")
                let text = String(buffer: response.body)
                XCTAssertTrue(text.contains("event: log"))
                XCTAssertTrue(text.contains("�log-line"))
                XCTAssertTrue(text.contains("event: warning"))
                XCTAssertTrue(text.contains("event: end"))
            }
        }
    }

    func testKeepaliveBackpressureLimitAndDisconnectCancellation() async throws {
        let source = AsyncThrowingStream<CommandStreamEvent, Error> { continuation in
            let task = Task {
                for index in 0..<200 {
                    continuation.yield(.stdout(Data("line-\(index)\n".utf8)))
                }
                try? await Task.sleep(for: .milliseconds(80))
                continuation.yield(.exited(0))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        let output = LogEventStream.make(
            source: source,
            keepaliveInterval: .milliseconds(20),
            bufferedChunks: 4
        )
        var iterator = output.makeAsyncIterator()
        _ = try await iterator.next()
        iterator = output.makeAsyncIterator()
        while let chunk = try await iterator.next() {
            let text = String(buffer: chunk)
            if text.contains("keepalive") || text.contains("event: warning") { break }
        }

        let limiter = LogSessionLimiter(maximumSessions: 8)
        var tokens: [UUID] = []
        for _ in 0..<8 { tokens.append(try await limiter.acquire()) }
        do {
            _ = try await limiter.acquire()
            XCTFail("Expected log-session limit")
        } catch let problem as ProblemDetail {
            XCTAssertEqual(problem.status, 429)
        }
        for token in tokens { await limiter.release(token) }

        let probe = CancellationProbe()
        let disconnectSource = AsyncThrowingStream<CommandStreamEvent, Error> { continuation in
            continuation.yield(.stdout(Data("connected\n".utf8)))
            continuation.onTermination = { _ in Task { await probe.markCancelled() } }
        }
        let disconnectOutput = LogEventStream.make(source: disconnectSource, keepaliveInterval: .seconds(15))
        let consumer = Task {
            for try await _ in disconnectOutput {
                try Task.checkCancellation()
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        consumer.cancel()
        _ = try? await consumer.value
        try await Task.sleep(for: .milliseconds(80))
        let wasCancelled = await probe.cancelled
        XCTAssertTrue(wasCancelled)
    }
}

private actor StubLogReader: ContainerLogReading {
    func recentLogs(id: String, tail _: Int) async throws -> RecentLogs {
        RecentLogs(containerID: id, text: "recent line\n", truncated: false, observedAt: Date())
    }

    func followLogs(id _: String, tail _: Int) async throws -> AsyncThrowingStream<CommandStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.stdout(Data([0xff]) + Data("log-line\n".utf8)))
            continuation.yield(.stderr(Data("sanitized stderr".utf8)))
            continuation.yield(.exited(0))
            continuation.finish()
        }
    }
}

private actor CancellationProbe {
    private(set) var cancelled = false
    func markCancelled() { cancelled = true }
}
