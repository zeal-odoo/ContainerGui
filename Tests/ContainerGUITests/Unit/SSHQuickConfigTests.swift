import Foundation
import XCTest

@testable import ContainerGUI

final class SSHQuickConfigTests: XCTestCase {
    private let publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhY fixture@example"

    func testSSHCreateConfigurationValidatesAndBuildsSafeSummary() throws {
        let configuration = SSHCreateConfiguration(
            hostPort: 2222,
            username: "dev",
            publicKey: publicKey
        )

        XCTAssertEqual(try configuration.validated(), configuration)
        XCTAssertEqual(configuration.publicKeyType, "ssh-ed25519")
        XCTAssertTrue(configuration.publicKeyFingerprint.hasPrefix("SHA256:"))

        let encoded = String(
            decoding: try JSONEncoder.containerGUI.encode(JSONValue.object(configuration.safeRequestSummary)),
            as: UTF8.self
        )
        XCTAssertTrue(encoded.contains("127.0.0.1"))
        XCTAssertTrue(encoded.contains("ssh-ed25519"))
        XCTAssertTrue(encoded.contains("SHA256:"))
        XCTAssertFalse(encoded.contains(publicKey))
    }

    func testSSHConnectionOnlyAcceptsCompleteTrustedLabels() throws {
        let connection = try XCTUnwrap(ContainerSSHConnection(labels: [
            SSHContainerLabels.enabled: .string("true"),
            SSHContainerLabels.hostPort: .string("2222"),
            SSHContainerLabels.username: .string("dev"),
        ]))

        XCTAssertEqual(connection.host, "127.0.0.1")
        XCTAssertEqual(connection.hostPort, 2222)
        XCTAssertEqual(connection.username, "dev")
        XCTAssertEqual(connection.connectionCommand, "ssh -p 2222 dev@127.0.0.1")

        XCTAssertNil(ContainerSSHConnection(labels: [
            SSHContainerLabels.enabled: .string("true"),
            SSHContainerLabels.hostPort: .string("22"),
            SSHContainerLabels.username: .string("root"),
        ]))
        XCTAssertNil(ContainerSSHConnection(labels: [
            SSHContainerLabels.enabled: .string("true"),
            SSHContainerLabels.hostPort: .string("2222"),
        ]))
    }

    func testParsesSSHMetadataFromVersionedFixtureAndKeepsItAcrossStateChanges() throws {
        let data = try fixture("ssh-container-detail.json")
        let running = try CLIOutputParser.parseContainerDetail(data: data, expectedID: "ssh-demo")
        let stoppedData = Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""state": "running""#, with: #""state": "stopped""#).utf8)
        let stopped = try CLIOutputParser.parseContainerDetail(data: stoppedData, expectedID: "ssh-demo")

        XCTAssertEqual(running.summary.state, .running)
        XCTAssertEqual(stopped.summary.state, .stopped)
        XCTAssertEqual(running.summary.ssh, ContainerSSHConnection(hostPort: 2222, username: "dev"))
        XCTAssertEqual(stopped.summary.ssh, running.summary.ssh)
        XCTAssertTrue(SSHContainerBootstrap.script.contains("ssh-keygen -A"))
        XCTAssertTrue(SSHContainerBootstrap.script.contains("exec /usr/sbin/sshd -D -e"))
        XCTAssertFalse(SSHContainerBootstrap.script.contains("rm -f /etc/ssh/ssh_host_"))
    }

    func testSSHCreateRejectsInvalidIdentityAndCrossFieldConflicts() throws {
        let invalidIdentity = ContainerCreateRequest(
            name: "ssh-demo",
            image: "ubuntu:26.04",
            startAfterCreate: true,
            ssh: SSHCreateConfiguration(hostPort: 22, username: "root", publicKey: "not-a-key")
        )
        assertValidationError(
            try invalidIdentity.validated(),
            fields: ["ssh.hostPort", "ssh.publicKey", "ssh.username"]
        )

        let conflicts = ContainerCreateRequest(
            name: "ssh-demo",
            image: "ubuntu:26.04",
            ports: [PortMapping(hostPort: 2222, containerPort: 8080)],
            environment: [
                EnvironmentEntry(name: SSHCreateConfiguration.userEnvironmentName, value: "override"),
            ],
            arguments: ["sleep", "infinity"],
            startAfterCreate: false,
            ssh: SSHCreateConfiguration(hostPort: 2222, username: "dev", publicKey: publicKey)
        )
        assertValidationError(
            try conflicts.validated(),
            fields: ["arguments", "environment", "ssh.hostPort", "startAfterCreate"]
        )
    }

    private func assertValidationError<T>(
        _ expression: @autoclosure () throws -> T,
        fields expectedFields: Set<String>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try expression()
            XCTFail("Expected validation failure", file: file, line: line)
        } catch let problem as ProblemDetail {
            XCTAssertEqual(problem.code, .validationFailed, file: file, line: line)
            XCTAssertEqual(Set(problem.fieldErrors?.map(\.field) ?? []), expectedFields, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
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
