import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import XCTest

@testable import ContainerGUI

final class ANEPowerAPITests: XCTestCase {
    func testPassiveEndpointHasExactNullContractAndNoStoreWithoutAnyCLIOrAI() async throws {
        let fixture = ANEPowerFixture()
        let app = application(sampler: fixture.sampler())
        try await app.testLocal { client in
            try await client.execute(uri: "/api/v1/system/ane", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers[.cacheControl], "no-store")
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
                XCTAssertEqual(Set(object.keys), Set(["state", "watts", "observedAt", "sampleSeconds", "reason", "scope", "estimated", "utilizationPercent", "utilizationState"]))
                XCTAssertEqual(object["state"] as? String, "sampling")
                for field in ["watts", "sampleSeconds", "reason", "utilizationPercent"] { XCTAssertTrue(object[field] is NSNull, field) }
                XCTAssertEqual(object["scope"] as? String, "host")
                XCTAssertEqual(object["estimated"] as? Bool, true)
                XCTAssertEqual(object["utilizationState"] as? String, "unavailable")
            }
            fixture.set(time: 5, channels: [.init(name: "ANE", unit: "mJ", value: 12_500)])
            try await client.execute(uri: "/api/v1/system/ane", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
                XCTAssertEqual(object["state"] as? String, "ready")
                XCTAssertEqual(object["watts"] as? Double, 2.5)
                XCTAssertEqual(object["sampleSeconds"] as? Double, 5)
                XCTAssertTrue(object["reason"] is NSNull)
                XCTAssertTrue(object["utilizationPercent"] is NSNull)
            }
        }
        XCTAssertEqual(fixture.readCount, 2)
    }

    func testUnavailableIs200WithSafeReasonAndExplicitNullValues() async throws {
        for failure in [ANEPowerFailure.unsupported, .readFailed, .invalidSample] {
            let fixture = ANEPowerFixture()
            fixture.set(time: 0, failure: failure)
            try await application(sampler: fixture.sampler()).testLocal { client in
                try await client.execute(uri: "/api/v1/system/ane", method: .get) { response in
                    XCTAssertEqual(response.status, .ok)
                    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as? [String: Any])
                    XCTAssertEqual(object["state"] as? String, "unavailable")
                    XCTAssertEqual(object["reason"] as? String, failure.rawValue)
                    for field in ["watts", "sampleSeconds", "utilizationPercent"] { XCTAssertTrue(object[field] is NSNull, field) }
                }
            }
        }
    }

    func testHostAndOriginAreRejectedBeforeSampling() async throws {
        let fixture = ANEPowerFixture()
        let app = application(sampler: fixture.sampler())
        try await app.testLocal { client in
            try await client.execute(uri: "/api/v1/system/ane", method: .get, headers: [.origin: "https://attacker.invalid"]) { response in
                XCTAssertEqual(response.status, .forbidden)
            }
        }
        try await app.testLocal(authority: "attacker.invalid:8787") { client in
            try await client.execute(uri: "/api/v1/system/ane", method: .get) { response in
                XCTAssertEqual(response.status, .forbidden)
            }
        }
        XCTAssertEqual(fixture.readCount, 0)
    }

    private func application(sampler: ANEPowerSampler) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router()
        router.middlewares.add(ErrorMiddleware())
        router.middlewares.add(SafetyMiddleware(policy: RequestSafetyPolicy(expectedOrigin: "http://127.0.0.1:8787", maximumBodyBytes: 1024)))
        ANEPowerRoutes.register(on: router, sampler: sampler)
        return Application(router: router)
    }
}
