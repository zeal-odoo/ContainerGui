import Foundation
import XCTest

@testable import ContainerGUI

final class RegistrySearchClientTests: XCTestCase {
    private let observedAt = Date(timeIntervalSince1970: 1_788_000_000)

    func testGHCRIsNotAnAcceptedRegistry() {
        XCTAssertNil(RemoteRegistry(rawValue: "ghcr"))
    }

    func testDockerHubRepositorySearchUsesFixedHostAndNormalizesOfficialImage() async throws {
        let transport = RecordingRegistryTransport(responses: [
            RegistryHTTPResponse(
                statusCode: 200,
                headers: [:],
                body: try fixture("docker-hub/repositories-page-1.json")
            ),
        ])
        let client = registryClient(transport: transport)

        let page = try await client.searchRepositories(RemoteRepositorySearchRequest(
            registry: .dockerHub,
            query: "postgres",
            page: 1
        ))

        XCTAssertEqual(page.items.map(\.reference), [
            "docker.io/library/postgres",
            "docker.io/cimg/postgres",
        ])
        XCTAssertEqual(page.totalCount, 3)
        XCTAssertTrue(page.hasNextPage)
        XCTAssertEqual(page.pageSize, 10)
        let recordedRequests = await transport.requests
        let request = try XCTUnwrap(recordedRequests.first)
        XCTAssertEqual(request.url.scheme, "https")
        XCTAssertEqual(request.url.host, "hub.docker.com")
        XCTAssertEqual(request.url.path, "/v2/search/repositories")
        XCTAssertTrue(request.url.absoluteString.contains("/v2/search/repositories/?"))
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "query" })?.value, "postgres")
        XCTAssertEqual(query?.first(where: { $0.name == "page_size" })?.value, "10")
        XCTAssertEqual(query?.first(where: { $0.name == "page" })?.value, "1")
    }

    func testDockerHubTagsReturnExactReferencesAndPagination() async throws {
        let transport = RecordingRegistryTransport(responses: [
            RegistryHTTPResponse(
                statusCode: 200,
                headers: [:],
                body: try fixture("docker-hub/tags-page-1.json")
            ),
        ])

        let page = try await registryClient(transport: transport).listTags(RemoteTagListRequest(
            registry: .dockerHub,
            repository: "library/postgres",
            page: 1
        ))

        XCTAssertEqual(page.items.map(\.name), ["latest", "17.6"])
        XCTAssertEqual(page.items.first?.reference, "docker.io/library/postgres:latest")
        XCTAssertEqual(page.items.first?.sizeBytes, 161_067_506)
        XCTAssertTrue(page.hasNextPage)
        XCTAssertEqual(page.pageSize, 10)
        let recordedRequests = await transport.requests
        let request = try XCTUnwrap(recordedRequests.first)
        XCTAssertEqual(request.url.host, "hub.docker.com")
        XCTAssertEqual(request.url.path, "/v2/namespaces/library/repositories/postgres/tags")
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "page_size" })?.value, "10")
    }

    func testRateLimitMapsToSafeProblem() async throws {
        let transport = RecordingRegistryTransport(responses: [
            RegistryHTTPResponse(statusCode: 429, headers: [:], body: Data("slow down".utf8)),
        ])
        let client = registryClient(transport: transport)

        do {
            _ = try await client.searchRepositories(RemoteRepositorySearchRequest(
                registry: .dockerHub,
                query: "postgres"
            ))
            XCTFail("Expected rate limit")
        } catch let problem as ProblemDetail {
            XCTAssertEqual(problem.code, .registryRateLimited)
            XCTAssertTrue(problem.retryable)
        }
    }

    func testValidationAndResponseLimitRejectBeforeParsing() async throws {
        let transport = RecordingRegistryTransport(responses: [
            RegistryHTTPResponse(statusCode: 200, headers: [:], body: Data(repeating: 0, count: 65)),
        ])
        let timestamp = observedAt
        let client = RegistrySearchClient(
            transport: transport,
            maximumResponseBytes: 64,
            now: { timestamp }
        )

        do {
            _ = try await client.searchRepositories(RemoteRepositorySearchRequest(
                registry: .dockerHub,
                query: "postgres",
                page: 0
            ))
            XCTFail("Expected page validation failure")
        } catch let problem as ProblemDetail {
            XCTAssertEqual(problem.code, .validationFailed)
            XCTAssertEqual(problem.fieldErrors?.map(\.field), ["page"])
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)

        do {
            _ = try await client.searchRepositories(RemoteRepositorySearchRequest(
                registry: .dockerHub,
                query: "postgres"
            ))
            XCTFail("Expected response-size failure")
        } catch let problem as ProblemDetail {
            XCTAssertEqual(problem.code, .registryUnavailable)
            XCTAssertTrue(problem.retryable)
        }
    }

    private func registryClient(
        transport: RecordingRegistryTransport
    ) -> RegistrySearchClient<RecordingRegistryTransport> {
        let timestamp = observedAt
        return RegistrySearchClient(
            transport: transport,
            maximumResponseBytes: 2 * 1024 * 1024,
            now: { timestamp }
        )
    }

    private func fixture(_ path: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: path,
                withExtension: nil,
                subdirectory: "Fixtures/Registry"
            )
        )
        return try Data(contentsOf: url)
    }
}

private actor RecordingRegistryTransport: RegistryHTTPTransport {
    private var responses: [RegistryHTTPResponse]
    private(set) var requests: [RegistryHTTPRequest] = []

    init(responses: [RegistryHTTPResponse]) {
        self.responses = responses
    }

    func get(_ request: RegistryHTTPRequest) async throws -> RegistryHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw RecordingRegistryTransportError.noResponse }
        return responses.removeFirst()
    }
}

private enum RecordingRegistryTransportError: Error {
    case noResponse
}
