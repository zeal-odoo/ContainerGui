import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import XCTest

@testable import ContainerGUI

final class ContainerConnectionAPITests: XCTestCase {
    func testUniversalViewAndMountedDatabaseSaveReplayPrivacyWithoutCLIExecution() async throws {
        let fixture = try configFixture(name: "app.env", text: "DB_HOST=old.local\nDB_PORT=5432\nDB_PASSWORD=secret-fixture\n")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let reader = ConnectionReader(image: "bettafish:local", source: fixture.directory.path, destination: "/app-config", arguments: ["-c", "ln -s /app-config/app.env /app/.env && exec python app.py"], executable: "sh")
        let executor = ConnectionExecutor()
        let coordinator = OperationCoordinator()
        let service = makeService(reader, executor, coordinator)
        let router = Router()
        router.middlewares.add(ErrorMiddleware())
        router.middlewares.add(SafetyMiddleware(policy: RequestSafetyPolicy(expectedOrigin: "http://127.0.0.1:8787", maximumBodyBytes: 64 * 1024)))
        ContainerControlRoutes.registerConnections(on: router, service: service)
        OperationRoutes.register(on: router, coordinator: coordinator)
        let app = Application(router: router)
        try await app.testLocal { client in
            let view = try await client.execute(uri: "/api/v1/containers/app/connections", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertFalse(String(buffer: response.body).contains("secret-fixture"))
                XCTAssertFalse(String(buffer: response.body).contains(fixture.directory.path))
                return try JSONDecoder.containerGUI.decode(ContainerConnectionView.self, from: response.body)
            }
            XCTAssertEqual(view.kind, "database")
            XCTAssertTrue(view.editable)
            let request = ContainerConnectionSaveRequest(endpointId: "database", host: "new.local", port: 5433, confirmationTarget: "app", expectedRevision: try XCTUnwrap(view.revision))
            let body = try JSONEncoder().encode(request)
            let headers: HTTPFields = [.origin: "http://127.0.0.1:8787", .contentType: "application/json", HTTPField.Name("Idempotency-Key")!: UUID().uuidString]
            let first = try await client.execute(uri: "/api/v1/containers/app/connections", method: .post, headers: headers, body: ByteBuffer(data: body)) { response in
                XCTAssertEqual(response.status, .accepted)
                return try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
            }
            let replay = try await client.execute(uri: "/api/v1/containers/app/connections", method: .post, headers: headers, body: ByteBuffer(data: body)) { response in
                XCTAssertEqual(response.status, .accepted)
                return try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
            }
            XCTAssertEqual(first.id, replay.id)
            let completed = await Self.finish(first, coordinator)
            XCTAssertEqual(completed?.state, .succeeded)
            XCTAssertEqual(completed?.readback?.observedConnections?.endpoints.first?.host, "new.local")
            XCTAssertEqual(completed?.readback?.observedConnections?.endpoints.first?.port, 5433)
            let backups = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "bak" }
            XCTAssertEqual(backups.count, 1)
        }
        let count = await executor.callCount()
        XCTAssertEqual(count, 0)
    }

    func testStoppedSingleFileNginxWritesOneEndpointAndPreservesInode() async throws {
        let text = "server { location /a/ { proxy_pass http://old.local:8501/a/; } location / { proxy_pass http://old.local:5000; } }\n"
        let fixture = try configFixture(name: "nginx.conf", text: text)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let inode = try FileManager.default.attributesOfItem(atPath: fixture.file.path)[.systemFileNumber] as? NSNumber
        let reader = ConnectionReader(image: "nginx:latest", source: fixture.file.path, destination: "/etc/nginx/nginx.conf", arguments: ["nginx", "-g", "daemon off;"])
        let executor = ConnectionExecutor()
        let coordinator = OperationCoordinator()
        let service = makeService(reader, executor, coordinator)
        let view = try await service.read(id: "app")
        XCTAssertTrue(view.editable)
        XCTAssertEqual(view.kind, "backend")
        let operation = try await service.submit(id: "app", request: .init(endpointId: "proxy-2", host: "new.local", port: 5001, confirmationTarget: "app", expectedRevision: try XCTUnwrap(view.revision)), idempotencyKey: UUID().uuidString)
        let completed = await Self.finish(operation, coordinator)
        XCTAssertEqual(completed?.state, .succeeded)
        XCTAssertEqual(try String(contentsOf: fixture.file, encoding: .utf8), text.replacingOccurrences(of: "old.local:5000", with: "new.local:5001"))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: fixture.file.path)[.systemFileNumber] as? NSNumber, inode)
        let count = await executor.callCount()
        XCTAssertEqual(count, 0)
    }

    func testUnsupportedRunningSingleFileTemplatesAndUnconsumedDotenvCannotWrite() async throws {
        let fixture = try configFixture(name: "nginx.conf", text: "location / { proxy_pass http://db:80; }")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let cases: [(ConnectionReader, String)] = [
            (ConnectionReader(image: "ubuntu:26.04"), "unsupported"),
            (ConnectionReader(image: "nginx:latest"), "unsupportedLocation"),
            (ConnectionReader(image: "nginx:latest", source: fixture.file.path, destination: "/etc/nginx/nginx.conf", state: .running), "runningSingleFile"),
            (ConnectionReader(image: "nginx:latest", source: fixture.file.path, destination: "/etc/nginx/nginx.conf", templates: true), "unsupportedLocation"),
            (ConnectionReader(image: "bettafish:local", source: fixture.directory.path, destination: "/app-config"), "unsupported"),
            (ConnectionReader(image: "odoo:19"), "stoppedInternal")
        ]
        for (reader, restriction) in cases {
            let executor = ConnectionExecutor()
            let service = makeService(reader, executor, OperationCoordinator())
            let view = try await service.read(id: "app")
            XCTAssertFalse(view.editable)
            XCTAssertEqual(view.restriction, restriction)
            do {
                _ = try await service.submit(id: "app", request: .init(endpointId: "database", host: "new.local", port: 5432, confirmationTarget: "app", expectedRevision: String(repeating: "a", count: 64)), idempotencyKey: UUID().uuidString)
                XCTFail("Unsupported target accepted")
            } catch {}
            let count = await executor.callCount()
            XCTAssertEqual(count, 0)
        }
        XCTAssertEqual(try String(contentsOf: fixture.file, encoding: .utf8), "location / { proxy_pass http://db:80; }")
    }

    func testStaleMissingEndpointLifecycleLockAndStateChangeRejectWithoutWrites() async throws {
        let fixture = try configFixture(name: "nginx.conf", text: "location / { proxy_pass http://old.local:5000; }")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let coordinator = OperationCoordinator()
        let reader = ConnectionReader(image: "nginx:latest", source: fixture.file.path, destination: "/etc/nginx/nginx.conf")
        let service = makeService(reader, ConnectionExecutor(), coordinator)
        let view = try await service.read(id: "app")
        for (endpoint, revision) in [("proxy-9", view.revision!), ("proxy-1", String(repeating: "a", count: 64))] {
            do { _ = try await service.submit(id: "app", request: .init(endpointId: endpoint, host: "new.local", port: 5001, confirmationTarget: "app", expectedRevision: revision), idempotencyKey: UUID().uuidString); XCTFail("Invalid request accepted") }
            catch {}
        }
        _ = try await coordinator.create(idempotencyKey: UUID().uuidString, fingerprint: "held", kind: .startContainer, target: .container(id: "app"), safeRequestSummary: [:])
        do { _ = try await service.submit(id: "app", request: .init(endpointId: "proxy-1", host: "new.local", port: 5001, confirmationTarget: "app", expectedRevision: view.revision!), idempotencyKey: UUID().uuidString); XCTFail("Concurrent lifecycle accepted") }
        catch { XCTAssertEqual(error as? OperationCoordinatorError, .operationInProgress) }
        let changedCoordinator = OperationCoordinator()
        let changedReader = ConnectionReader(image: "nginx:latest", source: fixture.file.path, destination: "/etc/nginx/nginx.conf", runningAfterRead: 1)
        let changedService = makeService(changedReader, ConnectionExecutor(), changedCoordinator)
        let operation = try await changedService.submit(id: "app", request: .init(endpointId: "proxy-1", host: "new.local", port: 5001, confirmationTarget: "app", expectedRevision: view.revision!), idempotencyKey: UUID().uuidString)
        let completed = await Self.finish(operation, changedCoordinator)
        XCTAssertEqual(completed?.state, .failed)
        XCTAssertEqual(try String(contentsOf: fixture.file, encoding: .utf8), "location / { proxy_pass http://old.local:5000; }")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).contains { $0.hasSuffix(".bak") })
    }

    func testUnifiedOdooDelegationPreservesOldAPIReadback() async throws {
        let fixture = try configFixture(name: "odoo.conf", text: "[options]\ndb_host=old.local\ndb_port=5432\ndb_password=secret-fixture\n")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let reader = ConnectionReader(image: "odoo:19", source: fixture.directory.path, destination: "/etc/odoo")
        let coordinator = OperationCoordinator()
        let service = makeService(reader, ConnectionExecutor(), coordinator)
        let view = try await service.read(id: "app")
        XCTAssertEqual(view.kind, "database")
        let operation = try await service.submit(id: "app", request: .init(endpointId: "database", host: "new.local", port: 5433, confirmationTarget: "app", expectedRevision: view.revision!), idempotencyKey: UUID().uuidString)
        let completed = await Self.finish(operation, coordinator)
        XCTAssertEqual(completed?.state, .succeeded)
        XCTAssertEqual(completed?.readback?.observedOdooDatabase?.host, "new.local")
        XCTAssertTrue(try String(contentsOf: fixture.file, encoding: .utf8).contains("db_password=secret-fixture"))
    }

    func testCustomLaunchCommandsNeverClaimAnUnusedMountedFileIsEditable() async throws {
        let nginx = try configFixture(name: "nginx.conf", text: "proxy_pass http://db:80;")
        let dotenv = try configFixture(name: "app.env", text: "DB_HOST=db\nDB_PORT=5432\n")
        defer { try? FileManager.default.removeItem(at: nginx.directory); try? FileManager.default.removeItem(at: dotenv.directory) }
        for reader in [
            ConnectionReader(image: "nginx:latest", source: nginx.file.path, destination: "/etc/nginx/nginx.conf", arguments: ["/bin/bash", "-lc", "exec nginx -c /other.conf"]),
            ConnectionReader(image: "bettafish:local", source: dotenv.directory.path, destination: "/app-config", arguments: ["-c", "echo 'ln -s /app-config/app.env /app/.env && exec python app.py'"], executable: "sh"),
            ConnectionReader(image: "bettafish:local", source: dotenv.directory.path, destination: "/app-config", arguments: ["-c", "ln -s /app-config/app.env /app/.env && exec python app.py"], executable: "echo")
        ] {
            let service = makeService(reader, ConnectionExecutor(), OperationCoordinator())
            let view = try await service.read(id: "app")
            XCTAssertFalse(view.editable)
        }
    }

    private static func finish(_ operation: ContainerGUI.Operation, _ coordinator: OperationCoordinator) async -> ContainerGUI.Operation? {
        for _ in 0..<100 {
            if await coordinator.operation(id: operation.id)?.state.isTerminal == true { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await coordinator.operation(id: operation.id)
    }

    private func makeService(_ reader: ConnectionReader, _ executor: ConnectionExecutor, _ coordinator: OperationCoordinator) -> ContainerConnectionService<ConnectionReader> {
        .init(reader: reader, odoo: .init(reader: reader, executor: executor, executableURL: URL(fileURLWithPath: "/fake/container"), coordinator: coordinator), coordinator: coordinator)
    }

    private func configFixture(name: String, text: String) throws -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("connection-api-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return (directory, file)
    }
}

private actor ConnectionReader: ContainerReading {
    let image: String
    let source: String?
    let destination: String?
    let arguments: [String]
    let executable: String?
    let state: ContainerState
    let templates: Bool
    let runningAfterRead: Int?
    private var reads = 0

    init(image: String, source: String? = nil, destination: String? = nil, arguments: [String] = [], executable: String? = nil, state: ContainerState = .stopped, templates: Bool = false, runningAfterRead: Int? = nil) {
        self.image = image; self.source = source; self.destination = destination; self.arguments = arguments; self.executable = executable; self.state = state; self.templates = templates; self.runningAfterRead = runningAfterRead
    }
    func systemHealth() async throws -> SystemHealth { throw ProblemDetail(code: .serviceUnavailable) }
    func listContainers() async throws -> ContainerList { .init(items: [], observedAt: Date()) }
    func containerDetail(id: String) async throws -> ContainerDetail {
        guard id == "app" else { throw ProblemDetail(code: .targetNotFound) }
        reads += 1
        let currentState = runningAfterRead.map { reads > $0 ? ContainerState.running : state } ?? state
        let summary = ContainerSummary(id: id, displayName: id, imageReference: image, state: currentState, rawState: currentState.rawValue, ipv4Address: nil, ipv6Address: nil, createdAt: nil, observedAt: Date())
        var mounts: [JSONValue] = []
        if let source, let destination { mounts.append(.object(["source": .string(source), "destination": .string(destination), "type": .object(["virtiofs": .object([:])])])) }
        if templates { mounts.append(.object(["source": .string("/not-read/templates"), "destination": .string("/etc/nginx/templates"), "type": .object(["virtiofs": .object([:])])])) }
        var process: [String: JSONValue] = ["arguments": .array(arguments.map { .string($0) })]
        if let executable { process["executable"] = .string(executable) }
        return .init(summary: summary, configuration: .object(["mounts": .array(mounts), "initProcess": .object(process)]), status: .object([:]), raw: .object([:]), observedAt: Date())
    }
}

private actor ConnectionExecutor: CommandExecuting {
    private var count = 0
    func run(_ request: CommandRequest) async throws -> CommandResult { count += 1; XCTFail("Unexpected CLI command"); throw ProblemDetail(code: .serviceUnavailable) }
    func callCount() -> Int { count }
}
