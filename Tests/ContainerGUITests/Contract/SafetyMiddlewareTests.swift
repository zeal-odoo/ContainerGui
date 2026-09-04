import Hummingbird
import HummingbirdTesting
import HTTPTypes
import XCTest

@testable import ContainerGUI

final class SafetyMiddlewareTests: XCTestCase {
    func testAcceptsOnlySameOriginJSONMutations() {
        let policy = RequestSafetyPolicy(
            expectedOrigin: "http://127.0.0.1:8787",
            maximumBodyBytes: 64 * 1024
        )

        XCTAssertNil(
            policy.validateMutation(
                origin: "http://127.0.0.1:8787",
                contentType: "application/json; charset=utf-8",
                contentLength: 2
            )
        )
        XCTAssertEqual(policy.validateMutation(origin: nil, contentType: "application/json", contentLength: 2)?.code, .originRejected)
        XCTAssertEqual(policy.validateMutation(origin: "https://evil.example", contentType: "application/json", contentLength: 2)?.code, .originRejected)
        XCTAssertEqual(policy.validateMutation(origin: "http://127.0.0.1:8787", contentType: "text/plain", contentLength: 2)?.code, .validationFailed)
        XCTAssertEqual(policy.validateMutation(origin: "http://127.0.0.1:8787", contentType: "application/json", contentLength: 65 * 1024)?.code, .requestTooLarge)
    }

    func testMiddlewareRejectsMissingOriginAndAddsSecurityHeaders() async throws {
        let router = Router()
        router.middlewares.add(
            SafetyMiddleware(
                policy: RequestSafetyPolicy(
                    expectedOrigin: "http://127.0.0.1:8787",
                    maximumBodyBytes: 64 * 1024
                )
            )
        )
        router.post("/mutate") { _, _ in "ok" }
        router.get("/read") { _, _ in "ok" }
        let app = Application(router: router)

        try await app.testLocal { client in
            try await client.execute(uri: "/mutate", method: .post, headers: [.contentType: "application/json"], body: ByteBuffer(string: "{}")) { response in
                XCTAssertEqual(response.status, .forbidden)
                XCTAssertNil(response.headers[.accessControlAllowOrigin])
            }
            try await client.execute(uri: "/mutate", method: .post, headers: [.origin: "http://127.0.0.1:8787", .contentType: "application/json"], body: ByteBuffer(string: "{}")) { response in
                XCTAssertEqual(response.status, .ok)
            }
            try await client.execute(uri: "/read", method: .get) { response in
                XCTAssertNotNil(response.headers[HTTPField.Name("Content-Security-Policy")!])
                XCTAssertEqual(response.headers[HTTPField.Name("X-Frame-Options")!], "DENY")
                XCTAssertEqual(response.headers[HTTPField.Name("X-Content-Type-Options")!], "nosniff")
                XCTAssertNil(response.headers[.accessControlAllowOrigin])
            }
        }
    }

    func testRejectsUnexpectedAuthorityForReadsAndMutations() async throws {
        let authorities: [String?] = [
            nil, "", "localhost", "127.0.0.1", "127.0.0.1:8788",
            "evil.example:8787", "127.0.0.1.evil.example:8787",
            "127.0.0.1:8787@evil.example", "127.0.0.1.:8787",
            "127.1:8787", "[::1]:8787", "127.0.0.1:8787,evil.example",
            "127.0.0.1:8787/path", "127.0.0.1:8787?query", "127.0.0.1 :8787",
        ]
        let app = Application(router: safetyRouter())
        for authority in authorities {
            try await app.testLocal(authority: authority) { client in
                for method: HTTPRequest.Method in [.get, .head, .post, .options] {
                    try await client.execute(uri: "/probe", method: method, headers: [
                        .origin: "http://127.0.0.1:8787", .contentType: "application/json",
                    ]) { response in
                        XCTAssertEqual(response.status, .forbidden, "authority: \(authority ?? "nil"), method: \(method)")
                        XCTAssertEqual(response.headers[.cacheControl], "no-store")
                    }
                }
            }
        }
    }

    func testRejectsDuplicateHostAndForeignOriginOnReads() async throws {
        let app = Application(router: safetyRouter())
        try await app.testLocal { client in
            // HTTP/1 moves the first Host into authority; any remaining Host is a duplicate.
            let rejectedHeaders: [HTTPFields] = [
                [HTTPField.Name("Host")!: "evil.example"], [HTTPField.Name("Host")!: "127.0.0.1:8787"],
                [.origin: "https://evil.example"], [.origin: "null"],
                [.origin: "http://127.0.0.1:8788"],
            ]
            for headers in rejectedHeaders {
                try await client.execute(uri: "/probe", method: .get, headers: headers) { response in
                    XCTAssertEqual(response.status, .forbidden)
                    XCTAssertNil(response.headers[.accessControlAllowOrigin])
                }
            }
            try await client.execute(uri: "/probe", method: .get, headers: [
                .origin: "http://127.0.0.1:8787",
                HTTPField.Name("X-Forwarded-Host")!: "evil.example",
            ]) { response in
                XCTAssertEqual(response.status, .ok)
            }
        }
    }

    func testAuthorityMatchesTheConfiguredPort() async throws {
        let app = Application(router: safetyRouter(origin: "http://127.0.0.1:9123"))
        try await app.testLocal(authority: "127.0.0.1:9123") { client in
            try await client.execute(uri: "/probe", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
            }
        }
        try await app.testLocal { client in
            try await client.execute(uri: "/probe", method: .get) { response in
                XCTAssertEqual(response.status, .forbidden)
            }
        }
    }

    func testAcceptsCanonicalAuthorityAfterHTTPWhitespaceNormalization() async throws {
        let app = Application(router: safetyRouter())
        // HTTPTypes strips optional surrounding whitespace when assigning a field value.
        try await app.testLocal(authority: " 127.0.0.1:8787 ") { client in
            try await client.execute(uri: "/probe", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
            }
        }
    }

    private func safetyRouter(origin: String = "http://127.0.0.1:8787") -> Router<BasicRequestContext> {
        let router = Router()
        router.middlewares.add(SafetyMiddleware(policy: RequestSafetyPolicy(expectedOrigin: origin, maximumBodyBytes: 1024)))
        router.get("/probe") { _, _ in "ok" }
        router.post("/probe") { _, _ in "ok" }
        return router
    }
}
