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

    func testHistoryIsPassivePagedAndHasNoStoreBoundary() async throws {
        let history = AILogHistoryStore(directory: try historyDirectory())
        for index in 0..<11 { try await history.append(historyRecord(index: index)) }
        let reader = FakeAILogReader()
        let worker = FakeAILogWorker()
        let service = AILogService(reader: reader, history: history, store: FakeAIModelStore(), worker: worker, memoryAvailable: { true })
        let router = Router()
        router.middlewares.add(ErrorMiddleware())
        router.middlewares.add(SafetyMiddleware(policy: RequestSafetyPolicy(expectedOrigin: "http://127.0.0.1:8787", maximumBodyBytes: 1024)))
        AILogRoutes.register(on: router, service: service)
        AILogRoutes.registerHistory(on: router, history: history)
        let app = Application(router: router)
        try await app.testLocal { client in
            for (page, count) in [(1, 10), (2, 1)] {
                try await client.execute(uri: "/api/v1/ai/logs/history?containerId=demo&page=\(page)", method: .get) { response in
                    XCTAssertEqual(response.status, .ok)
                    XCTAssertEqual(response.headers[.cacheControl], "no-store")
                    let value = try JSONDecoder.containerGUI.decode(AILogHistoryPage.self, from: response.body)
                    XCTAssertEqual(value.items.count, count)
                    XCTAssertEqual(value.total, 11)
                }
            }
            for query in ["page=0", "page=101", "page=oops", "containerId=..%2Fdemo", "path=%2Fetc%2Fpasswd", "page=1&page=2"] {
                try await client.execute(uri: "/api/v1/ai/logs/history?\(query)", method: .get) { response in
                    XCTAssertEqual(response.status, .unprocessableContent)
                }
            }
            try await client.execute(uri: "/api/v1/ai/logs/history", method: .get, headers: [.origin: "https://attacker.invalid"]) { response in
                XCTAssertEqual(response.status, .forbidden)
            }
        }
        try await app.testLocal(authority: "attacker.invalid:8787") { client in
            try await client.execute(uri: "/api/v1/ai/logs/history", method: .get) { response in XCTAssertEqual(response.status, .forbidden) }
        }
        let starts = await worker.starts
        let reads = await reader.reads
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(reads, 0)
    }

    func testHistoryDeletionRequiresExactConfirmationAndRejectsCrossOrigin() async throws {
        let history = AILogHistoryStore(directory: try historyDirectory())
        let record = historyRecord()
        try await history.append(record)
        let router = Router()
        router.middlewares.add(ErrorMiddleware())
        router.middlewares.add(SafetyMiddleware(policy: RequestSafetyPolicy(expectedOrigin: "http://127.0.0.1:8787", maximumBodyBytes: 1024)))
        AILogRoutes.registerHistory(on: router, history: history)
        try await Application(router: router).testLocal { client in
            let valid = "{\"id\":\"\(record.id)\",\"confirmationId\":\"\(record.id)\"}"
            for body in ["{}", "{\"id\":\"\(record.id)\"}", "{\"id\":\"../file\",\"confirmationId\":\"../file\"}",
                         "{\"id\":\"\(record.id)\",\"confirmationId\":\"\(UUID())\"}",
                         "{\"id\":\"\(record.id)\",\"confirmationId\":\"\(record.id)\",\"path\":\"/tmp\"}"] {
                try await client.execute(uri: "/api/v1/ai/logs/history/delete", method: .post,
                                         headers: [.origin: "http://127.0.0.1:8787", .contentType: "application/json"], body: ByteBuffer(string: body)) { response in
                    XCTAssertEqual(response.status, .unprocessableContent)
                }
            }
            try await client.execute(uri: "/api/v1/ai/logs/history/delete", method: .post,
                                     headers: [.origin: "https://attacker.invalid", .contentType: "application/json"], body: ByteBuffer(string: valid)) { response in
                XCTAssertEqual(response.status, .forbidden)
            }
            let before = try await history.list(containerID: nil, page: 1)
            XCTAssertEqual(before.total, 1)
            for expected in [HTTPResponse.Status.ok, .notFound] {
                try await client.execute(uri: "/api/v1/ai/logs/history/delete", method: .post,
                                         headers: [.origin: "http://127.0.0.1:8787", .contentType: "application/json"], body: ByteBuffer(string: valid)) { response in
                    XCTAssertEqual(response.status, expected)
                }
            }
        }
    }

    private func application() -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router()
        router.middlewares.add(ErrorMiddleware())
        router.middlewares.add(SafetyMiddleware(policy: RequestSafetyPolicy(expectedOrigin: "http://127.0.0.1:8787", maximumBodyBytes: 1024)))
        AILogRoutes.register(on: router, service: AILogService(reader: FakeAILogReader(), history: AILogHistoryStore(directory: try! historyDirectory()), store: FakeAIModelStore(), worker: FakeAILogWorker(), memoryAvailable: { true }))
        return Application(router: router)
    }
}
