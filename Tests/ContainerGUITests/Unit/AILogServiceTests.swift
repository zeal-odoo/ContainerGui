import Foundation
import XCTest

@testable import ContainerGUI

final class AILogServiceTests: XCTestCase {
    func testVeryLongUntrustedLinesAreBoundedWithoutRegexBacktracking() {
        let clock = ContinuousClock()
        let start = clock.now
        let evidence = AILogEvidence.prepare(String(repeating: "a", count: 1_000_000) + "\nConnection refused")
        XCTAssertTrue(evidence.contains("Connection refused"))
        XCTAssertLessThanOrEqual(evidence.utf8.count, 6_144)
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(2))
    }

    func testEvidenceRedactsSecretsAndKeepsBoundedTail() {
        let text = "Authorization: Bearer sensitive-token\nPASSWORD=hunter2\npostgres://alice:secret@db/test\n-----BEGIN PRIVATE KEY-----\nsecret-body\n-----END PRIVATE KEY-----\n" + String(repeating: "normal log\n", count: 1_000)
        let evidence = AILogEvidence.prepare(text)
        XCTAssertLessThanOrEqual(evidence.utf8.count, 6_144)
        XCTAssertFalse(evidence.contains("hunter2"))
        XCTAssertFalse(evidence.contains("secret-body"))
        let short = AILogEvidence.prepare("Authorization: Bearer sensitive-token\napi_key=secret-value\npostgres://alice:secret@db/test\n-----BEGIN RSA PRIVATE KEY-----\nsecret-body")
        XCTAssertFalse(short.contains("sensitive-token"))
        XCTAssertFalse(short.contains("secret-value"))
        XCTAssertFalse(short.contains("alice:secret"))
        XCTAssertFalse(short.contains("secret-body"))
        let nested = AILogEvidence.prepare(#"{"message":"connection failed password=clear-secret","level":"error"}"#)
        XCTAssertFalse(nested.contains("clear-secret"))
    }

    func testOffDoesNotLoadOrReadLogsAndDisableWaitsForExit() async throws {
        let worker = FakeAILogWorker()
        let reader = FakeAILogReader()
        let service = service(worker: worker, reader: reader)
        let initial = await service.status()
        XCTAssertEqual(initial.phase, "off")
        XCTAssertFalse(initial.enabled)
        await service.analyse()
        let reads = await reader.reads
        XCTAssertEqual(reads, 0)
        try await service.enable(containerID: "demo", language: "zh")
        try await waitFor(service, phase: "ready")
        await service.analyse()
        try await waitForResult(service)
        let result = await service.status().result
        XCTAssertEqual(result?.text, "Check the database connection.")
        try await service.disable()
        let final = await service.status()
        XCTAssertFalse(final.enabled)
        XCTAssertEqual(final.phase, "off")
        XCTAssertNil(final.workerPID)
        XCTAssertNil(final.result)
        let stops = await worker.stops
        XCTAssertGreaterThan(stops, 0)
    }

    func testDisableWhileLoadingCannotReturnToReady() async throws {
        let worker = FakeAILogWorker(loadDelay: .milliseconds(150))
        let service = service(worker: worker)
        try await service.enable(containerID: "demo", language: "en")
        try await Task.sleep(for: .milliseconds(20))
        try await service.disable()
        try await Task.sleep(for: .milliseconds(180))
        let state = await service.status()
        XCTAssertEqual(state.phase, "off")
        XCTAssertNil(state.workerPID)
        XCTAssertFalse(state.enabled)
    }

    func testLeaseExpiresWithoutStatusReadRenewal() async throws {
        let service = service(leaseSeconds: 0.05)
        try await service.enable(containerID: "demo", language: "zh")
        try await waitFor(service, phase: "ready")
        for _ in 0..<5 {
            _ = await service.status()
            try await Task.sleep(for: .milliseconds(40))
        }
        try await waitFor(service, phase: "off")
    }

    func testInvalidTargetAndMemoryPressureDoNotStartWorker() async throws {
        let worker = FakeAILogWorker()
        let service = service(worker: worker, memoryAvailable: false)
        for name in ["../demo", "demo"] {
            do {
                try await service.enable(containerID: name, language: "en")
                XCTFail("Must reject invalid target or insufficient memory")
            } catch {}
        }
        let starts = await worker.starts
        XCTAssertEqual(starts, 0)
    }

    func testDuplicateSnapshotDoesNotGenerateAgain() async throws {
        let worker = FakeAILogWorker()
        let service = service(worker: worker)
        try await service.enable(containerID: "demo", language: "zh")
        try await waitFor(service, phase: "ready")
        await service.analyse()
        try await waitForResult(service)
        await service.analyse()
        try await Task.sleep(for: .milliseconds(30))
        let generations = await worker.generations
        XCTAssertEqual(generations, 1)
        try await service.disable()
    }

    func testDisableDuringGenerationDropsResultAndAllowsRepeatedToggles() async throws {
        let worker = FakeAILogWorker(generationDelay: .milliseconds(200))
        let service = service(worker: worker)
        for _ in 0..<3 {
            try await service.enable(containerID: "demo", language: "en")
            try await waitFor(service, phase: "ready")
            await service.analyse()
            try await Task.sleep(for: .milliseconds(20))
            try await service.disable()
            let state = await service.status()
            XCTAssertEqual(state.phase, "off")
            XCTAssertNil(state.result)
            XCTAssertNil(state.workerPID)
        }
    }

    func testEmptySnapshotClearsOldResultAndShowsNoLogs() async throws {
        let reader = FakeAILogReader()
        let service = service(reader: reader)
        try await service.enable(containerID: "demo", language: "en")
        try await waitFor(service, phase: "ready")
        await service.analyse()
        try await waitForResult(service)
        await reader.setText("")
        await service.analyse()
        try await waitFor(service, phase: "ready")
        let empty = await service.status()
        XCTAssertNil(empty.result)
        XCTAssertEqual(empty.error, "no_recent_logs")
        await reader.setText("Database connection refused\nPASSWORD=secret")
        await service.analyse()
        try await waitForResult(service)
        try await service.disable()
    }

    func testFailedStopNeverReportsOff() async throws {
        let worker = FakeAILogWorker(failStop: true)
        let service = service(worker: worker)
        try await service.enable(containerID: "demo", language: "en")
        try await waitFor(service, phase: "ready")
        do { try await service.disable(); XCTFail("Stop must fail") } catch {}
        let state = await service.status()
        XCTAssertEqual(state.phase, "error")
        XCTAssertNotNil(state.workerPID)
        XCTAssertEqual(state.error, "worker_stop_failed")
    }

    private func service(worker: FakeAILogWorker = FakeAILogWorker(), reader: FakeAILogReader = FakeAILogReader(), memoryAvailable: Bool = true, leaseSeconds: Double = 60) -> AILogService {
        AILogService(reader: reader, history: AILogHistoryStore(directory: try! historyDirectory()), store: FakeAIModelStore(), worker: worker, memoryAvailable: { memoryAvailable }, leaseSeconds: leaseSeconds, minimumInterval: 0)
    }

    func testCompletedHistorySurvivesDisableWithoutFurtherModelOrLogReads() async throws {
        let directory = try historyDirectory()
        let history = AILogHistoryStore(directory: directory)
        let reader = FakeAILogReader()
        let worker = FakeAILogWorker()
        let service = AILogService(reader: reader, history: history, store: FakeAIModelStore(), worker: worker, memoryAvailable: { true }, minimumInterval: 0)
        try await service.enable(containerID: "demo", language: "en")
        try await waitFor(service, phase: "ready")
        await service.analyse()
        try await waitForResult(service)
        try await waitFor(service, phase: "ready")
        await service.analyse()
        try await waitFor(service, phase: "ready")
        try await service.disable()
        let reads = await reader.reads
        let starts = await worker.starts
        let page = try await AILogHistoryStore(directory: directory).list(containerID: "demo", page: 1)
        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.items.first?.language, "en")
        XCTAssertFalse(page.items[0].result.evidence.contains("PASSWORD=secret"))
        let finalReads = await reader.reads
        let finalStarts = await worker.starts
        XCTAssertEqual(finalReads, reads)
        XCTAssertEqual(finalStarts, starts)
    }

    func testCancelledAnalysisNeverBecomesHistory() async throws {
        let history = AILogHistoryStore(directory: try historyDirectory())
        let service = AILogService(reader: FakeAILogReader(), history: history, store: FakeAIModelStore(), worker: FakeAILogWorker(generationDelay: .milliseconds(200)), memoryAvailable: { true })
        try await service.enable(containerID: "demo", language: "en")
        try await waitFor(service, phase: "ready")
        await service.analyse()
        try await Task.sleep(for: .milliseconds(20))
        try await service.disable()
        let page = try await history.list(containerID: "demo", page: 1)
        XCTAssertEqual(page.total, 0)
    }

    func testSaveFailurePreservesResultAndDoesNotStopWorker() async throws {
        let directory = try historyDirectory()
        try Data("not a directory".utf8).write(to: directory)
        let service = AILogService(reader: FakeAILogReader(), history: AILogHistoryStore(directory: directory), store: FakeAIModelStore(), worker: FakeAILogWorker(), memoryAvailable: { true })
        try await service.enable(containerID: "demo", language: "en")
        try await waitFor(service, phase: "ready")
        await service.analyse()
        try await waitForResult(service)
        try await waitFor(service, phase: "ready")
        let state = await service.status()
        XCTAssertEqual(state.historyError, "history_save_failed")
        XCTAssertNil(state.historyRecordId)
        XCTAssertTrue(state.enabled)
        XCTAssertNotNil(state.result)
        try await service.disable()
    }

    private func waitFor(_ service: AILogService, phase: String) async throws {
        for _ in 0..<100 {
            if await service.status().phase == phase { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Did not reach \(phase)")
    }

    private func waitForResult(_ service: AILogService) async throws {
        for _ in 0..<100 {
            if await service.status().result != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("No analysis result")
    }
}

actor FakeAIModelStore: AIModelStoring {
    func status() async -> AIModelInstallation { .init(name: "Qwen3-1.7B", installed: true, downloading: false, downloadedBytes: 1, totalBytes: 1) }
    func install() async throws {}
    func cancel() async {}
    func verifiedDirectory() async throws -> URL { URL(fileURLWithPath: "/test-model") }
}

actor FakeAILogReader: ContainerLogReading {
    var reads = 0
    var text = "Database connection refused\nPASSWORD=secret"
    func setText(_ text: String) { self.text = text }
    func recentLogs(id: String, tail: Int) async throws -> RecentLogs {
        reads += 1
        return RecentLogs(containerID: id, text: text, truncated: false, observedAt: Date())
    }
    func followLogs(id: String, tail: Int) async throws -> AsyncThrowingStream<CommandStreamEvent, Error> { throw CancellationError() }
}

actor FakeAILogWorker: AIWorkerRunning {
    let loadDelay: Duration
    let failStop: Bool
    let generationDelay: Duration
    var starts = 0
    var stops = 0
    var generations = 0
    var running = false
    init(loadDelay: Duration = .zero, failStop: Bool = false, generationDelay: Duration = .zero) {
        self.loadDelay = loadDelay; self.failStop = failStop; self.generationDelay = generationDelay
    }
    func start(directory: URL) async throws {
        starts += 1
        running = true
        try await Task.sleep(for: loadDelay)
    }
    func generate(evidence: String, language: String) async throws -> AIWorkerAnswer {
        generations += 1
        try await Task.sleep(for: generationDelay)
        return .init(id: "test", text: "Check the database connection.", inputTokens: 50, outputTokens: 8, elapsedSeconds: 0.01, error: nil)
    }
    func stop() async throws {
        stops += 1
        if failStop { throw AIWorkerFailure.stopFailed }
        running = false
    }
    func pid() async -> Int32? { running ? 123 : nil }
}
