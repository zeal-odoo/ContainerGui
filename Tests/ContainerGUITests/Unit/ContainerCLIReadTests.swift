import Foundation
import XCTest

@testable import ContainerGUI

final class ContainerCLIReadTests: XCTestCase {
    private let observedAt = Date(timeIntervalSince1970: 1_787_987_200)
    private let installation = CLIInstallation(
        versionText: "container CLI version 1.3.1",
        semanticVersion: "1.3.1",
        compatibility: .supported,
        checkedAt: Date(timeIntervalSince1970: 1_787_987_199)
    )

    func testParsesHealthyStoppedAndUnregisteredSystemStates() throws {
        let healthy = try CLIOutputParser.parseSystemHealth(
            data: fixture("system-healthy.json"),
            installation: installation,
            observedAt: observedAt
        )
        let stopped = try CLIOutputParser.parseSystemHealth(
            data: fixture("system-stopped.json"),
            installation: installation,
            observedAt: observedAt
        )
        let unregistered = try CLIOutputParser.parseSystemHealth(
            data: fixture("system-unregistered.json"),
            installation: installation,
            observedAt: observedAt
        )

        XCTAssertEqual(healthy.serviceState, .healthy)
        XCTAssertEqual(healthy.apiServerVersion, "container-apiserver version 1.3.1")
        XCTAssertEqual(stopped.serviceState, .stopped)
        XCTAssertEqual(unregistered.serviceState, .unregistered)
    }

    func testParsesMixedAndEmptyContainerLists() throws {
        let mixed = try CLIOutputParser.parseContainerList(
            data: fixture("containers-mixed.json"),
            observedAt: observedAt
        )
        let empty = try CLIOutputParser.parseContainerList(
            data: fixture("containers-empty.json"),
            observedAt: observedAt
        )

        XCTAssertEqual(mixed.items.map(\.id), ["demo-running", "demo-stopped"])
        XCTAssertEqual(mixed.items.map(\.state), [.running, .stopped])
        XCTAssertEqual(mixed.items.first?.imageReference, "docker.io/library/nginx:alpine")
        XCTAssertEqual(mixed.items.first?.ipv4Address, "192.0.2.10/24")
        XCTAssertEqual(mixed.observedAt, observedAt)
        XCTAssertTrue(empty.items.isEmpty)
    }

    func testToleratesUnknownFieldsAndNormalizesUnknownState() throws {
        let list = try CLIOutputParser.parseContainerList(
            data: fixture("containers-unknown-fields.json"),
            observedAt: observedAt
        )

        XCTAssertEqual(list.items.count, 1)
        XCTAssertEqual(list.items[0].state, .unknown)
        XCTAssertEqual(list.items[0].rawState, "teleporting")
    }

    func testRejectsMissingIdentifierAndMalformedJSON() throws {
        XCTAssertThrowsError(
            try CLIOutputParser.parseContainerList(
                data: fixture("containers-missing-id.json"),
                observedAt: observedAt
            )
        )
        XCTAssertThrowsError(
            try CLIOutputParser.parseContainerList(
                data: fixture("containers-malformed.txt"),
                observedAt: observedAt
            )
        )
    }

    func testParsesDetailAndRedactsSecretsRecursively() throws {
        let detail = try CLIOutputParser.parseContainerDetail(
            data: fixture("container-detail.json"),
            expectedID: "demo-running",
            observedAt: observedAt
        )
        let encoded = String(decoding: try JSONEncoder.containerGUI.encode(detail), as: UTF8.self)

        XCTAssertEqual(detail.summary.state, .running)
        XCTAssertTrue(encoded.contains("PUBLIC_MODE"))
        XCTAssertTrue(encoded.contains("[REDACTED]"))
        XCTAssertFalse(encoded.contains("fixture-secret-must-not-leak"))
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "Fixtures/CLI/1.3.1"
            )
        )
        return try Data(contentsOf: url)
    }
}
