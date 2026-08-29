import Foundation
import Darwin
import XCTest

@testable import ContainerGUI

final class FoundationProcessExecutorTests: XCTestCase {
    private let executor = FoundationProcessExecutor()

    func testDrainsStdoutAndStderrAndCapturesExit() async throws {
        let script = "i=0; while [ $i -lt 2000 ]; do printf 'out-%04d\\n' $i; printf 'err-%04d\\n' $i >&2; i=$((i+1)); done; exit 7"
        let result = try await executor.run(
            CommandRequest(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", script],
                timeout: .seconds(5),
                maximumOutputBytes: 1_000_000
            )
        )

        XCTAssertEqual(result.exitCode, 7)
        XCTAssertTrue(result.stdoutString.contains("out-1999"))
        XCTAssertTrue(result.stderrString.contains("err-1999"))
        XCTAssertGreaterThanOrEqual(result.duration, .zero)
    }

    func testPreservesInvalidUTF8Bytes() async throws {
        let result = try await executor.run(
            CommandRequest(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf '\\377\\376ok'"],
                timeout: .seconds(2),
                maximumOutputBytes: 64
            )
        )

        XCTAssertTrue(result.stdout.starts(with: [0xff, 0xfe]))
        XCTAssertTrue(result.stdoutString.contains("��ok"))
    }

    func testTimesOutAndTerminatesChild() async {
        do {
            _ = try await executor.run(
                CommandRequest(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "sleep 5"],
                    timeout: .milliseconds(100),
                    maximumOutputBytes: 64
                )
            )
            XCTFail("Expected timeout")
        } catch let error as CommandExecutionError {
            XCTAssertEqual(error, .timedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancellationTerminatesChild() async {
        let executor = self.executor
        let task = Task {
            try await executor.run(
                CommandRequest(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "sleep 5"],
                    timeout: .seconds(10),
                    maximumOutputBytes: 64
                )
            )
        }
        try? await Task.sleep(for: .milliseconds(80))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch let error as CommandExecutionError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConcurrentFastExitsRemainObservable() async throws {
        let executor = self.executor
        try await withThrowingTaskGroup(of: CommandResult.self) { group in
            for _ in 0..<64 {
                group.addTask {
                    try await executor.run(
                        CommandRequest(
                            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                            arguments: [],
                            timeout: .seconds(2),
                            maximumOutputBytes: 64
                        )
                    )
                }
            }
            for try await result in group {
                XCTAssertEqual(result.exitCode, 0)
            }
        }
    }

    func testRejectsCombinedOutputOverLimit() async {
        do {
            _ = try await executor.run(
                CommandRequest(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "printf '12345678'; printf 'abcdefgh' >&2"],
                    timeout: .seconds(2),
                    maximumOutputBytes: 12
                )
            )
            XCTFail("Expected output limit")
        } catch let error as CommandExecutionError {
            XCTAssertEqual(error, .outputLimitExceeded(limit: 12))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStreamCancellationTerminatesChildProcess() async throws {
        let stream = executor.stream(
            CommandRequest(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf '%d\\n' $$; exec /bin/sleep 5"],
                timeout: .seconds(10),
                maximumOutputBytes: 64
            )
        )
        let probe = StreamPIDProbe()
        let consumer = Task {
            for try await event in stream {
                if case .stdout(let data) = event,
                   let pid = Int32(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) {
                    await probe.record(pid)
                }
            }
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while await probe.pid == nil, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let recordedPID = await probe.pid
        let pid = try XCTUnwrap(recordedPID)

        consumer.cancel()
        _ = try? await consumer.value

        let terminationDeadline = clock.now.advanced(by: .seconds(1))
        while kill(pid, 0) == 0, clock.now < terminationDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotEqual(kill(pid, 0), 0, "stream cancellation must terminate the CLI child")
    }
}

private actor StreamPIDProbe {
    private(set) var pid: Int32?
    func record(_ pid: Int32) { self.pid = pid }
}
