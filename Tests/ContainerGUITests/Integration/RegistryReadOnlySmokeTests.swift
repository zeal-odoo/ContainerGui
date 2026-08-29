import Foundation
import XCTest

@testable import ContainerGUI

final class RegistryReadOnlySmokeTests: XCTestCase {
    func testDockerHubSearchAndTagsAreReadable() async throws {
        guard ProcessInfo.processInfo.environment["CONTAINER_GUI_LIVE_REGISTRY_READONLY"] == "1" else {
            throw XCTSkip("Set CONTAINER_GUI_LIVE_REGISTRY_READONLY=1 to run external GET-only checks")
        }
        let client = RegistrySearchClient(
            transport: FoundationRegistryHTTPTransport(timeoutSeconds: 5),
            maximumResponseBytes: 2 * 1024 * 1024
        )

        let repositories = try await client.searchRepositories(RemoteRepositorySearchRequest(
            registry: .dockerHub,
            query: "postgres"
        ))
        XCTAssertFalse(repositories.items.isEmpty)
        XCTAssertTrue(repositories.items.allSatisfy { $0.reference.hasPrefix("docker.io/") })

        let tags = try await client.listTags(RemoteTagListRequest(
            registry: .dockerHub,
            repository: "library/postgres"
        ))
        XCTAssertFalse(tags.items.isEmpty)
        XCTAssertTrue(tags.items.allSatisfy { $0.reference.hasPrefix("docker.io/library/postgres:") })
    }
}
