import Foundation
import XCTest

@testable import ContainerGUI

final class ContainerMetricsTests: XCTestCase {
    private let firstObservedAt = Date(timeIntervalSince1970: 1_787_987_200)

    func testParserAcceptsUnknownFieldsAndEmptySnapshot() throws {
        let first = try CLIOutputParser.parseContainerResourceSamples(
            data: fixture("stats-first.json"),
            observedAt: firstObservedAt
        )
        let empty = try CLIOutputParser.parseContainerResourceSamples(
            data: fixture("stats-empty.json"),
            observedAt: firstObservedAt
        )

        XCTAssertEqual(first.samples.count, 1)
        XCTAssertEqual(first.samples[0].containerID, "demo-running")
        XCTAssertEqual(first.samples[0].cpuUsageUsec, 1_000_000)
        XCTAssertEqual(first.samples[0].memoryUsageBytes, 1_073_741_824)
        XCTAssertEqual(first.samples[0].memoryLimitBytes, 4_294_967_296)
        XCTAssertEqual(first.observedAt, firstObservedAt)
        XCTAssertTrue(empty.samples.isEmpty)
    }

    func testParserRejectsNegativeMissingAndDuplicateIdentifiers() throws {
        XCTAssertThrowsError(
            try CLIOutputParser.parseContainerResourceSamples(
                data: fixture("stats-invalid-negative.json"),
                observedAt: firstObservedAt
            )
        )
        XCTAssertThrowsError(
            try CLIOutputParser.parseContainerResourceSamples(
                data: fixture("stats-missing-id.json"),
                observedAt: firstObservedAt
            )
        )
        let duplicate = Data("""
        [
          {"id":"same","cpuUsageUsec":1,"memoryUsageBytes":1,"memoryLimitBytes":2},
          {"id":"same","cpuUsageUsec":2,"memoryUsageBytes":1,"memoryLimitBytes":2}
        ]
        """.utf8)
        XCTAssertThrowsError(
            try CLIOutputParser.parseContainerResourceSamples(data: duplicate, observedAt: firstObservedAt)
        )
    }

    func testParsesRootFilesystemCapacityAsExactBytes() throws {
        let usage = try CLIOutputParser.parseContainerRootFilesystemUsage(
            data: fixture("df-root-valid.txt")
        )

        XCTAssertEqual(usage.state, .ready)
        XCTAssertEqual(usage.capacityBytes, 528_432_952 * 1_024)
        XCTAssertEqual(usage.usedBytes, 2_498_132 * 1_024)
        XCTAssertEqual(usage.availableBytes, 525_918_436 * 1_024)
        XCTAssertEqual(
            try XCTUnwrap(usage.usagePercent),
            Double(2_498_132) / Double(528_432_952) * 100,
            accuracy: 0.000_001
        )
    }

    func testRejectsInvalidRootFilesystemCapacity() throws {
        for data in [
            try fixture("df-root-invalid.txt"),
            Data("Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/vdb 10 11 0 110% /\n".utf8),
            Data("Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/vdb 18014398509481984 1 1 1% /\n".utf8),
            Data("not a filesystem table\n".utf8),
        ] {
            XCTAssertThrowsError(try CLIOutputParser.parseContainerRootFilesystemUsage(data: data))
        }
    }

    func testFirstAndContinuousSamplesCalculateCPUAndMemory() async throws {
        let sampler = ContainerMetricsSampler()
        let firstBatch = batch(cpu: 1_000_000, memory: 1_073_741_824, limit: 4_294_967_296, offset: 0)
        let secondBatch = batch(cpu: 1_250_000, memory: 1_610_612_736, limit: 4_294_967_296, offset: 5)
        let first = try await sampler.snapshot { firstBatch }
        let second = try await sampler.snapshot { secondBatch }

        let firstUsage = try XCTUnwrap(first.items.first)
        XCTAssertEqual(firstUsage.cpuState, .sampling)
        XCTAssertNil(firstUsage.cpuPercent)
        XCTAssertEqual(try XCTUnwrap(firstUsage.memoryPercent), 25, accuracy: 0.0001)
        let secondUsage = try XCTUnwrap(second.items.first)
        XCTAssertEqual(secondUsage.cpuState, .ready)
        XCTAssertEqual(try XCTUnwrap(secondUsage.cpuPercent), 5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(secondUsage.memoryPercent), 37.5, accuracy: 0.0001)
    }

    func testMultiCoreCPUIsNotClampedAndCounterResetResamples() async throws {
        let sampler = ContainerMetricsSampler()
        let firstBatch = batch(cpu: 1_000_000, memory: 1, limit: 2, offset: 0)
        let multiCoreBatch = batch(cpu: 9_000_000, memory: 1, limit: 2, offset: 5)
        let resetBatch = batch(cpu: 100, memory: 1, limit: 2, offset: 10)
        _ = try await sampler.snapshot { firstBatch }
        let multiCore = try await sampler.snapshot { multiCoreBatch }
        let reset = try await sampler.snapshot { resetBatch }

        XCTAssertEqual(try XCTUnwrap(multiCore.items.first?.cpuPercent), 160, accuracy: 0.0001)
        XCTAssertEqual(reset.items.first?.cpuState, .sampling)
        XCTAssertNil(reset.items.first?.cpuPercent)
    }

    func testZeroMemoryLimitAvoidsNonFinitePercentage() async throws {
        let batch = batch(cpu: 1, memory: 512, limit: 0, offset: 0)
        let snapshot = try await ContainerMetricsSampler().snapshot { batch }

        XCTAssertEqual(snapshot.items.first?.memoryUsageBytes, 512)
        XCTAssertEqual(snapshot.items.first?.memoryLimitBytes, 0)
        XCTAssertNil(snapshot.items.first?.memoryPercent)
    }

    func testMissingContainerEvictsPreviousSample() async throws {
        let sampler = ContainerMetricsSampler()
        let first = ContainerResourceSampleBatch(
            samples: [
                sample(id: "a", cpu: 1, offset: 0),
                sample(id: "b", cpu: 1, offset: 0),
            ],
            observedAt: firstObservedAt
        )
        let second = ContainerResourceSampleBatch(
            samples: [sample(id: "a", cpu: 2, offset: 5)],
            observedAt: firstObservedAt.addingTimeInterval(5)
        )
        let third = ContainerResourceSampleBatch(
            samples: [sample(id: "b", cpu: 3, offset: 10)],
            observedAt: firstObservedAt.addingTimeInterval(10)
        )
        _ = try await sampler.snapshot { first }
        _ = try await sampler.snapshot { second }
        let returned = try await sampler.snapshot { third }

        XCTAssertEqual(returned.items.first?.containerID, "b")
        XCTAssertEqual(returned.items.first?.cpuState, .sampling)
    }

    func testOverlappingRequestsShareOneStatsLoad() async throws {
        let sampler = ContainerMetricsSampler()
        let probe = MetricsLoadProbe()
        let batch = batch(cpu: 1, memory: 1, limit: 2, offset: 0)

        async let first = sampler.snapshot { try await probe.load(batch) }
        async let second = sampler.snapshot { try await probe.load(batch) }
        let snapshots = try await (first, second)

        XCTAssertEqual(snapshots.0, snapshots.1)
        let invocationCount = await probe.invocationCount
        XCTAssertEqual(invocationCount, 1)
    }

    func testCancelledWaiterDoesNotCancelSharedStatsLoad() async throws {
        let sampler = ContainerMetricsSampler()
        let probe = MetricsLoadProbe()
        let batch = batch(cpu: 1, memory: 1, limit: 2, offset: 0)
        let first = Task {
            try await sampler.snapshot { try await probe.load(batch) }
        }
        try await Task.sleep(for: .milliseconds(10))
        first.cancel()

        let second = try await sampler.snapshot { try await probe.load(batch) }
        _ = try? await first.value

        XCTAssertEqual(second.items.first?.containerID, "demo-running")
        let invocationCount = await probe.invocationCount
        XCTAssertEqual(invocationCount, 1)
    }

    func testCLIUsesFixedReadOnlyStatsCommand() async throws {
        let executor = MetricsCommandExecutor(results: [
            CommandResult(
                stdout: Data("container CLI version 1.3.1".utf8),
                stderr: Data(), exitCode: 0, duration: .zero
            ),
            CommandResult(
                stdout: try fixture("stats-first.json"),
                stderr: Data(), exitCode: 0, duration: .zero
            ),
            CommandResult(
                stdout: try fixture("df-root-valid.txt"),
                stderr: Data(), exitCode: 0, duration: .zero
            ),
        ])
        let client = ContainerCLIClient(
            executor: executor,
            executableURL: URL(fileURLWithPath: "/fixture/container")
        )

        let snapshot = try await client.containerMetrics()

        XCTAssertEqual(snapshot.items.first?.cpuState, .sampling)
        XCTAssertEqual(snapshot.items.first?.rootFilesystem.state, .ready)
        let requests = await executor.requests
        XCTAssertEqual(requests.map(\.arguments), [
            ["--version"],
            ["stats", "--no-stream", "--format", "json"],
            ["exec", "demo-running", "df", "-kP", "/"],
        ])
        XCTAssertFalse(requests.flatMap(\.arguments).contains("--all"))
        XCTAssertTrue(requests.allSatisfy { $0.executableURL.path == "/fixture/container" })
    }

    func testFilesystemFailureIsIsolatedFromOtherContainerMetrics() async throws {
        let executor = FilesystemMetricsCommandExecutor(validFilesystem: try fixture("df-root-valid.txt"))
        let client = ContainerCLIClient(
            executor: executor,
            executableURL: URL(fileURLWithPath: "/fixture/container")
        )

        let snapshot = try await client.containerMetrics()
        let byID = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.containerID, $0) })

        XCTAssertEqual(byID["demo-ready"]?.rootFilesystem.state, .ready)
        XCTAssertEqual(byID["demo-unavailable"]?.rootFilesystem.state, .unavailable)
        XCTAssertNil(byID["demo-unavailable"]?.rootFilesystem.capacityBytes)
        XCTAssertEqual(snapshot.items.count, 2)
    }

    private func batch(
        cpu: UInt64,
        memory: UInt64,
        limit: UInt64,
        offset: TimeInterval
    ) -> ContainerResourceSampleBatch {
        let observedAt = firstObservedAt.addingTimeInterval(offset)
        return ContainerResourceSampleBatch(
            samples: [
                ContainerResourceSample(
                    containerID: "demo-running",
                    cpuUsageUsec: cpu,
                    memoryUsageBytes: memory,
                    memoryLimitBytes: limit,
                    observedAt: observedAt
                )
            ],
            observedAt: observedAt
        )
    }

    private func sample(id: String, cpu: UInt64, offset: TimeInterval) -> ContainerResourceSample {
        ContainerResourceSample(
            containerID: id,
            cpuUsageUsec: cpu,
            memoryUsageBytes: 1,
            memoryLimitBytes: 2,
            observedAt: firstObservedAt.addingTimeInterval(offset)
        )
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "Fixtures/CLI/1.3.1/metrics"
            )
        )
        return try Data(contentsOf: url)
    }
}

private actor MetricsLoadProbe {
    private(set) var invocationCount = 0

    func load(_ batch: ContainerResourceSampleBatch) async throws -> ContainerResourceSampleBatch {
        invocationCount += 1
        try await Task.sleep(for: .milliseconds(50))
        return batch
    }
}

private actor MetricsCommandExecutor: CommandExecuting {
    private var results: [CommandResult]
    private(set) var requests: [CommandRequest] = []

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        guard !results.isEmpty else { throw CommandExecutionError.streamFailed }
        return results.removeFirst()
    }
}

private actor FilesystemMetricsCommandExecutor: CommandExecuting {
    private let validFilesystem: Data

    init(validFilesystem: Data) {
        self.validFilesystem = validFilesystem
    }

    func run(_ request: CommandRequest) async throws -> CommandResult {
        let result: (Data, Int32)
        switch request.arguments {
        case ["--version"]:
            result = (Data("container CLI version 1.3.1".utf8), 0)
        case ["stats", "--no-stream", "--format", "json"]:
            result = (Data("""
            [
              {"id":"demo-ready","cpuUsageUsec":1,"memoryUsageBytes":1,"memoryLimitBytes":2},
              {"id":"demo-unavailable","cpuUsageUsec":1,"memoryUsageBytes":1,"memoryLimitBytes":2}
            ]
            """.utf8), 0)
        case ["exec", "demo-ready", "df", "-kP", "/"]:
            result = (validFilesystem, 0)
        case ["exec", "demo-unavailable", "df", "-kP", "/"]:
            result = (Data(), 127)
        default:
            throw CommandExecutionError.streamFailed
        }
        return CommandResult(stdout: result.0, stderr: Data(), exitCode: result.1, duration: .zero)
    }
}
