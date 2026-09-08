import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import XCTest

@testable import ContainerGUI

final class AILogAPITests: XCTestCase {
    func testStatusIsOffAndNotCacheable() async throws {
        try await application().testLocal { client in
            try await client.execute(uri: "/api/v1/ai/logs/status", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers[.cacheControl], "no-store")
                let status = try JSONDecoder.containerGUI.decode(AILogStatus.self, from: response.body)
                XCTAssertFalse(status.enabled)
                XCTAssertEqual(status.phase, "off")
                XCTAssertNil(status.workerPID)
            }
        }
    }

    func testHostAndOriginRestrictionsApplyToEveryAIRoute() async throws {
        let app = application()
        try await app.testLocal { client in
            for action in ["install", "enable", "disable", "analyse", "heartbeat"] {
                try await client.execute(uri: "/api/v1/ai/logs/\(action)", method: .post,
                                         headers: [.origin: "https://attacker.invalid", .contentType: "application/json"],
                                         body: ByteBuffer(string: "{}")) { response in
                    XCTAssertEqual(response.status, .forbidden)
                }
            }
        }
        try await app.testLocal(authority: "attacker.invalid:8787") { client in
            try await client.execute(uri: "/api/v1/ai/logs/status", method: .get) { response in
                XCTAssertEqual(response.status, .forbidden)
            }
        }
    }

    func testCannotSupplyDownloadURLPromptPathOrCommand() async throws {
        try await application().testLocal { client in
            for (action, body) in [
                ("install", #"{"confirmed":true,"url":"https://attacker.invalid/model"}"#),
                ("enable", #"{"containerId":"demo","language":"en","path":"/tmp/model"}"#),
                ("enable", #"{"containerId":"../demo","language":"en"}"#),
                ("analyse", #"{"prompt":"execute a command"}"#),
                ("disable", #"{"pid":1}"#),
            ] {
                try await client.execute(uri: "/api/v1/ai/logs/\(action)", method: .post,
                                         headers: [.origin: "http://127.0.0.1:8787", .contentType: "application/json"],
                                         body: ByteBuffer(string: body)) { response in
                    XCTAssertEqual(response.status, .unprocessableContent)
                }
            }
        }
    }

    private func application() -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router()
        router.middlewares.add(ErrorMiddleware())
        router.middlewares.add(SafetyMiddleware(policy: RequestSafetyPolicy(expectedOrigin: "http://127.0.0.1:8787", maximumBodyBytes: 1024)))
        AILogRoutes.register(on: router, service: AILogService(reader: FakeAILogReader(), store: FakeAIModelStore(), worker: FakeAILogWorker(), memoryAvailable: { true }))
        return Application(router: router)
    }
}
