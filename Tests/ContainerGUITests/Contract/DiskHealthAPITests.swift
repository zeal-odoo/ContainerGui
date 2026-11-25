import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import XCTest

@testable import ContainerGUI

final class DiskHealthAPITests: XCTestCase {
    func testHostDiskEndpointIsIndependentAndFailureRemainsExplicit() async throws {
        for failure in [false, true] {
            let reader = APIDiskReader(failure: failure)
            try await application(reader: reader).testLocal { client in
                try await client.execute(uri: "/api/v1/system/disks", method: .get) { response in
                    XCTAssertEqual(response.status, .ok)
                    XCTAssertEqual(response.headers[.cacheControl], "no-store")
                    let body = try JSONDecoder.containerGUI.decode(DiskHealthSnapshot.self, from: Data(response.body.readableBytesView))
                    XCTAssertTrue(body.disks.isEmpty)
                    XCTAssertEqual(body.error, failure ? "read_failed" : nil)
                }
            }
        }
    }

    func testUntrustedOriginIsRejectedBeforeReadingDisks() async throws {
        let reader = APIDiskReader(failure: false)
        try await application(reader: reader).testLocal { client in
            try await client.execute(uri: "/api/v1/system/disks", method: .get, headers: [.origin: "https://attacker.invalid"]) { response in
                XCTAssertEqual(response.status, .forbidden)
            }
        }
        let calls = await reader.calls
        XCTAssertEqual(calls, 0)
    }

    private func application(reader: APIDiskReader) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router()
        router.middlewares.add(ErrorMiddleware())
        router.middlewares.add(SafetyMiddleware(policy: RequestSafetyPolicy(expectedOrigin: "http://127.0.0.1:8787", maximumBodyBytes: 1024)))
        DiskHealthRoutes.register(on: router, service: DiskHealthService(reader: reader))
        return Application(router: router)
    }
}

private actor APIDiskReader: DiskHealthReading {
    let failure: Bool
    var calls = 0
    init(failure: Bool) { self.failure = failure }
    func read() async -> DiskHealthSnapshot {
        calls += 1
        return .init(disks: [], observedAt: Date(), error: failure ? "read_failed" : nil)
    }
}
