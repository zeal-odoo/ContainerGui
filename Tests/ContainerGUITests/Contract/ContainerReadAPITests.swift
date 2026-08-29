import Foundation
import Hummingbird
import HummingbirdTesting
import XCTest

@testable import ContainerGUI

final class ContainerReadAPITests: XCTestCase {
    func testHealthListAndDetailMatchContract() async throws {
        let reader = StubContainerReader()
        let app = makeApplication(reader: reader)

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/v1/system/health", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let value = try JSONDecoder.containerGUI.decode(SystemHealth.self, from: response.body)
                XCTAssertEqual(value.serviceState, .healthy)
            }
            try await client.execute(uri: "/api/v1/containers", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let value = try JSONDecoder.containerGUI.decode(ContainerList.self, from: response.body)
                XCTAssertEqual(value.items.map(\.id), ["demo-running"])
            }
            try await client.execute(uri: "/api/v1/containers/demo-running", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let value = try JSONDecoder.containerGUI.decode(ContainerDetail.self, from: response.body)
                XCTAssertEqual(value.summary.id, "demo-running")
            }
        }
    }

    func testEmptyListIsA200Snapshot() async throws {
        let reader = StubContainerReader(items: [])
        let app = makeApplication(reader: reader)

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/v1/containers", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let value = try JSONDecoder.containerGUI.decode(ContainerList.self, from: response.body)
                XCTAssertTrue(value.items.isEmpty)
                XCTAssertNotNil(value.observedAt)
            }
        }
    }

    func testNotFoundAndCLIErrorUseProblemEnvelope() async throws {
        let reader = StubContainerReader(listProblem: ProblemDetail(code: .serviceUnavailable))
        let app = makeApplication(reader: reader)

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/v1/containers", method: .get) { response in
                XCTAssertEqual(response.status, .serviceUnavailable)
                XCTAssertTrue(response.headers[.contentType]?.hasPrefix("application/problem+json") == true)
                let problem = try JSONDecoder.containerGUI.decode(ProblemDetail.self, from: response.body)
                XCTAssertEqual(problem.code, .serviceUnavailable)
            }
            try await client.execute(uri: "/api/v1/containers/missing", method: .get) { response in
                XCTAssertEqual(response.status, .notFound)
                let problem = try JSONDecoder.containerGUI.decode(ProblemDetail.self, from: response.body)
                XCTAssertEqual(problem.code, .targetNotFound)
            }
        }
    }

    private func makeApplication(reader: some ContainerReading) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router()
        router.middlewares.add(ErrorMiddleware())
        ContainerReadRoutes.register(on: router, reader: reader)
        return Application(router: router)
    }
}

private actor StubContainerReader: ContainerReading {
    private let items: [ContainerSummary]
    private let listProblem: ProblemDetail?
    private let observedAt = Date(timeIntervalSince1970: 1_787_987_200)

    init(items: [ContainerSummary]? = nil, listProblem: ProblemDetail? = nil) {
        self.items = items ?? [
            ContainerSummary(
                id: "demo-running",
                displayName: "demo-running",
                imageReference: "docker.io/library/nginx:alpine",
                state: .running,
                rawState: "running",
                ipv4Address: "192.0.2.10/24",
                ipv6Address: nil,
                createdAt: nil,
                observedAt: Date(timeIntervalSince1970: 1_787_987_200)
            )
        ]
        self.listProblem = listProblem
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
        if let listProblem { throw listProblem }
        return ContainerList(items: items, observedAt: observedAt)
    }

    func containerDetail(id: String) async throws -> ContainerDetail {
        guard let summary = items.first(where: { $0.id == id }) else {
            throw ProblemDetail(code: .targetNotFound)
        }
        return ContainerDetail(
            summary: summary,
            configuration: .object(["id": .string(id)]),
            status: .object(["state": .string("running")]),
            raw: .object(["id": .string(id)]),
            observedAt: observedAt
        )
    }
}
