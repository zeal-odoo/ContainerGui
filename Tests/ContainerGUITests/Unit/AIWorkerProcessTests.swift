import Darwin
import Foundation
import XCTest

@testable import ContainerGUI

final class AIWorkerProcessTests: XCTestCase {
    func testAlreadyCancelledStartNeverCreatesChild() async throws {
        let worker = AIWorkerProcess(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf '{\"event\":\"ready\"}\\n'; while read line; do :; done"])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await worker.start(directory: URL(fileURLWithPath: "/unused"))
        }
        do { try await task.value; XCTFail("Cancelled start must fail") } catch {}
        let pid = await worker.pid()
        XCTAssertNil(pid)
        try await worker.stop()
    }

    func testStopKillsOwnedUnresponsiveChildAndWaitsForExit() async throws {
        let worker = AIWorkerProcess(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "trap '' TERM; printf '{\"event\":\"ready\"}\\n'; while read line; do :; done; while :; do :; done"])
        try await worker.start(directory: URL(fileURLWithPath: "/unused"))
        let pid = await worker.pid()
        XCTAssertNotNil(pid)
        try await worker.stop()
        let after = await worker.pid()
        XCTAssertNil(after)
        if let pid { XCTAssertNotEqual(kill(pid, 0), 0) }
    }

    func testMalformedWorkerOutputIsRejectedAndCanBeStopped() async throws {
        let worker = AIWorkerProcess(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf 'bad-json\\n'; while read line; do :; done"])
        do {
            try await worker.start(directory: URL(fileURLWithPath: "/unused"))
            XCTFail("Invalid protocol must fail")
        } catch {}
        try await worker.stop()
        let pid = await worker.pid()
        XCTAssertNil(pid)
    }
}
