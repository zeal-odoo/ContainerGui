import Foundation

struct RegistryHTTPRequest: Equatable, Sendable {
    let url: URL
    let headers: [String: String]
}

struct RegistryHTTPResponse: Equatable, Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

protocol RegistryHTTPTransport: Sendable {
    func get(_ request: RegistryHTTPRequest) async throws -> RegistryHTTPResponse
}

protocol RegistrySearching: Sendable {
    func searchRepositories(_ request: RemoteRepositorySearchRequest) async throws -> RemoteRepositoryPage
    func listTags(_ request: RemoteTagListRequest) async throws -> RemoteTagPage
}

struct FoundationRegistryHTTPTransport: RegistryHTTPTransport {
    private let session: URLSession
    private let timeoutSeconds: TimeInterval

    init(timeoutSeconds: TimeInterval = 5) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        self.session = URLSession(
            configuration: configuration,
            delegate: RegistryNoRedirectDelegate(),
            delegateQueue: nil
        )
        self.timeoutSeconds = timeoutSeconds
    }

    func get(_ request: RegistryHTTPRequest) async throws -> RegistryHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = timeoutSeconds
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: urlRequest)
        guard let response = response as? HTTPURLResponse else {
            throw RegistryTransportError.invalidResponse
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            guard let key = item.key as? String, let value = item.value as? String else { return }
            result[key] = value
        }
        return RegistryHTTPResponse(statusCode: response.statusCode, headers: headers, body: data)
    }
}

struct RegistrySearchClient<Transport: RegistryHTTPTransport>: RegistrySearching {
    private static var pageSize: Int { 20 }

    private let transport: Transport
    private let githubToken: String?
    private let maximumResponseBytes: Int
    private let now: @Sendable () -> Date

    init(
        transport: Transport,
        githubToken: String?,
        maximumResponseBytes: Int,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.githubToken = githubToken
        self.maximumResponseBytes = maximumResponseBytes
        self.now = now
    }

    func searchRepositories(_ unvalidated: RemoteRepositorySearchRequest) async throws -> RemoteRepositoryPage {
        let request = try unvalidated.validated()
        switch request.registry {
        case .dockerHub:
            return try await searchDockerHub(request)
        case .ghcr:
            return try await listGHCRPackages(request)
        }
    }

    func listTags(_ unvalidated: RemoteTagListRequest) async throws -> RemoteTagPage {
        let request = try unvalidated.validated()
        switch request.registry {
        case .dockerHub:
            return try await listDockerHubTags(request)
        case .ghcr:
            return try await listGHCRTags(request)
        }
    }

    private func searchDockerHub(_ request: RemoteRepositorySearchRequest) async throws -> RemoteRepositoryPage {
        let url = try fixedURL(
            host: "hub.docker.com",
            path: "/v2/search/repositories/",
            queryItems: [
                URLQueryItem(name: "query", value: request.query),
                URLQueryItem(name: "page_size", value: String(Self.pageSize)),
                URLQueryItem(name: "page", value: String(request.page)),
            ]
        )
        let response = try await response(for: RegistryHTTPRequest(
            url: url,
            headers: ["Accept": "application/json"]
        ), registry: .dockerHub)
        let decoded: DockerHubRepositoryPage
        do {
            decoded = try JSONDecoder().decode(DockerHubRepositoryPage.self, from: response.body)
        } catch {
            throw ProblemDetail(code: .registryUnavailable)
        }

        var seen = Set<String>()
        let items = decoded.results.compactMap { result -> RemoteRepositorySummary? in
            guard let normalized = normalizeDockerRepository(result.repositoryName),
                  seen.insert(normalized.repository).inserted else { return nil }
            return RemoteRepositorySummary(
                registry: .dockerHub,
                repository: normalized.repository,
                reference: "docker.io/\(normalized.repository)",
                name: normalized.name,
                namespace: normalized.namespace,
                description: safeDescription(result.description),
                isOfficial: result.isOfficial,
                starCount: nonnegative(result.starCount),
                pullCount: nonnegative(result.pullCount),
                updatedAt: nil
            )
        }
        return RemoteRepositoryPage(
            items: items,
            page: request.page,
            pageSize: Self.pageSize,
            totalCount: max(0, decoded.count),
            hasNextPage: decoded.next != nil,
            observedAt: now()
        )
    }

    private func listDockerHubTags(_ request: RemoteTagListRequest) async throws -> RemoteTagPage {
        let components = request.repository.split(separator: "/").map(String.init)
        let url = try fixedURL(
            host: "hub.docker.com",
            path: "/v2/namespaces/\(components[0])/repositories/\(components[1])/tags",
            queryItems: [
                URLQueryItem(name: "page_size", value: String(Self.pageSize)),
                URLQueryItem(name: "page", value: String(request.page)),
            ]
        )
        let response = try await response(for: RegistryHTTPRequest(
            url: url,
            headers: ["Accept": "application/json"]
        ), registry: .dockerHub)
        let decoded: DockerHubTagPage
        do {
            decoded = try JSONDecoder().decode(DockerHubTagPage.self, from: response.body)
        } catch {
            throw ProblemDetail(code: .registryUnavailable)
        }

        var seen = Set<String>()
        let items = decoded.results.compactMap { tag -> RemoteTagSummary? in
            guard isValidRemoteTag(tag.name), seen.insert(tag.name).inserted else { return nil }
            return RemoteTagSummary(
                name: tag.name,
                reference: "docker.io/\(request.repository):\(tag.name)",
                digest: validDigest(tag.digest),
                sizeBytes: tag.fullSize,
                updatedAt: parseDate(tag.lastUpdated)
            )
        }
        return RemoteTagPage(
            items: items,
            page: request.page,
            pageSize: Self.pageSize,
            totalCount: max(0, decoded.count),
            hasNextPage: decoded.next != nil,
            observedAt: now()
        )
    }

    private func listGHCRPackages(_ request: RemoteRepositorySearchRequest) async throws -> RemoteRepositoryPage {
        let owner = request.owner!
        let url = try githubURL(
            ownerType: request.ownerType!,
            owner: owner,
            suffix: "/packages",
            queryItems: [
                URLQueryItem(name: "package_type", value: "container"),
                URLQueryItem(name: "visibility", value: "public"),
                URLQueryItem(name: "per_page", value: String(Self.pageSize)),
                URLQueryItem(name: "page", value: String(request.page)),
            ]
        )
        let response = try await response(
            for: RegistryHTTPRequest(url: url, headers: try githubHeaders()),
            registry: .ghcr
        )
        let decoded: [GitHubPackage]
        do {
            decoded = try JSONDecoder().decode([GitHubPackage].self, from: response.body)
        } catch {
            throw ProblemDetail(code: .registryUnavailable)
        }

        var seen = Set<String>()
        let items = decoded.compactMap { package -> RemoteRepositorySummary? in
            guard package.packageType == "container",
                  isValidRepositoryPath(package.name),
                  seen.insert(package.name).inserted else { return nil }
            return RemoteRepositorySummary(
                registry: .ghcr,
                repository: package.name,
                reference: "ghcr.io/\(owner)/\(package.name)",
                name: package.name,
                namespace: owner,
                description: safeDescription(package.description),
                isOfficial: nil,
                starCount: nil,
                pullCount: nil,
                updatedAt: parseDate(package.updatedAt)
            )
        }
        return RemoteRepositoryPage(
            items: items,
            page: request.page,
            pageSize: Self.pageSize,
            totalCount: nil,
            hasNextPage: hasNextLink(response.headers),
            observedAt: now()
        )
    }

    private func listGHCRTags(_ request: RemoteTagListRequest) async throws -> RemoteTagPage {
        let url = try githubURL(
            ownerType: request.ownerType!,
            owner: request.owner!,
            suffix: "/packages/container/\(encodedPathSegment(request.repository))/versions",
            queryItems: [
                URLQueryItem(name: "per_page", value: String(Self.pageSize)),
                URLQueryItem(name: "page", value: String(request.page)),
            ]
        )
        let response = try await response(
            for: RegistryHTTPRequest(url: url, headers: try githubHeaders()),
            registry: .ghcr
        )
        let decoded: [GitHubPackageVersion]
        do {
            decoded = try JSONDecoder().decode([GitHubPackageVersion].self, from: response.body)
        } catch {
            throw ProblemDetail(code: .registryUnavailable)
        }

        var seen = Set<String>()
        var items: [RemoteTagSummary] = []
        for version in decoded where version.metadata?.packageType == "container" {
            for tag in version.metadata?.container?.tags ?? []
                where isValidRemoteTag(tag) && seen.insert(tag).inserted {
                items.append(RemoteTagSummary(
                    name: tag,
                    reference: "ghcr.io/\(request.owner!)/\(request.repository):\(tag)",
                    digest: validDigest(version.name),
                    sizeBytes: nil,
                    updatedAt: parseDate(version.updatedAt)
                ))
            }
        }
        return RemoteTagPage(
            items: items,
            page: request.page,
            pageSize: Self.pageSize,
            totalCount: nil,
            hasNextPage: hasNextLink(response.headers),
            observedAt: now()
        )
    }

    private func response(
        for request: RegistryHTTPRequest,
        registry: RemoteRegistry
    ) async throws -> RegistryHTTPResponse {
        let response: RegistryHTTPResponse
        do {
            response = try await transport.get(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProblemDetail(code: .registryUnavailable)
        }
        guard response.body.count <= maximumResponseBytes else {
            throw ProblemDetail(code: .registryUnavailable)
        }
        switch response.statusCode {
        case 200..<300:
            return response
        case 401 where registry == .ghcr,
             403 where registry == .ghcr:
            throw ProblemDetail(code: .registryAuthenticationRequired)
        case 429:
            throw ProblemDetail(code: .registryRateLimited)
        default:
            throw ProblemDetail(code: .registryUnavailable)
        }
    }

    private func githubHeaders() throws -> [String: String] {
        guard let githubToken, !githubToken.isEmpty else {
            throw ProblemDetail(code: .registryAuthenticationRequired)
        }
        return [
            "Accept": "application/vnd.github+json",
            "Authorization": "Bearer \(githubToken)",
            "X-GitHub-Api-Version": "2026-03-10",
            "User-Agent": "ContainerGUI",
        ]
    }
}

private final class RegistryNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private enum RegistryTransportError: Error {
    case invalidResponse
}

private struct DockerHubRepositoryPage: Decodable {
    let count: Int
    let next: String?
    let results: [DockerHubRepository]
}

private struct DockerHubRepository: Decodable {
    let repositoryName: String
    let description: String?
    let starCount: Int?
    let pullCount: Int?
    let isOfficial: Bool?

    enum CodingKeys: String, CodingKey {
        case repositoryName = "repo_name"
        case description = "short_description"
        case starCount = "star_count"
        case pullCount = "pull_count"
        case isOfficial = "is_official"
    }
}

private struct DockerHubTagPage: Decodable {
    let count: Int
    let next: String?
    let results: [DockerHubTag]
}

private struct DockerHubTag: Decodable {
    let name: String
    let digest: String?
    let fullSize: UInt64?
    let lastUpdated: String?

    enum CodingKeys: String, CodingKey {
        case name, digest
        case fullSize = "full_size"
        case lastUpdated = "last_updated"
    }
}

private struct GitHubPackage: Decodable {
    let name: String
    let packageType: String
    let description: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case name, description
        case packageType = "package_type"
        case updatedAt = "updated_at"
    }
}

private struct GitHubPackageVersion: Decodable {
    let name: String
    let updatedAt: String?
    let metadata: GitHubPackageMetadata?

    enum CodingKeys: String, CodingKey {
        case name, metadata
        case updatedAt = "updated_at"
    }
}

private struct GitHubPackageMetadata: Decodable {
    let packageType: String
    let container: GitHubContainerMetadata?

    enum CodingKeys: String, CodingKey {
        case container
        case packageType = "package_type"
    }
}

private struct GitHubContainerMetadata: Decodable {
    let tags: [String]
}

private func fixedURL(host: String, path: String, queryItems: [URLQueryItem]) throws -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = host
    components.percentEncodedPath = path
    components.queryItems = queryItems
    guard let url = components.url else { throw ProblemDetail(code: .registryUnavailable) }
    return url
}

private func githubURL(
    ownerType: GHCRNamespaceType,
    owner: String,
    suffix: String,
    queryItems: [URLQueryItem]
) throws -> URL {
    let scope = ownerType == .organization ? "orgs" : "users"
    return try fixedURL(
        host: "api.github.com",
        path: "/\(scope)/\(owner)\(suffix)",
        queryItems: queryItems
    )
}

private func encodedPathSegment(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
}

private func normalizeDockerRepository(_ value: String) -> (repository: String, namespace: String, name: String)? {
    let rawComponents = value.split(separator: "/").map(String.init)
    let components = rawComponents.count == 1 ? ["library", rawComponents[0]] : rawComponents
    guard components.count == 2 else { return nil }
    let repository = components.joined(separator: "/")
    guard isValidRepositoryPath(repository) else { return nil }
    return (repository, components[0], components[1])
}

private func safeDescription(_ value: String?) -> String? {
    guard let value else { return nil }
    return String(value.prefix(2_048))
}

private func nonnegative(_ value: Int?) -> Int? {
    guard let value, value >= 0 else { return nil }
    return value
}

private func validDigest(_ value: String?) -> String? {
    guard let value, value.range(
        of: #"^sha256:[0-9a-f]{64}$"#,
        options: .regularExpression
    ) != nil else { return nil }
    return value
}

private func parseDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}

private func hasNextLink(_ headers: [String: String]) -> Bool {
    headers.first { $0.key.caseInsensitiveCompare("Link") == .orderedSame }?
        .value.contains(#"rel="next""#) == true
}
