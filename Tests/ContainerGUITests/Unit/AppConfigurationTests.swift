import XCTest

@testable import ContainerGUI

final class AppConfigurationTests: XCTestCase {
    func testDefaultsAreLoopbackAndBounded() throws {
        let configuration = try AppConfiguration(environment: [:])

        XCTAssertEqual(configuration.host, "127.0.0.1")
        XCTAssertEqual(configuration.port, 8787)
        XCTAssertEqual(configuration.maximumRequestBodyBytes, 64 * 1024)
        XCTAssertEqual(configuration.maximumCommandOutputBytes, 16 * 1024 * 1024)
        XCTAssertEqual(configuration.queryTimeout, .seconds(5))
        XCTAssertEqual(configuration.mutationTimeout, .seconds(30))
        XCTAssertEqual(configuration.imagePullTimeout, .seconds(30 * 60))
        XCTAssertEqual(configuration.operationTTL, .seconds(15 * 60))
        XCTAssertEqual(configuration.maximumConcurrentMutations, 4)
        XCTAssertEqual(configuration.maximumOperationRecords, 1_000)
        XCTAssertEqual(configuration.maximumLogSessions, 8)
        XCTAssertEqual(configuration.maximumRegistryResponseBytes, 2 * 1024 * 1024)
        XCTAssertEqual(configuration.registryTimeoutSeconds, 5)
        XCTAssertNil(configuration.githubToken)
    }

    func testAcceptsPortAndExplicitCLIPath() throws {
        let configuration = try AppConfiguration(environment: [
            "CONTAINER_GUI_PORT": "49152",
            "CONTAINER_GUI_CLI_PATH": "/opt/homebrew/bin/container",
        ])

        XCTAssertEqual(configuration.host, "127.0.0.1")
        XCTAssertEqual(configuration.port, 49152)
        XCTAssertEqual(configuration.explicitCLIPath, "/opt/homebrew/bin/container")
        XCTAssertEqual(configuration.origin, "http://127.0.0.1:49152")
    }

    func testRejectsInvalidPorts() {
        for value in ["0", "1023", "65536", "abc"] {
            XCTAssertThrowsError(try AppConfiguration(environment: ["CONTAINER_GUI_PORT": value])) { error in
                XCTAssertTrue(error is AppConfigurationError)
            }
        }
    }

    func testRejectsEmptyExplicitCLIPath() {
        XCTAssertThrowsError(try AppConfiguration(environment: ["CONTAINER_GUI_CLI_PATH": "   "]))
    }

    func testReadsGHCRTokenOnlyFromDedicatedEnvironmentVariable() throws {
        let configuration = try AppConfiguration(environment: [
            "CONTAINER_GUI_GITHUB_TOKEN": "github-read-only-token",
            "GITHUB_TOKEN": "must-not-be-used",
        ])

        XCTAssertEqual(configuration.githubToken, "github-read-only-token")
        XCTAssertNil(try AppConfiguration(environment: ["CONTAINER_GUI_GITHUB_TOKEN": "  "]).githubToken)
    }
}
