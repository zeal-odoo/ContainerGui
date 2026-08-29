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

        try await app.test(.router) { client in
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
}
