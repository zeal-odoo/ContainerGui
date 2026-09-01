import Foundation
import Hummingbird
import HummingbirdTesting
import XCTest

@testable import ContainerGUI

final class UpdateCheckAPITests: XCTestCase {
    func testReadOnlyRouteReturnsVersionComparisonAndOfficialReleaseURL() async throws {
        let checker = StubUpdateChecker()
        let app = makeApplication(checker: checker)

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/v1/update-check", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let summary = try JSONDecoder.containerGUI.decode(UpdateSummary.self, from: response.body)
                XCTAssertEqual(summary.currentVersion, "2.17.0")
                XCTAssertEqual(summary.latestVersion, "2.18.0")
                XCTAssertTrue(summary.updateAvailable)
                XCTAssertEqual(
                    summary.releaseURL.absoluteString,
                    "https://github.com/zeal-odoo/ContainerGui/releases/tag/v2.18.0"
                )
            }
        }
        let callCount = await checker.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testFailureUsesSafeRetryableProblemEnvelope() async throws {
        let checker = StubUpdateChecker(problem: ProblemDetail(code: .updateCheckUnavailable))
        let app = makeApplication(checker: checker)

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/v1/update-check", method: .get) { response in
                XCTAssertEqual(response.status, .badGateway)
                XCTAssertTrue(response.headers[.contentType]?.hasPrefix("application/problem+json") == true)
                let problem = try JSONDecoder.containerGUI.decode(ProblemDetail.self, from: response.body)
                XCTAssertEqual(problem.code, .updateCheckUnavailable)
                XCTAssertTrue(problem.retryable)
            }
        }
    }

    private func makeApplication(
        checker: StubUpdateChecker
    ) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router()
        router.middlewares.add(ErrorMiddleware())
        UpdateCheckRoutes.register(on: router, checker: checker)
        return Application(router: router)
    }
}

private actor StubUpdateChecker: UpdateChecking {
    private(set) var callCount = 0
    private let problem: ProblemDetail?

    init(problem: ProblemDetail? = nil) {
        self.problem = problem
    }

    func checkForUpdates() async throws -> UpdateSummary {
        callCount += 1
        if let problem { throw problem }
        return UpdateSummary(
            currentVersion: "2.17.0",
            latestVersion: "2.18.0",
            updateAvailable: true,
            releaseURL: URL(string: "https://github.com/zeal-odoo/ContainerGui/releases/tag/v2.18.0")!,
            publishedAt: Date(timeIntervalSince1970: 1_788_192_000)
        )
    }
}
