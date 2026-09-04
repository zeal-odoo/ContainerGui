import Foundation
import Hummingbird
import HummingbirdTesting
import XCTest

@testable import ContainerGUI

final class RegistrySearchAPITests: XCTestCase {
    func testRepositoryAndTagRoutesReturnPagedResponses() async throws {
        let searcher = StubRegistrySearcher()
        let app = makeApplication(searcher: searcher)

        try await app.testLocal { client in
            try await client.execute(
                uri: "/api/v1/registry-search/repositories?registry=dockerHub&query=postgres&page=2",
                method: .get
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let page = try JSONDecoder.containerGUI.decode(RemoteRepositoryPage.self, from: response.body)
                XCTAssertEqual(page.items.first?.reference, "docker.io/library/postgres")
                XCTAssertEqual(page.page, 2)
                XCTAssertEqual(page.pageSize, 10)
                XCTAssertTrue(page.hasNextPage)
            }

            try await client.execute(
                uri: "/api/v1/registry-search/tags?registry=dockerHub&repository=library%2Fpostgres&page=1",
                method: .get
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let page = try JSONDecoder.containerGUI.decode(RemoteTagPage.self, from: response.body)
                XCTAssertEqual(page.items.first?.reference, "docker.io/library/postgres:17.6")
                XCTAssertEqual(page.pageSize, 10)
                XCTAssertFalse(page.hasNextPage)
            }
        }

        let requests = await searcher.requests
        XCTAssertEqual(requests, [
            .repositories(RemoteRepositorySearchRequest(registry: .dockerHub, query: "postgres", page: 2)),
            .tags(RemoteTagListRequest(registry: .dockerHub, repository: "library/postgres", page: 1)),
        ])
    }

    func testGHCRProviderIsRejectedWithoutCallingSearcher() async throws {
        let searcher = StubRegistrySearcher()
        let app = makeApplication(searcher: searcher)

        try await app.testLocal { client in
            try await client.execute(
                uri: "/api/v1/registry-search/repositories?registry=ghcr&ownerType=organization&owner=apple&page=1",
                method: .get
            ) { response in
                XCTAssertEqual(response.status, .unprocessableContent)
                let problem = try JSONDecoder.containerGUI.decode(ProblemDetail.self, from: response.body)
                XCTAssertEqual(problem.code, .validationFailed)
                XCTAssertEqual(problem.fieldErrors?.map(\.field), ["registry"])
            }
        }

        let requests = await searcher.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testInvalidQueriesReturnFieldErrorsWithoutCallingSearcher() async throws {
        let searcher = StubRegistrySearcher()
        let app = makeApplication(searcher: searcher)

        try await app.testLocal { client in
            for (uri, expectedField) in [
                ("/api/v1/registry-search/repositories?registry=dockerHub", "query"),
                ("/api/v1/registry-search/repositories?registry=unknown&query=x", "registry"),
                ("/api/v1/registry-search/tags?registry=dockerHub&repository=postgres&page=0", "page"),
            ] {
                try await client.execute(uri: uri, method: .get) { response in
                    XCTAssertEqual(response.status, .unprocessableContent)
                    let problem = try JSONDecoder.containerGUI.decode(ProblemDetail.self, from: response.body)
                    XCTAssertEqual(problem.code, .validationFailed)
                    XCTAssertTrue(problem.fieldErrors?.contains(where: { $0.field == expectedField }) == true)
                }
            }
        }

        let requests = await searcher.requests
        XCTAssertTrue(requests.isEmpty)
    }

    private func makeApplication(
        searcher: StubRegistrySearcher
    ) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router()
        router.middlewares.add(ErrorMiddleware())
        RegistrySearchRoutes.register(on: router, searcher: searcher)
        return Application(router: router)
    }
}

private actor StubRegistrySearcher: RegistrySearching {
    enum Request: Equatable {
        case repositories(RemoteRepositorySearchRequest)
        case tags(RemoteTagListRequest)
    }

    private(set) var requests: [Request] = []
    private let observedAt = Date(timeIntervalSince1970: 1_788_000_000)

    func searchRepositories(_ request: RemoteRepositorySearchRequest) async throws -> RemoteRepositoryPage {
        requests.append(.repositories(request))
        return RemoteRepositoryPage(
            items: [RemoteRepositorySummary(
                registry: request.registry,
                repository: "library/postgres",
                reference: "docker.io/library/postgres",
                name: "postgres",
                namespace: "library",
                description: "PostgreSQL",
                isOfficial: true,
                starCount: 10,
                pullCount: 20,
                updatedAt: nil
            )],
            page: request.page,
            pageSize: 10,
            totalCount: 3,
            hasNextPage: true,
            observedAt: observedAt
        )
    }

    func listTags(_ request: RemoteTagListRequest) async throws -> RemoteTagPage {
        requests.append(.tags(request))
        return RemoteTagPage(
            items: [RemoteTagSummary(
                name: "17.6",
                reference: "docker.io/library/postgres:17.6",
                digest: "sha256:" + String(repeating: "a", count: 64),
                sizeBytes: 160_000_000,
                updatedAt: observedAt
            )],
            page: request.page,
            pageSize: 10,
            totalCount: 1,
            hasNextPage: false,
            observedAt: observedAt
        )
    }
}
