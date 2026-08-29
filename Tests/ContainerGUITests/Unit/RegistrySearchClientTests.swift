import Foundation
import XCTest

@testable import ContainerGUI

final class RegistrySearchClientTests: XCTestCase {
    private let observedAt = Date(timeIntervalSince1970: 1_788_000_000)

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
        XCTAssertEqual(page.pageSize, 20)
        let recordedRequests = await transport.requests
        let request = try XCTUnwrap(recordedRequests.first)
        XCTAssertEqual(request.url.scheme, "https")
        XCTAssertEqual(request.url.host, "hub.docker.com")
        XCTAssertEqual(request.url.path, "/v2/search/repositories/")
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "query" })?.value, "postgres")
        XCTAssertEqual(query?.first(where: { $0.name == "page_size" })?.value, "20")
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
        let recordedRequests = await transport.requests
        let request = try XCTUnwrap(recordedRequests.first)
        XCTAssertEqual(request.url.host, "hub.docker.com")
        XCTAssertEqual(request.url.path, "/v2/namespaces/library/repositories/postgres/tags")
    }

    func testGHCRPackagesAndTagsUseScopedOfficialAPIAndBearerToken() async throws {
        let token = "fixture-read-only-token"
        let transport = RecordingRegistryTransport(responses: [
            RegistryHTTPResponse(
                statusCode: 200,
                headers: ["Link": #"<https://api.github.com/orgs/apple/packages?page=2>; rel="next""#],
                body: try fixture("github/packages-page-1.json")
            ),
            RegistryHTTPResponse(
                statusCode: 200,
                headers: ["link": #"<https://api.github.com/orgs/apple/packages/container/x/versions?page=2>; rel="next""#],
                body: try fixture("github/versions-page-1.json")
            ),
        ])
        let client = registryClient(transport: transport, githubToken: token)

        let repositories = try await client.searchRepositories(RemoteRepositorySearchRequest(
            registry: .ghcr,
            ownerType: .organization,
            owner: "apple",
            page: 1
        ))
        let tags = try await client.listTags(RemoteTagListRequest(
            registry: .ghcr,
            repository: "containerization/vminit",
            ownerType: .organization,
            owner: "apple",
            page: 1
        ))

        XCTAssertEqual(repositories.items.first?.reference, "ghcr.io/apple/containerization/vminit")
        XCTAssertTrue(repositories.hasNextPage)
        XCTAssertEqual(tags.items.map(\.reference), [
            "ghcr.io/apple/containerization/vminit:latest",
            "ghcr.io/apple/containerization/vminit:0.13.0",
            "ghcr.io/apple/containerization/vminit:0.12.0",
        ])
        XCTAssertTrue(tags.hasNextPage)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.url.host == "api.github.com" })
        XCTAssertTrue(requests.allSatisfy { $0.headers["Authorization"] == "Bearer \(token)" })
        XCTAssertTrue(requests.allSatisfy { $0.headers["X-GitHub-Api-Version"] == "2026-03-10" })
        XCTAssertTrue(requests[1].url.absoluteString.contains("containerization%2Fvminit"))
    }

    func testGHCRWithoutTokenFailsBeforeTransport() async throws {
        let transport = RecordingRegistryTransport(responses: [])
        let client = registryClient(transport: transport, githubToken: nil)

        do {
            _ = try await client.searchRepositories(RemoteRepositorySearchRequest(
                registry: .ghcr,
                ownerType: .user,
                owner: "octocat"
            ))
            XCTFail("Expected missing-token failure")
        } catch let problem as ProblemDetail {
            XCTAssertEqual(problem.code, .registryAuthenticationRequired)
            XCTAssertFalse(problem.retryable)
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testUpstreamAuthenticationAndRateLimitMapToSafeProblems() async throws {
        let secret = "fixture-secret-token-never-echo"
        let transport = RecordingRegistryTransport(responses: [
            RegistryHTTPResponse(statusCode: 401, headers: [:], body: Data("denied".utf8)),
            RegistryHTTPResponse(statusCode: 429, headers: [:], body: Data("slow down".utf8)),
        ])
        let client = registryClient(transport: transport, githubToken: secret)

        do {
            _ = try await client.searchRepositories(RemoteRepositorySearchRequest(
                registry: .ghcr,
                ownerType: .organization,
                owner: "apple"
            ))
            XCTFail("Expected authentication failure")
        } catch let problem as ProblemDetail {
            let encoded = String(decoding: try JSONEncoder.containerGUI.encode(problem), as: UTF8.self)
            XCTAssertEqual(problem.code, .registryAuthenticationRequired)
            XCTAssertFalse(encoded.contains(secret))
            XCTAssertFalse(encoded.contains("denied"))
        }

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
        let client = RegistrySearchClient(
            transport: transport,
            githubToken: nil,
            maximumResponseBytes: 64,
            now: { self.observedAt }
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
        transport: RecordingRegistryTransport,
        githubToken: String? = nil
    ) -> RegistrySearchClient<RecordingRegistryTransport> {
        RegistrySearchClient(
            transport: transport,
            githubToken: githubToken,
            maximumResponseBytes: 2 * 1024 * 1024,
            now: { self.observedAt }
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
