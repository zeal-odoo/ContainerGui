import Foundation

enum UpdateRepository: String, Sendable {
    case containerGUI = "zeal-odoo/ContainerGui"
    case appleContainer = "apple/container"
}

struct GitHubReleaseChecker<Transport: RegistryHTTPTransport>: UpdateChecking {
    private var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(repository.rawValue)/releases/latest")!
    }

    private let transport: Transport
    private let maximumResponseBytes: Int
    private let currentVersion: String
    private let repository: UpdateRepository

    init(
        transport: Transport,
        maximumResponseBytes: Int,
        currentVersion: String = AppVersion.current,
        repository: UpdateRepository = .containerGUI
    ) {
        self.transport = transport
        self.maximumResponseBytes = maximumResponseBytes
        self.currentVersion = currentVersion
        self.repository = repository
    }

    func checkForUpdates() async throws -> UpdateSummary {
        guard let current = SemanticVersion(currentVersion) else {
            throw ProblemDetail(code: .updateCheckUnavailable)
        }
        let response: RegistryHTTPResponse
        do {
            response = try await transport.get(RegistryHTTPRequest(
                url: latestReleaseURL,
                headers: [
                    "Accept": "application/vnd.github+json",
                    "X-GitHub-Api-Version": "2022-11-28",
                    "User-Agent": "ContainerGUI/\(current)",
                ]
            ))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProblemDetail(code: .updateCheckUnavailable)
        }

        guard (200..<300).contains(response.statusCode),
              response.body.count <= maximumResponseBytes,
              let payload = try? JSONDecoder.containerGUI.decode(GitHubReleasePayload.self, from: response.body),
              !payload.draft,
              !payload.prerelease,
              let latest = SemanticVersion(payload.tagName),
              let releaseURL = validatedReleaseURL(payload.htmlURL, repository: repository) else {
            throw ProblemDetail(code: .updateCheckUnavailable)
        }

        return UpdateSummary(
            currentVersion: current.description,
            latestVersion: latest.description,
            updateAvailable: latest > current,
            releaseURL: releaseURL,
            publishedAt: payload.publishedAt
        )
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let publishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease
        case publishedAt = "published_at"
    }
}

private func validatedReleaseURL(_ url: URL, repository: UpdateRepository) -> URL? {
    guard url.scheme?.lowercased() == "https",
          url.host?.lowercased() == "github.com",
          url.user == nil,
          url.password == nil,
          url.port == nil,
          url.query == nil,
          url.fragment == nil,
          url.path.hasPrefix("/\(repository.rawValue)/releases/") else { return nil }
    return url
}
