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

    func testPublishedPortsReachBothListAndDetailSummaries() throws {
        let data = Data(#"""
        [{"id":"demo","configuration":{"publishedPorts":[
            {"hostAddress":"127.0.0.1","hostPort":18080,"containerPort":8069,"proto":"tcp","count":1},
            {"hostAddress":"0.0.0.0","hostPort":110,"containerPort":5432,"proto":"tcp","count":1},
            {"hostAddress":"::1","hostPort":5300,"containerPort":53,"proto":"udp","count":3}
        ]},"status":{"state":"stopped"}}]
        """#.utf8)
        let list = try CLIOutputParser.parseContainerList(data: data)
        let detail = try CLIOutputParser.parseContainerDetail(data: data, expectedID: "demo")
        for summary in [list.items[0], detail.summary] {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(
                with: JSONEncoder.containerGUI.encode(summary)
            ) as? [String: Any])
            let ports = try XCTUnwrap(object["publishedPorts"] as? [[String: Any]])
            XCTAssertEqual(ports.count, 3)
            XCTAssertEqual(ports[0]["hostAddress"] as? String, "127.0.0.1")
            XCTAssertEqual(ports[0]["hostPort"] as? Int, 18080)
            XCTAssertEqual(ports[0]["containerPort"] as? Int, 8069)
            XCTAssertEqual(ports[0]["protocol"] as? String, "tcp")
            XCTAssertEqual(ports[1]["hostPort"] as? Int, 110)
            XCTAssertEqual(ports[2]["hostAddress"] as? String, "::1")
            XCTAssertEqual(ports[2]["count"] as? Int, 3)
            XCTAssertEqual(ports[2]["protocol"] as? String, "udp")
        }
    }

    func testPublishedPortsDistinguishUnmappedFromUnavailableAndDefaultSinglePorts() throws {
        let list = try CLIOutputParser.parseContainerList(data: Data(#"""
        [
            {"id":"unmapped","configuration":{"publishedPorts":[]}},
            {"id":"unavailable","configuration":{}},
            {"id":"legacy","configuration":{"publishedPorts":[
                {"hostAddress":"127.0.0.1","hostPort":2222,"containerPort":22,"proto":"tcp"},
                {"hostAddress":"::","hostPort":65535,"containerPort":65535,"proto":"udp","count":null}
            ]}}
        ]
        """#.utf8))
        XCTAssertEqual(list.items[0].publishedPorts, [])
        XCTAssertNil(list.items[1].publishedPorts)
        XCTAssertEqual(list.items[2].publishedPorts?.first?.count, 1)
        XCTAssertEqual(list.items[2].publishedPorts?.last?.count, 1)
        XCTAssertEqual(list.items[2].publishedPorts?.last?.hostPort, 65_535)
        let sshDetail = try CLIOutputParser.parseContainerDetail(
            data: fixture("ssh-container-detail.json"), expectedID: "ssh-demo"
        )
        XCTAssertEqual(sshDetail.summary.publishedPorts?.first?.containerPort, 22)
    }

    func testInvalidPortDataDoesNotHideContainerOrClaimNoMappings() throws {
        let valid: [String: Any] = [
            "hostAddress": "127.0.0.1", "hostPort": 18080,
            "containerPort": 8069, "proto": "tcp", "count": 1
        ]
        let invalidFields: [(String, Any)] = [
            ("hostAddress", ""), ("hostPort", -1), ("hostPort", 65_536),
            ("hostPort", 80.5), ("hostPort", "8080"), ("containerPort", -1),
            ("containerPort", 65_536), ("count", 0), ("count", -1),
            ("count", 0.5), ("count", 65_536), ("count", 60_000),
            ("proto", "sctp"), ("proto", NSNull())
        ]
        for (key, value) in invalidFields {
            var invalid = valid
            invalid[key] = value
            let data = try JSONSerialization.data(withJSONObject: [[
                "id": "demo", "configuration": ["publishedPorts": [valid, invalid]],
                "status": ["state": "running"]
            ]])
            let item = try XCTUnwrap(CLIOutputParser.parseContainerList(data: data).items.first)
            XCTAssertEqual(item.state, .running)
            XCTAssertNil(item.publishedPorts, "\(key): \(value)")
        }
        for ports in ["null", "{}", "[null]"] {
            let data = Data(#"[{"id":"demo","configuration":{"publishedPorts":\#(ports)}}]"#.utf8)
            XCTAssertNil(try CLIOutputParser.parseContainerList(data: data).items[0].publishedPorts)
        }
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
        for clientVersion in ["1.5.0", "1.6.1", "1.7.1"] {
            for serverVersion in ["1.3.1", "1.4.1", "1.5.0", "1.6.1", "1.7.1", nil] {
                let servers = serverVersion.map {
                    [#"{"version":"\#($0)","build":"release","commit":"fixture-server"}"#]
                } ?? ["null", "{}"]
                for server in servers {
                    let health = try CLIOutputParser.parseSystemHealth(
                        data: Data(#"{"status":"running","client":{"version":"\#(clientVersion)"},"server":\#(server)}"#.utf8),
                        installation: installation
                    )
                    XCTAssertEqual(health.serviceState, .healthy)
                    XCTAssertEqual(health.apiServerVersion, serverVersion)
                }
            }
        }
    }

    func testParsesRecentNestedServerWithoutExposingHostMetadata() throws {
        for version in ["1.5.0", "1.6.1", "1.7.1"] {
            let health = try CLIOutputParser.parseSystemHealth(
                data: fixture("system-healthy.json", version: version),
                installation: installation,
                observedAt: observedAt
            )
            XCTAssertEqual(health.serviceState, .healthy)
            XCTAssertEqual(health.apiServerVersion, version)
            XCTAssertEqual(health.apiServerBuild, "release")
            XCTAssertEqual(health.apiServerCommit, "fixture-server")
            XCTAssertEqual(health.tool, installation)
            let encoded = String(decoding: try JSONEncoder.containerGUI.encode(health), as: UTF8.self)
            XCTAssertFalse(encoded.contains("/Users/example"))
            XCTAssertFalse(encoded.contains("installRoot"))
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
