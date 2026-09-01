import Foundation
import XCTest

@testable import ContainerGUI

final class GitHubReleaseCheckerTests: XCTestCase {
    private let publishedAt = Date(timeIntervalSince1970: 1_788_192_000)

    func testSemanticVersionUsesNumericPrecedenceAndNormalizesStableTags() throws {
        XCTAssertEqual(try XCTUnwrap(SemanticVersion(" v2.17.0 ")).description, "2.17.0")
        XCTAssertEqual(try XCTUnwrap(SemanticVersion("2.17.0+build.4")).description, "2.17.0")
        XCTAssertGreaterThan(
            try XCTUnwrap(SemanticVersion("2.10.0")),
            try XCTUnwrap(SemanticVersion("2.9.9"))
        )
        XCTAssertNil(SemanticVersion("2.17"))
        XCTAssertNil(SemanticVersion("2.17.0-beta.1"))
        XCTAssertNil(SemanticVersion("2.-1.0"))
        XCTAssertNil(SemanticVersion("999999999999999999999.1.0"))
    }

    func testLatestStableReleaseUsesFixedGitHubEndpointAndReportsNewerVersion() async throws {
        let transport = RecordingReleaseTransport(responses: [
            response(tag: "v2.18.0", url: "https://github.com/zeal-odoo/ContainerGui/releases/tag/v2.18.0"),
        ])
        let checker = GitHubReleaseChecker(
            transport: transport,
            maximumResponseBytes: 128 * 1024,
            currentVersion: "2.17.0"
        )

        let summary = try await checker.checkForUpdates()

        XCTAssertEqual(summary.currentVersion, "2.17.0")
        XCTAssertEqual(summary.latestVersion, "2.18.0")
        XCTAssertTrue(summary.updateAvailable)
        XCTAssertEqual(summary.releaseURL.absoluteString, "https://github.com/zeal-odoo/ContainerGui/releases/tag/v2.18.0")
        XCTAssertEqual(summary.publishedAt, publishedAt)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url.scheme, "https")
        XCTAssertEqual(request.url.host, "api.github.com")
        XCTAssertEqual(request.url.path, "/repos/zeal-odoo/ContainerGui/releases/latest")
        XCTAssertEqual(request.headers["Accept"], "application/vnd.github+json")
        XCTAssertEqual(request.headers["X-GitHub-Api-Version"], "2022-11-28")
        XCTAssertEqual(request.headers["User-Agent"], "ContainerGUI/2.17.0")
    }

    func testEqualAndOlderReleasesAreNotUpdates() async throws {
        for tag in ["2.17.0", "v2.16.9"] {
            let checker = GitHubReleaseChecker(
                transport: RecordingReleaseTransport(responses: [
                    response(tag: tag, url: "https://github.com/zeal-odoo/ContainerGui/releases/tag/\(tag)"),
                ]),
                maximumResponseBytes: 128 * 1024,
                currentVersion: "2.17.0"
            )

            let summary = try await checker.checkForUpdates()
            XCTAssertFalse(summary.updateAvailable)
        }
    }

    func testDraftPrereleaseMalformedVersionAndUntrustedURLAreRejected() async throws {
        let bodies = [
            response(tag: "v2.18.0", url: "https://github.com/zeal-odoo/ContainerGui/releases/tag/v2.18.0", draft: true),
            response(tag: "v2.18.0", url: "https://github.com/zeal-odoo/ContainerGui/releases/tag/v2.18.0", prerelease: true),
            response(tag: "latest", url: "https://github.com/zeal-odoo/ContainerGui/releases/tag/latest"),
            response(tag: "v2.18.0", url: "https://example.com/zeal-odoo/ContainerGui/releases/tag/v2.18.0"),
            response(tag: "v2.18.0", url: "https://github.com/another/repository/releases/tag/v2.18.0"),
        ]

        for body in bodies {
            await assertUnavailable(response: body)
        }
    }

    func testOversizedNonSuccessMalformedAndTransportFailuresUseSafeRetryableProblem() async throws {
        await assertUnavailable(response: RegistryHTTPResponse(
            statusCode: 200,
            headers: [:],
            body: Data(repeating: 0, count: 65)
        ), maximumResponseBytes: 64)
        await assertUnavailable(response: RegistryHTTPResponse(
            statusCode: 429,
            headers: [:],
            body: Data("rate limited".utf8)
        ))
        await assertUnavailable(response: RegistryHTTPResponse(
            statusCode: 200,
            headers: [:],
            body: Data("not json".utf8)
        ))

        let checker = GitHubReleaseChecker(
            transport: RecordingReleaseTransport(responses: []),
            maximumResponseBytes: 128 * 1024,
            currentVersion: "2.17.0"
        )
        do {
            _ = try await checker.checkForUpdates()
            XCTFail("Expected unavailable problem")
        } catch let problem as ProblemDetail {
            XCTAssertEqual(problem.code, .updateCheckUnavailable)
            XCTAssertTrue(problem.retryable)
            XCTAssertFalse(problem.message.contains("noResponse"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func assertUnavailable(
        response: RegistryHTTPResponse,
        maximumResponseBytes: Int = 128 * 1024
    ) async {
        let checker = GitHubReleaseChecker(
            transport: RecordingReleaseTransport(responses: [response]),
            maximumResponseBytes: maximumResponseBytes,
            currentVersion: "2.17.0"
        )
        do {
            _ = try await checker.checkForUpdates()
            XCTFail("Expected unavailable problem")
        } catch let problem as ProblemDetail {
            XCTAssertEqual(problem.code, .updateCheckUnavailable)
            XCTAssertTrue(problem.retryable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func response(
        tag: String,
        url: String,
        draft: Bool = false,
        prerelease: Bool = false
    ) -> RegistryHTTPResponse {
        let published = ISO8601DateFormatter().string(from: publishedAt)
        let json = """
        {
          "tag_name": "\(tag)",
          "html_url": "\(url)",
          "draft": \(draft),
          "prerelease": \(prerelease),
          "published_at": "\(published)"
        }
        """
        return RegistryHTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8))
    }
}

private actor RecordingReleaseTransport: RegistryHTTPTransport {
    private var responses: [RegistryHTTPResponse]
    private(set) var requests: [RegistryHTTPRequest] = []

    init(responses: [RegistryHTTPResponse]) {
        self.responses = responses
    }

    func get(_ request: RegistryHTTPRequest) async throws -> RegistryHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw RecordingReleaseTransportError.noResponse }
        return responses.removeFirst()
    }
}

private enum RecordingReleaseTransportError: Error {
    case noResponse
}
