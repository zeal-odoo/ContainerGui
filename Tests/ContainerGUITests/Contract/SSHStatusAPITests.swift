import Foundation
import Hummingbird
import HummingbirdTesting
import XCTest

@testable import ContainerGUI

final class SSHStatusAPITests: XCTestCase {
    func testRunningContainerReportsReadyOnlyAfterSSHBanner() async throws {
        let readyChecker = StubSSHReadinessChecker(isReady: true)
        let readyApp = makeApplication(state: .running, connection: connection, checker: readyChecker)

        try await readyApp.testLocal { client in
            try await client.execute(uri: "/api/v1/containers/ssh-demo/ssh", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let status = try JSONDecoder.containerGUI.decode(ContainerSSHStatus.self, from: response.body)
                XCTAssertEqual(status.containerID, "ssh-demo")
                XCTAssertEqual(status.state, .ready)
                XCTAssertEqual(status.connection?.connectionCommand, "ssh -p 2222 dev@127.0.0.1")
            }
        }
        let readyCheckedPorts = await readyChecker.checkedPorts
        XCTAssertEqual(readyCheckedPorts, [2222])

        let pendingChecker = StubSSHReadinessChecker(isReady: false)
        let pendingApp = makeApplication(state: .running, connection: connection, checker: pendingChecker)
        try await pendingApp.testLocal { client in
            try await client.execute(uri: "/api/v1/containers/ssh-demo/ssh", method: .get) { response in
                let status = try JSONDecoder.containerGUI.decode(ContainerSSHStatus.self, from: response.body)
                XCTAssertEqual(status.state, .initializing)
            }
        }
    }

    func testStoppedFailedAndUnconfiguredContainersDoNotProbePorts() async throws {
        for (state, connection, expectedState) in [
            (ContainerState.stopped, self.connection, ContainerSSHState.stopped),
            (.error, self.connection, .failed),
            (.running, nil, .notConfigured),
        ] {
            let checker = StubSSHReadinessChecker(isReady: true)
            let app = makeApplication(state: state, connection: connection, checker: checker)
            try await app.testLocal { client in
                try await client.execute(uri: "/api/v1/containers/ssh-demo/ssh", method: .get) { response in
                    let status = try JSONDecoder.containerGUI.decode(ContainerSSHStatus.self, from: response.body)
                    XCTAssertEqual(status.state, expectedState)
                    XCTAssertEqual(status.connection, connection)
                }
            }
            let checkedPorts = await checker.checkedPorts
            XCTAssertTrue(checkedPorts.isEmpty)
        }
    }

    private var connection: ContainerSSHConnection {
        ContainerSSHConnection(hostPort: 2222, username: "dev")
    }

    private func makeApplication(
        state: ContainerState,
        connection: ContainerSSHConnection?,
        checker: StubSSHReadinessChecker
    ) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router()
        SSHStatusRoutes.register(
            on: router,
            reader: StubSSHStatusReader(summary: summary(state: state, connection: connection)),
            checker: checker
        )
        return Application(router: router)
    }

    private func summary(
        state: ContainerState,
        connection: ContainerSSHConnection?
    ) -> ContainerSummary {
        ContainerSummary(
            id: "ssh-demo",
            displayName: "ssh-demo",
            imageReference: "ubuntu:26.04",
            state: state,
            rawState: state.rawValue,
            ipv4Address: nil,
            ipv6Address: nil,
            createdAt: nil,
            ssh: connection,
            observedAt: Date(timeIntervalSince1970: 1_788_000_000)
        )
    }
}

private struct StubSSHStatusReader: ContainerReading {
    let summary: ContainerSummary

    func systemHealth() async throws -> SystemHealth {
        throw ContainerCLIError.invalidOutput
    }

    func listContainers() async throws -> ContainerList {
        ContainerList(items: [summary], observedAt: summary.observedAt)
    }

    func containerDetail(id: String) async throws -> ContainerDetail {
        guard id == summary.id else { throw ContainerCLIError.targetNotFound }
        return ContainerDetail(
            summary: summary,
            configuration: .object([:]),
            status: .object([:]),
            raw: .object([:]),
            observedAt: summary.observedAt
        )
    }
}

private actor StubSSHReadinessChecker: SSHReadinessChecking {
    let isReady: Bool
    private(set) var checkedPorts: [Int] = []

    init(isReady: Bool) {
        self.isReady = isReady
    }

    func receivesSSHBanner(port: Int) async -> Bool {
        checkedPorts.append(port)
        return isReady
    }
}
