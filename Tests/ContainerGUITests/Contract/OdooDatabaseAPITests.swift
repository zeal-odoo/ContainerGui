import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import XCTest

@testable import ContainerGUI

final class OdooDatabaseAPITests: XCTestCase {
    func testMountedStoppedConfigReadSaveReplayAndPrivacy() async throws {
        let fixture = try configurationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let reader = OdooDatabaseReader(directory: fixture.directory.path)
        let executor = OdooDatabaseExecutor()
        let coordinator = OperationCoordinator()
        let service = makeService(reader, executor, coordinator)
        let app = makeApplication(service, coordinator)
        let key = UUID().uuidString
        let revision = try OdooConfigurationFile.read(fixture.file).revision
        let body = try JSONEncoder().encode(OdooDatabaseSaveRequest(host: "new.local", port: 5433, confirmationTarget: "odoo", expectedRevision: revision))
        try await app.testLocal { client in
            try await client.execute(uri: "/api/v1/containers/odoo/odoo/database-config", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let view = try JSONDecoder.containerGUI.decode(OdooDatabaseView.self, from: response.body)
                XCTAssertTrue(view.editable)
                XCTAssertEqual(view.host, "old.local")
                XCTAssertFalse(String(buffer: response.body).contains("secret-fixture"))
                XCTAssertFalse(String(buffer: response.body).contains(fixture.directory.path))
            }
            let headers: HTTPFields = [.origin: "http://127.0.0.1:8787", .contentType: "application/json", HTTPField.Name("Idempotency-Key")!: key]
            let first = try await client.execute(uri: "/api/v1/containers/odoo/odoo/database-config", method: .post, headers: headers, body: ByteBuffer(data: body)) { response in
                XCTAssertEqual(response.status, .accepted)
                let operation = try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
                XCTAssertEqual(response.headers[.location], "/api/v1/operations/\(operation.id.uuidString)")
                return operation
            }
            let replay = try await client.execute(uri: "/api/v1/containers/odoo/odoo/database-config", method: .post, headers: headers, body: ByteBuffer(data: body)) { response in
                XCTAssertEqual(response.status, .accepted)
                return try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
            }
            XCTAssertEqual(first.id, replay.id)
            for _ in 0..<100 {
                if await coordinator.operation(id: first.id)?.state.isTerminal == true { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let completed = await coordinator.operation(id: first.id)
            XCTAssertEqual(completed?.state, .succeeded)
            XCTAssertEqual(completed?.readback?.observedOdooDatabase?.host, "new.local")
            XCTAssertEqual(completed?.readback?.observedOdooDatabase?.port, 5433)
            XCTAssertFalse(String(decoding: try JSONEncoder.containerGUI.encode(completed), as: UTF8.self).contains("secret-fixture"))
        }
        XCTAssertEqual(try OdooConfigurationFile.read(fixture.file).host, "new.local")
        let calls = await executor.callCount()
        XCTAssertEqual(calls, 0)
    }

    func testStoppedInternalAndNonOdooNeverExecute() async throws {
        for image in ["odoo:19", "ubuntu:26.04"] {
            let reader = OdooDatabaseReader(directory: nil, image: image)
            let executor = OdooDatabaseExecutor()
            let coordinator = OperationCoordinator()
            let service = makeService(reader, executor, coordinator)
            let view = try await service.read(id: "odoo")
            XCTAssertFalse(view.editable)
            XCTAssertEqual(view.restriction, image.hasPrefix("odoo") ? "stoppedInternal" : "notOdoo")
            do {
                _ = try await service.submit(id: "odoo", request: .init(host: "new.local", port: 5432, confirmationTarget: "odoo", expectedRevision: String(repeating: "a", count: 64)), idempotencyKey: UUID().uuidString)
                XCTFail("Unsupported target was accepted")
            } catch { XCTAssertEqual(error.containerGUIProblem.code, .stateConflict) }
            let calls = await executor.callCount()
            XCTAssertEqual(calls, 0)
        }
    }

    func testValidationStaleRevisionOriginAndTargetLocks() async throws {
        let fixture = try configurationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let reader = OdooDatabaseReader(directory: fixture.directory.path)
        let coordinator = OperationCoordinator()
        let service = makeService(reader, OdooDatabaseExecutor(), coordinator)
        let revision = try OdooConfigurationFile.read(fixture.file).revision
        let request = OdooDatabaseSaveRequest(host: "new.local", port: 5432, confirmationTarget: "odoo", expectedRevision: revision)
        let app = makeApplication(service, coordinator)
        try await app.testLocal { client in
            for (origin, body, status) in [
                ("https://evil.invalid", "{}", HTTPResponse.Status.forbidden),
                ("http://127.0.0.1:8787", "{}", .unprocessableContent),
                ("http://127.0.0.1:8787", "{\"host\":\"http://evil\",\"port\":0,\"confirmationTarget\":\"odoo\",\"expectedRevision\":\"\(revision)\"}", .unprocessableContent),
                ("http://127.0.0.1:8787", "{\"host\":\"new.local\",\"port\":5432,\"confirmationTarget\":\"wrong\",\"expectedRevision\":\"\(revision)\"}", .unprocessableContent),
                ("http://127.0.0.1:8787", "{\"host\":\"new.local\",\"port\":5432,\"confirmationTarget\":\"odoo\",\"expectedRevision\":\"\(String(repeating: "a", count: 64))\"}", .conflict)
            ] {
                let headers: HTTPFields = [.origin: origin, .contentType: "application/json", HTTPField.Name("Idempotency-Key")!: UUID().uuidString]
                try await client.execute(uri: "/api/v1/containers/odoo/odoo/database-config", method: .post, headers: headers, body: ByteBuffer(string: body)) { response in XCTAssertEqual(response.status, status) }
            }
        }
        let lock = try await coordinator.create(idempotencyKey: UUID().uuidString, fingerprint: "start", kind: .startContainer, target: .container(id: "odoo"), safeRequestSummary: [:])
        do { _ = try await service.submit(id: "odoo", request: request, idempotencyKey: UUID().uuidString); XCTFail("Lock bypassed") }
        catch { XCTAssertEqual(error.containerGUIProblem.code, .operationInProgress) }
        _ = try await coordinator.fail(lock.id, problem: .init(code: .stateConflict))
        XCTAssertEqual(try OdooConfigurationFile.read(fixture.file).host, "old.local")
    }

    func testConcurrentIdenticalRetryDispatchesOnceAndChangedBodyConflicts() async throws {
        let reader = OdooDatabaseReader(directory: nil, state: .running)
        let executor = OdooDatabaseExecutor(delay: .milliseconds(30))
        let coordinator = OperationCoordinator()
        let service = makeService(reader, executor, coordinator)
        let view = try await service.read(id: "odoo")
        let request = OdooDatabaseSaveRequest(host: "new.local", port: 5433, confirmationTarget: "odoo", expectedRevision: try XCTUnwrap(view.revision))
        let key = UUID().uuidString
        async let first = service.submit(id: "odoo", request: request, idempotencyKey: key)
        async let second = service.submit(id: "odoo", request: request, idempotencyKey: key)
        let operations = try await [first, second]
        XCTAssertEqual(operations[0].id, operations[1].id)
        do {
            _ = try await service.submit(id: "odoo", request: .init(host: "other.local", port: 5433, confirmationTarget: "odoo", expectedRevision: request.expectedRevision), idempotencyKey: key)
            XCTFail("Key conflict bypassed")
        } catch { XCTAssertEqual(error.containerGUIProblem.code, .idempotencyConflict) }
        for _ in 0..<100 {
            if await coordinator.operation(id: operations[0].id)?.state.isTerminal == true { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let writes = await executor.writeCount()
        let completed = await coordinator.operation(id: operations[0].id)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(completed?.state, .succeeded)
    }

    func testGuestFailureAndReadbackMismatchReleaseLockWithoutFalseSuccess() async throws {
        for failure in ["exit", "mismatch", "timeout", "invalid"] {
            let reader = OdooDatabaseReader(directory: nil, state: .running)
            let executor = OdooDatabaseExecutor(failure: failure)
            let coordinator = OperationCoordinator()
            let service = makeService(reader, executor, coordinator)
            let view = try await service.read(id: "odoo")
            let operation = try await service.submit(id: "odoo", request: .init(host: "new.local", port: 5433, confirmationTarget: "odoo", expectedRevision: try XCTUnwrap(view.revision)), idempotencyKey: UUID().uuidString)
            for _ in 0..<100 {
                if await coordinator.operation(id: operation.id)?.state.isTerminal == true { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let completed = await coordinator.operation(id: operation.id)
            XCTAssertEqual(completed?.state, .failed)
            let next = try await coordinator.create(idempotencyKey: UUID().uuidString, fingerprint: "start", kind: .startContainer, target: .container(id: "odoo"), safeRequestSummary: [:])
            XCTAssertEqual(next.state, .queued)
        }
    }

    private func makeService(_ reader: OdooDatabaseReader, _ executor: OdooDatabaseExecutor, _ coordinator: OperationCoordinator) -> OdooDatabaseService<OdooDatabaseReader> {
        OdooDatabaseService(reader: reader, executor: executor, executableURL: URL(fileURLWithPath: "/usr/local/bin/container"), coordinator: coordinator)
    }

    private func makeApplication(_ service: OdooDatabaseService<OdooDatabaseReader>, _ coordinator: OperationCoordinator) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router()
        router.middlewares.add(ErrorMiddleware())
        router.middlewares.add(SafetyMiddleware(policy: RequestSafetyPolicy(expectedOrigin: "http://127.0.0.1:8787", maximumBodyBytes: 64 * 1024)))
        OperationRoutes.register(on: router, coordinator: coordinator)
        ContainerControlRoutes.registerOdooDatabase(on: router, service: service)
        return Application(router: router)
    }

    private func configurationFixture() throws -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("odoo-api-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("odoo.conf")
        try Data("[options]\ndb_host = old.local\ndb_port = 5432\ndb_password = secret-fixture\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return (directory, file)
    }
}

private struct OdooDatabaseReader: ContainerReading {
    let directory: String?
    var image = "odoo:19"
    var state: ContainerState = .stopped

    func systemHealth() async throws -> SystemHealth { throw ProblemDetail(code: .serviceUnavailable) }
    func listContainers() async throws -> ContainerList { ContainerList(items: [summary], observedAt: Date()) }
    func containerDetail(id: String) async throws -> ContainerDetail {
        guard id == summary.id else { throw ProblemDetail(code: .targetNotFound) }
        let mounts: [JSONValue] = directory.map { [.object(["source": .string($0), "destination": .string("/etc/odoo"), "type": .object(["virtiofs": .object([:])])])] } ?? []
        return ContainerDetail(summary: summary, configuration: .object(["mounts": .array(mounts)]), status: .object([:]), raw: .object([:]), observedAt: Date())
    }
    private var summary: ContainerSummary {
        .init(id: "odoo", displayName: "odoo", imageReference: image, state: state, rawState: state.rawValue, ipv4Address: nil, ipv6Address: nil, createdAt: nil, observedAt: Date())
    }
}

private actor OdooDatabaseExecutor: CommandExecuting {
    private var calls: [[String]] = []
    private var endpoint = OdooDatabaseEndpoint(host: "old.local", port: 5432, revision: String(repeating: "a", count: 64))
    private let delay: Duration
    private let failure: String?
    init(delay: Duration = .zero, failure: String? = nil) { self.delay = delay; self.failure = failure }
    func run(_ request: CommandRequest) async throws -> CommandResult {
        calls.append(request.arguments)
        XCTAssertEqual(Array(request.arguments.prefix(3)), ["exec", "--user", "root"])
        XCTAssertEqual(request.arguments[3], "odoo")
        XCTAssertEqual(Array(request.arguments[4..<6]), ["python3", "-c"])
        XCTAssertEqual(request.arguments[6], OdooDatabaseGuest.script)
        let mode = request.arguments[7]
        XCTAssertEqual(request.arguments[8], "/etc/odoo/odoo.conf")
        try await Task.sleep(for: delay)
        if mode == "write" {
            if failure == "timeout" { throw CommandExecutionError.timedOut }
            if failure == "exit" { return .init(stdout: Data(), stderr: Data("secret-fixture".utf8), exitCode: 1, duration: .zero) }
            if failure == "invalid" { return .init(stdout: Data("unexpected secret-fixture".utf8), stderr: Data(), exitCode: 0, duration: .zero) }
            if failure != "mismatch" { endpoint = .init(host: request.arguments[9], port: Int(request.arguments[10])!, revision: String(repeating: "b", count: 64)) }
        }
        return .init(stdout: try JSONEncoder().encode(endpoint), stderr: Data(), exitCode: 0, duration: .zero)
    }
    func callCount() -> Int { calls.count }
    func writeCount() -> Int { calls.filter { $0[7] == "write" }.count }
}
