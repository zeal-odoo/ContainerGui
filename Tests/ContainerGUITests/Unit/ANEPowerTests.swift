import Foundation
import XCTest

@testable import ContainerGUI

final class ANEPowerTests: XCTestCase {
    func testFirstSampleThenEnergyDifferenceProducesWatts() async throws {
        let fixture = ANEPowerFixture()
        let sampler = fixture.sampler()
        let first = await sampler.snapshot()
        XCTAssertEqual(first.state, .sampling)
        XCTAssertNil(first.watts)
        XCTAssertNil(first.sampleSeconds)
        XCTAssertNil(first.reason)

        fixture.set(time: 5, channels: [.init(name: "ANE", unit: "mJ", value: 12_500)])
        let ready = await sampler.snapshot()
        XCTAssertEqual(ready.state, .ready)
        XCTAssertEqual(try XCTUnwrap(ready.watts), 2.5, accuracy: 0.000_001)
        XCTAssertEqual(ready.sampleSeconds, 5)
        XCTAssertEqual(ready.observedAt, ANEPowerFixture.date)
    }

    func testAllSupportedUnitsAndRealZeroArePreserved() async throws {
        for (unit, value) in [("J", Int64(2)), ("mJ", 2_000), ("uJ", 2_000_000), ("nJ", 2_000_000_000)] {
            let fixture = ANEPowerFixture(channels: [.init(name: "ANE", unit: unit, value: 0)])
            let sampler = fixture.sampler()
            _ = await sampler.snapshot()
            fixture.set(time: 2, channels: [.init(name: "ANE", unit: unit, value: value)])
            let active = await sampler.snapshot()
            XCTAssertEqual(try XCTUnwrap(active.watts), 1, accuracy: 0.000_001)
            fixture.set(time: 4, channels: [.init(name: "ANE", unit: unit, value: value)])
            let idle = await sampler.snapshot()
            XCTAssertEqual(idle.state, .ready)
            XCTAssertEqual(idle.watts, 0)
        }
    }

    func testUniqueNumberedChannelsSumAndIgnoreOrder() async throws {
        let fixture = ANEPowerFixture(channels: [
            .init(name: "ANE0", unit: "mJ", value: 100),
            .init(name: "ANE1", unit: "uJ", value: 1_000),
        ])
        let sampler = fixture.sampler()
        _ = await sampler.snapshot()
        fixture.set(time: 2, channels: [
            .init(name: "ANE1", unit: "uJ", value: 4_001_000),
            .init(name: "ANE0", unit: "mJ", value: 2_100),
        ])
        let result = await sampler.snapshot()
        XCTAssertEqual(try XCTUnwrap(result.watts), 3, accuracy: 0.000_001)
    }

    func testSubtractsIntegersBeforeConvertingLargeCumulativeCounts() async throws {
        let fixture = ANEPowerFixture(channels: [.init(name: "ANE", unit: "mJ", value: Int64.max - 1)])
        let sampler = fixture.sampler()
        _ = await sampler.snapshot()
        fixture.set(time: 1, channels: [.init(name: "ANE", unit: "mJ", value: Int64.max)])
        let result = await sampler.snapshot()
        XCTAssertEqual(try XCTUnwrap(result.watts), 0.001, accuracy: 0.000_000_1)
    }

    func testOneSecondCacheSerializesConcurrentWindows() async {
        let fixture = ANEPowerFixture()
        let sampler = fixture.sampler()
        _ = await sampler.snapshot()
        fixture.set(time: 0.99)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 { group.addTask { _ = await sampler.snapshot() } }
        }
        XCTAssertEqual(fixture.readCount, 1)
        fixture.set(time: 1, channels: [.init(name: "ANE", unit: "mJ", value: 1_000)])
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 { group.addTask { _ = await sampler.snapshot() } }
        }
        XCTAssertEqual(fixture.readCount, 2)
        let ready = await sampler.snapshot()
        XCTAssertEqual(ready.watts, 1)
    }

    func testSampleIntervalUsesReadCompletionTime() async {
        let fixture = ANEPowerFixture(readDuration: 2)
        let sampler = fixture.sampler()
        _ = await sampler.snapshot()
        fixture.set(time: 3, channels: [.init(name: "ANE", unit: "mJ", value: 1_000)])
        let result = await sampler.snapshot()
        XCTAssertEqual(result.sampleSeconds, 1)
        XCTAssertEqual(result.watts, 1)
    }

    func testCacheStartsWhenTheSlowReadFinishes() async {
        let fixture = ANEPowerFixture(readDuration: 2)
        let sampler = fixture.sampler()
        _ = await sampler.snapshot()
        fixture.set(time: 2.5)
        let result = await sampler.snapshot()
        XCTAssertEqual(fixture.readCount, 1)
        XCTAssertEqual(result.state, .sampling)
    }

    func testSlowReadCrossingExpiryRestartsSampling() async {
        let fixture = ANEPowerFixture()
        let sampler = fixture.sampler()
        _ = await sampler.snapshot()
        fixture.set(time: 14, channels: [.init(name: "ANE", unit: "mJ", value: 1_000)], readDuration: 2)
        let result = await sampler.snapshot()
        XCTAssertEqual(result.state, .sampling)
        XCTAssertNil(result.watts)
    }

    func testInvalidTimeAfterReadDiscardsSample() async {
        for duration in [-1, Double.nan, .infinity] {
            let fixture = ANEPowerFixture(readDuration: duration)
            let sampler = fixture.sampler()
            let result = await sampler.snapshot()
            assertUnavailable(result, .invalidSample)
            fixture.set(time: 2)
            let recovered = await sampler.snapshot()
            XCTAssertEqual(recovered.state, .sampling)
        }
    }

    func testExpiredBaselineClearsReadyValueAndRestartsSampling() async {
        let fixture = ANEPowerFixture()
        let sampler = fixture.sampler()
        _ = await sampler.snapshot()
        fixture.set(time: 1, channels: [.init(name: "ANE", unit: "mJ", value: 1_000)])
        let ready = await sampler.snapshot()
        XCTAssertEqual(ready.state, .ready)
        fixture.set(time: 16.01, channels: [.init(name: "ANE", unit: "mJ", value: 20_000)])
        let expired = await sampler.snapshot()
        XCTAssertEqual(expired.state, .sampling)
        XCTAssertNil(expired.watts)
        XCTAssertNil(expired.sampleSeconds)
        fixture.set(time: 17.01, channels: [.init(name: "ANE", unit: "mJ", value: 21_000)])
        let recovered = await sampler.snapshot()
        XCTAssertEqual(recovered.watts, 1)
    }

    func testFifteenSecondBoundaryStillProducesAValidSample() async {
        let fixture = ANEPowerFixture()
        let sampler = fixture.sampler()
        _ = await sampler.snapshot()
        fixture.set(time: 15, channels: [.init(name: "ANE", unit: "mJ", value: 15_000)])
        let result = await sampler.snapshot()
        XCTAssertEqual(result.state, .ready)
        XCTAssertEqual(result.sampleSeconds, 15)
        XCTAssertEqual(result.watts, 1)
    }

    func testCounterRegressionAndMetadataChangesDiscardThePair() async {
        for changed in [
            [ANEEnergyChannel(name: "ANE", unit: "mJ", value: 999)],
            [.init(name: "ANE0", unit: "mJ", value: 2_000)],
            [.init(name: "ANE", unit: "uJ", value: 2_000)],
        ] {
            let fixture = ANEPowerFixture(channels: [.init(name: "ANE", unit: "mJ", value: 1_000)])
            let sampler = fixture.sampler()
            _ = await sampler.snapshot()
            fixture.set(time: 1, channels: changed)
            let invalid = await sampler.snapshot()
            assertUnavailable(invalid, .invalidSample)
            fixture.set(time: 2, channels: changed)
            let fresh = await sampler.snapshot()
            XCTAssertEqual(fresh.state, .sampling)
        }
    }

    func testInvalidChannelValuesAndUnsupportedSourcesFailClosed() async {
        let cases: [([ANEEnergyChannel], ANEPowerFailure)] = [
            ([], .unsupported),
            ([.init(name: "ANE", unit: "kWh", value: 1)], .unsupported),
            ([.init(name: "ANE", unit: "mJ", value: -1)], .invalidSample),
            ([.init(name: "ANE", unit: "mJ", value: Int64.min)], .invalidSample),
            ([.init(name: "ANE0", unit: "mJ", value: 0), .init(name: "ANE0", unit: "mJ", value: 1)], .invalidSample),
            ([.init(name: "ANE", unit: "mJ", value: 0), .init(name: "ANE1", unit: "mJ", value: 1)], .invalidSample),
            ((0..<17).map { .init(name: "ANE\($0)", unit: "mJ", value: 0) }, .invalidSample),
        ]
        for (channels, reason) in cases {
            let fixture = ANEPowerFixture(channels: channels)
            let snapshot = await fixture.sampler().snapshot()
            assertUnavailable(snapshot, reason)
        }
        for name in ["", "ANE power", "ANE-1", "ANE1x", "ANE١", "GPU", "ane", "ANEnergy"] {
            let fixture = ANEPowerFixture(channels: [.init(name: name, unit: "mJ", value: 0)])
            let snapshot = await fixture.sampler().snapshot()
            assertUnavailable(snapshot, .invalidSample)
        }
    }

    func testReadFailureDiscardsReadyValueAndRequiresNewBaseline() async {
        for reason in [ANEPowerFailure.unsupported, .readFailed, .invalidSample] {
            let fixture = ANEPowerFixture()
            let sampler = fixture.sampler()
            _ = await sampler.snapshot()
            fixture.set(time: 1, channels: [.init(name: "ANE", unit: "mJ", value: 1_000)])
            _ = await sampler.snapshot()
            fixture.set(time: 2, failure: reason)
            let failure = await sampler.snapshot()
            assertUnavailable(failure, reason)
            fixture.set(time: 2.5)
            _ = await sampler.snapshot()
            XCTAssertEqual(fixture.readCount, 3)
            fixture.set(time: 3, channels: [.init(name: "ANE", unit: "mJ", value: 3_000)])
            let fresh = await sampler.snapshot()
            XCTAssertEqual(fresh.state, .sampling)
        }
    }

    func testInvalidMonotonicTimesDiscardReadyValuesWithoutReading() async {
        for time in [-1, 0.5, Double.nan, .infinity, -.infinity] {
            let fixture = ANEPowerFixture()
            let sampler = fixture.sampler()
            _ = await sampler.snapshot()
            fixture.set(time: 1, channels: [.init(name: "ANE", unit: "mJ", value: 1_000)])
            _ = await sampler.snapshot()
            fixture.set(time: time)
            let invalid = await sampler.snapshot()
            assertUnavailable(invalid, .invalidSample)
            XCTAssertEqual(fixture.readCount, 2)
            fixture.set(time: 2)
            let fresh = await sampler.snapshot()
            XCTAssertEqual(fresh.state, .sampling)
        }
    }

    func testUnknownReaderErrorOnlyExposesSafeFailureCode() async throws {
        struct BrokenReader: ANEEnergyReading {
            func read() throws -> [ANEEnergyChannel] { throw CocoaError(.fileReadNoPermission) }
        }
        let snapshot = await ANEPowerSampler(reader: BrokenReader()).snapshot()
        assertUnavailable(snapshot, .readFailed)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.containerGUI.encode(snapshot)) as? [String: Any])
        XCTAssertEqual(object["reason"] as? String, "read_failed")
    }

    func testAllOptionalJSONFieldsAreExplicitlyNull() async throws {
        let snapshot = await ANEPowerFixture().sampler().snapshot()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.containerGUI.encode(snapshot)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["state", "watts", "observedAt", "sampleSeconds", "reason", "scope", "estimated", "utilizationPercent", "utilizationState"]))
        for field in ["watts", "sampleSeconds", "reason", "utilizationPercent"] {
            XCTAssertTrue(object[field] is NSNull, field)
        }
        XCTAssertEqual(object["observedAt"] as? String, "2026-09-08T00:00:00Z")
        XCTAssertEqual(object["scope"] as? String, "host")
        XCTAssertEqual(object["estimated"] as? Bool, true)
        XCTAssertEqual(object["utilizationState"] as? String, "unavailable")
    }

    func testRealIOReportReadOnlySmokeWhenExplicitlyRequested() async throws {
        guard ProcessInfo.processInfo.environment["CONTAINER_GUI_ANE_SMOKE"] == "1" else {
            throw XCTSkip("Set CONTAINER_GUI_ANE_SMOKE=1 for the native read-only ANE smoke test")
        }
        let reader = IOReportANEEnergyReader()
        let before = try reader.read()
        XCTAssertFalse(before.isEmpty)
        let sampler = ANEPowerSampler(reader: reader)
        let initial = await sampler.snapshot()
        XCTAssertEqual(initial.state, .sampling)
        try await Task.sleep(for: .milliseconds(1_100))
        let result = await sampler.snapshot()
        XCTAssertEqual(result.state, .ready)
        XCTAssertTrue(try XCTUnwrap(result.watts).isFinite)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(result.watts), 0)
        XCTAssertGreaterThan(try XCTUnwrap(result.sampleSeconds), 1)
        let after = try reader.read()
        XCTAssertEqual(before.map(\.name), after.map(\.name))
        for (start, end) in zip(before, after) { XCTAssertGreaterThanOrEqual(end.value, start.value) }
        print("ANE_SMOKE before=\(before) after=\(after) snapshot=\(String(decoding: try JSONEncoder.containerGUI.encode(result), as: UTF8.self))")
        // Exercise create-owned CF teardown before unloading the library, without keeping readers alive.
        for _ in 0..<10 {
            try autoreleasepool {
                let transientReader = IOReportANEEnergyReader()
                XCTAssertFalse(try transientReader.read().isEmpty)
            }
        }
    }

    private func assertUnavailable(_ snapshot: ANEPowerSnapshot, _ reason: ANEPowerFailure, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(snapshot.state, .unavailable, file: file, line: line)
        XCTAssertEqual(snapshot.reason, reason, file: file, line: line)
        XCTAssertNil(snapshot.watts, file: file, line: line)
        XCTAssertNil(snapshot.sampleSeconds, file: file, line: line)
    }
}

final class ANEPowerFixture: ANEEnergyReading, @unchecked Sendable {
    static let date = Date(timeIntervalSince1970: 1_788_825_600)
    private let lock = NSLock()
    private var time: Double = 0
    private var channels: [ANEEnergyChannel]
    private var failure: ANEPowerFailure?
    private var readDuration: Double
    private var count = 0

    init(channels: [ANEEnergyChannel] = [.init(name: "ANE", unit: "mJ", value: 0)], readDuration: Double = 0) {
        self.channels = channels
        self.readDuration = readDuration
    }

    var readCount: Int { lock.withLock { count } }

    func set(time: Double, channels: [ANEEnergyChannel]? = nil, failure: ANEPowerFailure? = nil, readDuration: Double = 0) {
        lock.withLock {
            self.time = time
            if let channels { self.channels = channels }
            self.failure = failure
            self.readDuration = readDuration
        }
    }

    func read() throws -> [ANEEnergyChannel] {
        try lock.withLock {
            count += 1
            time += readDuration
            if let failure { throw failure }
            return channels
        }
    }

    func sampler() -> ANEPowerSampler {
        ANEPowerSampler(reader: self, monotonicNow: { self.lock.withLock { self.time } }, observedAt: { Self.date })
    }
}
