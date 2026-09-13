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
        XCTAssertEqual(mixed.items.first?.cpuCount, 3)
        XCTAssertEqual(mixed.items.first?.ipv4Address, "192.0.2.10/24")
        XCTAssertEqual(mixed.observedAt, observedAt)
        XCTAssertTrue(empty.items.isEmpty)
    }

    func testParses141NestedServerWithoutChangingHealthContract() throws {
        let health = try CLIOutputParser.parseSystemHealth(
            data: fixture("system-healthy.json", version: "1.4.1"),
            installation: installation,
            observedAt: observedAt
        )
        XCTAssertEqual(health.serviceState, .healthy)
        XCTAssertEqual(health.apiServerVersion, "container-apiserver version 1.4.1")
        XCTAssertEqual(health.apiServerBuild, "release")
        XCTAssertEqual(health.apiServerCommit, "fixture-server")
        XCTAssertEqual(health.tool, installation)
        XCTAssertEqual(health.observedAt, observedAt)
        let encoded = String(decoding: try JSONEncoder.containerGUI.encode(health), as: UTF8.self)
        XCTAssertFalse(encoded.contains("/Users/example"))
        XCTAssertFalse(encoded.contains("futureField"))
    }

    func testNestedServerVersionIsNotInferredFromClientDuringUpgrade() throws {
        for server in [#"{"version":"1.3.1","build":"release","commit":"old-server"}"#, "null", "{}"] {
            let health = try CLIOutputParser.parseSystemHealth(
                data: Data(#"{"status":"running","client":{"version":"1.4.1"},"server":\#(server)}"#.utf8),
                installation: installation
            )
            XCTAssertEqual(health.serviceState, .healthy)
            XCTAssertEqual(health.apiServerVersion, server.contains("1.3.1") ? "1.3.1" : nil)
        }
    }

    func test141MinimalClosedStatesAndInvalidHealthOutput() throws {
        for (status, expected) in [("not running", SystemServiceState.stopped), ("unregistered", .unregistered)] {
            let health = try CLIOutputParser.parseSystemHealth(
                data: Data("{\"status\":\"\(status)\"}".utf8), installation: installation
            )
            XCTAssertEqual(health.serviceState, expected)
            XCTAssertNil(health.apiServerVersion)
        }
        for json in ["{}", "[]", #"{"status":null}"#, "not JSON"] {
            XCTAssertThrowsError(try CLIOutputParser.parseSystemHealth(
                data: Data(json.utf8), installation: installation
            ))
        }
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

    func testRedactsSSHPublicKeyEmbeddedInEnvironmentArray() throws {
        let detail = try CLIOutputParser.parseContainerDetail(
            data: fixture("ssh-container-detail.json"),
            expectedID: "ssh-demo",
            observedAt: observedAt
        )
        let encoded = String(decoding: try JSONEncoder.containerGUI.encode(detail), as: UTF8.self)

        XCTAssertTrue(encoded.contains(SSHCreateConfiguration.publicKeyEnvironmentName))
        XCTAssertTrue(encoded.contains("[REDACTED]"))
        XCTAssertFalse(encoded.contains("AAAAC3NzaC1lZDI1NTE5AAAAIFhY"))
        XCTAssertFalse(encoded.contains("fixture@example"))

        let keyedEnvironment = JSONValue.object([
            SSHCreateConfiguration.publicKeyEnvironmentName: .string("ssh-ed25519 AAAA keyed@example")
        ]).redacted()
        XCTAssertEqual(
            keyedEnvironment.objectValue?[SSHCreateConfiguration.publicKeyEnvironmentName],
            .string("[REDACTED]")
        )
    }

    private func fixture(_ name: String, version: String = "1.3.1") throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "Fixtures/CLI/\(version)"
            )
        )
        return try Data(contentsOf: url)
    }
}
