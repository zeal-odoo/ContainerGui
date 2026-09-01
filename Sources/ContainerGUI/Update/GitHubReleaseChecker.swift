import Foundation

struct GitHubReleaseChecker<Transport: RegistryHTTPTransport>: UpdateChecking {
    private static var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/zeal-odoo/ContainerGui/releases/latest")!
    }

    private let transport: Transport
    private let maximumResponseBytes: Int
    private let currentVersion: String

    init(
        transport: Transport,
        maximumResponseBytes: Int,
        currentVersion: String = AppVersion.current
    ) {
        self.transport = transport
        self.maximumResponseBytes = maximumResponseBytes
        self.currentVersion = currentVersion
    }

    func checkForUpdates() async throws -> UpdateSummary {
        guard let current = SemanticVersion(currentVersion) else {
            throw ProblemDetail(code: .updateCheckUnavailable)
        }
        let response: RegistryHTTPResponse
        do {
            response = try await transport.get(RegistryHTTPRequest(
                url: Self.latestReleaseURL,
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
              let releaseURL = validatedReleaseURL(payload.htmlURL) else {
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

private func validatedReleaseURL(_ url: URL) -> URL? {
    guard url.scheme?.lowercased() == "https",
          url.host?.lowercased() == "github.com",
          url.user == nil,
          url.password == nil,
          url.port == nil,
          url.query == nil,
          url.fragment == nil,
          url.path.hasPrefix("/zeal-odoo/ContainerGui/releases/") else { return nil }
    return url
}
