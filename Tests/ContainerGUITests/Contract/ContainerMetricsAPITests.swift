import Foundation
import Hummingbird
import HummingbirdTesting
import XCTest

@testable import ContainerGUI

final class ContainerMetricsAPITests: XCTestCase {
    func testMetricsRouteReturnsSamplingSnapshotAndWinsOverDetailParameter() async throws {
        let reader = StubMetricsReader()
        let app = makeApplication(reader: reader)

        try await app.testLocal { client in
            try await client.execute(uri: "/api/v1/containers/metrics", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertTrue(response.headers[.contentType]?.hasPrefix("application/json") == true)
                let body = Data(buffer: response.body)
                let value = try JSONDecoder.containerGUI.decode(ContainerMetricsSnapshot.self, from: body)
                XCTAssertEqual(value.items.first?.containerID, "demo-running")
                XCTAssertEqual(value.items.first?.cpuState, .sampling)
                XCTAssertNil(value.items.first?.cpuPercent)
                XCTAssertEqual(value.items.first?.rootFilesystem.state, .ready)
                XCTAssertEqual(value.items.first?.rootFilesystem.capacityBytes, 541_115_342_848)
                XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("\"cpuPercent\":null"))
                XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("\"rootFilesystem\""))
            }
        }
    }

    func testMetricsFailureUsesProblemEnvelopeWithoutBreakingContainerList() async throws {
        let reader = StubMetricsReader(metricsTimeOut: true)
        let app = makeApplication(reader: reader)

        try await app.testLocal { client in
            try await client.execute(uri: "/api/v1/containers/metrics", method: .get) { response in
                XCTAssertEqual(response.status, .gatewayTimeout)
                XCTAssertTrue(response.headers[.contentType]?.hasPrefix("application/problem+json") == true)
                let problem = try JSONDecoder.containerGUI.decode(ProblemDetail.self, from: response.body)
                XCTAssertEqual(problem.code, .cliTimeout)
            }
            try await client.execute(uri: "/api/v1/containers", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let value = try JSONDecoder.containerGUI.decode(ContainerList.self, from: response.body)
                XCTAssertEqual(value.items.map(\.id), ["demo-running"])
            }
        }
    }

    func testMetricsRouteBoundsAReaderThatDoesNotReturn() async throws {
        let reader = StubMetricsReader(metricsDelay: .seconds(30))
        let app = makeApplication(reader: reader, metricsTimeout: .milliseconds(50))

        try await app.testLocal { client in
            try await client.execute(uri: "/api/v1/containers/metrics", method: .get) { response in
                XCTAssertEqual(response.status, .gatewayTimeout)
                let problem = try JSONDecoder.containerGUI.decode(ProblemDetail.self, from: response.body)
                XCTAssertEqual(problem.code, .cliTimeout)
            }
        }
    }

    private func makeApplication(
        reader: StubMetricsReader,
        metricsTimeout: Duration = .seconds(5)
    ) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router()
        router.middlewares.add(ErrorMiddleware())
        ContainerReadRoutes.register(on: router, reader: reader)
        ContainerMetricsRoutes.register(on: router, reader: reader, timeout: metricsTimeout)
        return Application(router: router)
    }
}

private actor StubMetricsReader: ContainerReading, ContainerMetricsReading {
    private let metricsTimeOut: Bool
    private let metricsDelay: Duration?
    private let observedAt = Date(timeIntervalSince1970: 1_787_987_200)

    init(metricsTimeOut: Bool = false, metricsDelay: Duration? = nil) {
        self.metricsTimeOut = metricsTimeOut
        self.metricsDelay = metricsDelay
    }

    func systemHealth() async throws -> SystemHealth {
        SystemHealth(
            tool: CLIInstallation(
                versionText: "container CLI version 1.3.1",
                semanticVersion: "1.3.1",
                compatibility: .supported,
                checkedAt: observedAt
            ),
            serviceState: .healthy,
            apiServerVersion: "1.3.1",
            apiServerBuild: "release",
            apiServerCommit: "fixture",
            diagnosticCode: nil,
            diagnosticMessage: nil,
            observedAt: observedAt
        )
    }

    func listContainers() async throws -> ContainerList {
        ContainerList(items: [summary], observedAt: observedAt)
    }

    func containerDetail(id: String) async throws -> ContainerDetail {
        guard id == summary.id else { throw ProblemDetail(code: .targetNotFound) }
        return ContainerDetail(
            summary: summary,
            configuration: .object([:]),
            status: .object(["state": .string("running")]),
            raw: .object(["id": .string(id)]),
            observedAt: observedAt
        )
    }

    func containerMetrics() async throws -> ContainerMetricsSnapshot {
        if metricsTimeOut { throw CommandExecutionError.timedOut }
        if let metricsDelay { try await Task.sleep(for: metricsDelay) }
        return ContainerMetricsSnapshot(
            items: [
                ContainerResourceUsage(
                    containerID: "demo-running",
                    cpuPercent: nil,
                    cpuState: .sampling,
                    memoryUsageBytes: 1_073_741_824,
                    memoryLimitBytes: 4_294_967_296,
                    memoryPercent: 25,
                    rootFilesystem: ContainerRootFilesystemUsage(
                        state: .ready,
                        usedBytes: 2_558_087_168,
                        capacityBytes: 541_115_342_848,
                        availableBytes: 538_540_478_464,
                        usagePercent: 0.472727,
                    ),
                    observedAt: observedAt
                )
            ],
            observedAt: observedAt
        )
    }

    private var summary: ContainerSummary {
        ContainerSummary(
            id: "demo-running",
            displayName: "demo-running",
            imageReference: "example.invalid/demo:1",
            state: .running,
            rawState: "running",
            ipv4Address: "192.0.2.10/24",
            ipv6Address: nil,
            createdAt: nil,
            observedAt: observedAt
        )
    }
}
