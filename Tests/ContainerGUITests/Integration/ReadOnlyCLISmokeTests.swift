import Foundation
import XCTest

@testable import ContainerGUI

final class ReadOnlyCLISmokeTests: XCTestCase {
    func testLiveVersionStatusListMetricsAndOptionalDetail() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CONTAINER_GUI_LIVE_READONLY"] == "1",
            "Set CONTAINER_GUI_LIVE_READONLY=1 to run non-mutating compatibility checks"
        )

        let configuration = try AppConfiguration()
        let executableURL = try CLIVersionResolver().resolve(explicitPath: configuration.explicitCLIPath)
        let client = ContainerCLIClient(
            executor: FoundationProcessExecutor(),
            executableURL: executableURL,
            queryTimeout: configuration.queryTimeout,
            maximumOutputBytes: configuration.maximumCommandOutputBytes
        )

        let installation = try await client.installation()
        XCTAssertEqual(installation.compatibility, .supported)
        XCTAssertEqual(installation.semanticVersion, "1.3.1")

        let health = try await client.systemHealth()
        XCTAssertNotEqual(health.serviceState, .unknown)

        let list = try await client.listContainers()
        XCTAssertLessThanOrEqual(list.items.count, 1_000)
        for _ in 0..<4 {
            let cancelledWaiter = Task { try await client.containerMetrics() }
            try await Task.sleep(for: .milliseconds(50))
            cancelledWaiter.cancel()
            let metrics = try await client.containerMetrics()
            _ = try? await cancelledWaiter.value
            XCTAssertLessThanOrEqual(metrics.items.count, 1_000)
            XCTAssertEqual(Set(metrics.items.map(\.containerID)).count, metrics.items.count)
            for metric in metrics.items {
                if let cpuPercent = metric.cpuPercent {
                    XCTAssertTrue(cpuPercent.isFinite)
                    XCTAssertGreaterThanOrEqual(cpuPercent, 0)
                }
                if let memoryPercent = metric.memoryPercent {
                    XCTAssertTrue(memoryPercent.isFinite)
                    XCTAssertGreaterThanOrEqual(memoryPercent, 0)
                }
            }
        }
        if let first = list.items.first {
            let detail = try await client.containerDetail(id: first.id)
            XCTAssertEqual(detail.summary.id, first.id)
            assertSensitiveValuesAreRedacted(detail.raw)
        }
    }

    private func assertSensitiveValuesAreRedacted(_ value: JSONValue) {
        switch value {
        case .object(let object):
            for (key, child) in object {
                let normalized = key.lowercased()
                if ["password", "passwd", "secret", "token", "api_key", "apikey", "authorization", "credential", "private_key"]
                    .contains(where: { normalized == $0 || normalized.hasSuffix("_\($0)") }) {
                    XCTAssertEqual(child, .string("[REDACTED]"))
                } else {
                    assertSensitiveValuesAreRedacted(child)
                }
            }
        case .array(let array):
            array.forEach(assertSensitiveValuesAreRedacted)
        default:
            break
        }
    }
}
