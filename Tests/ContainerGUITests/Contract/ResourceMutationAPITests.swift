import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import XCTest

@testable import ContainerGUI

final class ResourceMutationAPITests: XCTestCase {
    private let origin = "http://127.0.0.1:8787"
    private let idempotencyName = HTTPField.Name("Idempotency-Key")!

    func testImageListPullReplayAndOperationReadback() async throws {
        let manager = StubImageManager()
        let app = makeImageApplication(manager: manager)
        let key = UUID().uuidString
        let expectedOrigin = origin
        let headerName = idempotencyName

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/v1/images", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let list = try JSONDecoder.containerGUI.decode(ImageList.self, from: response.body)
                XCTAssertEqual(list.items.map(\.name), ["docker.io/library/postgres:latest"])
            }

            let headers: HTTPFields = [
                .origin: expectedOrigin,
                .contentType: "application/json",
                headerName: key,
            ]
            let body = ByteBuffer(string: #"{"reference":"postgres:latest","platform":"linux/arm64"}"#)
            let first: ContainerGUI.Operation = try await client.execute(
                uri: "/api/v1/images/pull",
                method: .post,
                headers: headers,
                body: body
            ) { response in
                XCTAssertEqual(response.status, .accepted)
                let operation = try JSONDecoder.containerGUI.decode(Operation.self, from: response.body)
                XCTAssertEqual(operation.kind, .pullImage)
                XCTAssertEqual(response.headers[.location], "/api/v1/operations/\(operation.id.uuidString)")
                return operation
            }
            let replay: ContainerGUI.Operation = try await client.execute(
                uri: "/api/v1/images/pull",
                method: .post,
                headers: headers,
                body: ByteBuffer(string: #"{"reference":"postgres:latest","platform":"linux/arm64"}"#)
            ) { response in
                XCTAssertEqual(response.status, .accepted)
                return try JSONDecoder.containerGUI.decode(Operation.self, from: response.body)
            }
            XCTAssertEqual(first.id, replay.id)

            try await Task.sleep(for: .milliseconds(80))
            try await client.execute(uri: "/api/v1/operations/\(first.id.uuidString)", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let operation = try JSONDecoder.containerGUI.decode(Operation.self, from: response.body)
                XCTAssertEqual(operation.state, .succeeded)
                XCTAssertNotNil(operation.readback?.observedImage)
                XCTAssertEqual(operation.readback?.expectationMatched, true)
                XCTAssertEqual(operation.progress?.phase, .verifying)
                XCTAssertEqual(operation.progress?.percentComplete, 100)
            }
        }
        let pullCount = await manager.pullCount
        XCTAssertEqual(pullCount, 1)
    }

    func testInvalidPullIsRejectedBeforeMutation() async throws {
        let manager = StubImageManager()
        let app = makeImageApplication(manager: manager)
        let expectedOrigin = origin
        let headerName = idempotencyName

        try await app.test(.router) { client in
            let headers: HTTPFields = [
                .origin: expectedOrigin,
                .contentType: "application/json",
                headerName: UUID().uuidString,
            ]
            try await client.execute(
                uri: "/api/v1/images/pull",
                method: .post,
                headers: headers,
                body: ByteBuffer(string: #"{"reference":"bad image"}"#)
            ) { response in
                XCTAssertEqual(response.status, .unprocessableContent)
                let problem = try JSONDecoder.containerGUI.decode(ProblemDetail.self, from: response.body)
                XCTAssertEqual(problem.code, .validationFailed)
                XCTAssertEqual(problem.fieldErrors?.map(\.field), ["reference"])
            }
        }
        let pullCount = await manager.pullCount
        XCTAssertEqual(pullCount, 0)
    }

    func testCreateReplayRedactionOptionalStartAndReadback() async throws {
        let manager = StubImageManager()
        let app = makeImageApplication(manager: manager)
        let expectedOrigin = origin
        let headerName = idempotencyName
        let key = UUID().uuidString
        let secret = "must-never-appear-in-operation"

        try await app.test(.router) { client in
            let headers: HTTPFields = [
                .origin: expectedOrigin,
                .contentType: "application/json",
                headerName: key,
            ]
            let rawBody = #"{"name":"demo","image":"postgres:latest","cpus":2,"memoryMiB":512,"ports":[{"hostPort":15432,"containerPort":5432}],"environment":[{"name":"POSTGRES_PASSWORD","value":"\#(secret)"}],"arguments":["postgres"],"startAfterCreate":true}"#
            let first: ContainerGUI.Operation = try await client.execute(
                uri: "/api/v1/containers",
                method: .post,
                headers: headers,
                body: ByteBuffer(string: rawBody)
            ) { response in
                XCTAssertEqual(response.status, .accepted)
                let encoded = String(decoding: response.body.readableBytesView, as: UTF8.self)
                XCTAssertFalse(encoded.contains(secret))
                XCTAssertTrue(encoded.contains("POSTGRES_PASSWORD"))
                return try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
            }
            let replay: ContainerGUI.Operation = try await client.execute(
                uri: "/api/v1/containers",
                method: .post,
                headers: headers,
                body: ByteBuffer(string: rawBody)
            ) { response in
                XCTAssertEqual(response.status, .accepted)
                return try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
            }
            XCTAssertEqual(first.id, replay.id)

            try await Task.sleep(for: .milliseconds(80))
            try await client.execute(uri: "/api/v1/operations/\(first.id.uuidString)", method: .get) { response in
                let encoded = String(decoding: response.body.readableBytesView, as: UTF8.self)
                XCTAssertFalse(encoded.contains(secret))
                let operation = try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
                XCTAssertEqual(operation.state, .succeeded)
                XCTAssertNotNil(operation.readback?.observedContainer)
                XCTAssertEqual(operation.readback?.expectationMatched, true)
            }
        }
        let createCount = await manager.createCount
        let optionalStartCount = await manager.optionalStartCount
        XCTAssertEqual(createCount, 1)
        XCTAssertEqual(optionalStartCount, 1)
    }

    func testCreateRejectsExistingNameBeforeMutation() async throws {
        let manager = StubImageManager(mode: .existingContainer)
        let app = makeImageApplication(manager: manager)
        let expectedOrigin = origin
        let headerName = idempotencyName

        try await app.test(.router) { client in
            let headers: HTTPFields = [
                .origin: expectedOrigin,
                .contentType: "application/json",
                headerName: UUID().uuidString,
            ]
            try await client.execute(
                uri: "/api/v1/containers",
                method: .post,
                headers: headers,
                body: ByteBuffer(string: #"{"name":"demo","image":"postgres:latest"}"#)
            ) { response in
                XCTAssertEqual(response.status, .conflict)
                let problem = try JSONDecoder.containerGUI.decode(ProblemDetail.self, from: response.body)
                XCTAssertEqual(problem.code, .stateConflict)
            }
        }
        let createCount = await manager.createCount
        XCTAssertEqual(createCount, 0)
    }

    func testCreateRejectsPrivilegedHostPortBeforeMutation() async throws {
        let manager = StubImageManager()
        let app = makeImageApplication(manager: manager)
        let expectedOrigin = origin
        let headerName = idempotencyName

        try await app.test(.router) { client in
            let headers: HTTPFields = [
                .origin: expectedOrigin,
                .contentType: "application/json",
                headerName: UUID().uuidString,
            ]
            try await client.execute(
                uri: "/api/v1/containers",
                method: .post,
                headers: headers,
                body: ByteBuffer(string: #"{"name":"ubuntu-test","image":"ubuntu:26.04","ports":[{"hostPort":100,"containerPort":22}]}"#)
            ) { response in
                XCTAssertEqual(response.status, .unprocessableContent)
                let problem = try JSONDecoder.containerGUI.decode(ProblemDetail.self, from: response.body)
                XCTAssertEqual(problem.code, .validationFailed)
                XCTAssertEqual(problem.fieldErrors, [
                    FieldError(field: "ports", message: "主机端口必须使用 1024...65535；1024 以下需要 root 权限")
                ])
            }
        }
        let createCount = await manager.createCount
        XCTAssertEqual(createCount, 0)
    }

    func testCreateExitZeroWithoutReadbackEndsFailed() async throws {
        let manager = StubImageManager(mode: .missingCreateReadback)
        let app = makeImageApplication(manager: manager)
        let expectedOrigin = origin
        let headerName = idempotencyName

        try await app.test(.router) { client in
            let headers: HTTPFields = [
                .origin: expectedOrigin,
                .contentType: "application/json",
                headerName: UUID().uuidString,
            ]
            let operation: ContainerGUI.Operation = try await client.execute(
                uri: "/api/v1/containers",
                method: .post,
                headers: headers,
                body: ByteBuffer(string: #"{"name":"demo","image":"postgres:latest"}"#)
            ) { response in
                XCTAssertEqual(response.status, .accepted)
                return try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
            }
            try await Task.sleep(for: .milliseconds(80))
            try await client.execute(uri: "/api/v1/operations/\(operation.id.uuidString)", method: .get) { response in
                let completed = try JSONDecoder.containerGUI.decode(ContainerGUI.Operation.self, from: response.body)
                XCTAssertEqual(completed.state, .failed)
                XCTAssertEqual(completed.readback?.targetAbsent, true)
            }
        }
    }

    private func makeImageApplication(
        manager: StubImageManager
    ) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router()
        router.middlewares.add(ErrorMiddleware())
        router.middlewares.add(
            SafetyMiddleware(
                policy: RequestSafetyPolicy(expectedOrigin: origin, maximumBodyBytes: 64 * 1024)
            )
        )
        let coordinator = OperationCoordinator()
        let service = ImageMutationService(manager: manager, coordinator: coordinator)
        let creationService = ContainerCreationService(manager: manager, coordinator: coordinator)
        OperationRoutes.register(on: router, coordinator: coordinator)
        ResourceMutationRoutes.registerImages(on: router, reader: manager, service: service)
        ResourceMutationRoutes.registerCreation(on: router, service: creationService)
        return Application(router: router)
    }
}

private actor StubImageManager: ImageReading, ResourceMutating, ContainerControlling {
    enum Mode {
        case success
        case existingContainer
        case missingCreateReadback
    }

    private(set) var pullCount = 0
    private(set) var createCount = 0
    private(set) var optionalStartCount = 0
    private let mode: Mode
    private let observedAt = Date(timeIntervalSince1970: 1_787_987_200)

    init(mode: Mode = .success) {
        self.mode = mode
    }

    func listImages() async throws -> ImageList {
        ImageList(items: [image()], observedAt: observedAt)
    }

    func inspectImage(reference _: String) async throws -> ImageSummary {
        image()
    }

    func pullImage(
        _ request: ImagePullRequest,
        progress: @escaping @Sendable (ImagePullProgress) async -> Void
    ) async throws -> ImagePullOutcome {
        pullCount += 1
        await progress(ImagePullProgress(
            phase: .fetching,
            percentComplete: 35,
            completedUnits: 7,
            totalUnits: 20
        ))
        return ImagePullOutcome(
            exitCode: 0,
            observedImage: image(),
            matchedExpectation: request.platform == nil || request.platform == "linux/arm64"
        )
    }

    func listContainers() async throws -> ContainerList {
        let items = mode == .existingContainer ? [container(state: .stopped)] : []
        return ContainerList(items: items, observedAt: observedAt)
    }

    func startContainer(id _: String) async throws -> ContainerControlOutcome {
        let summary = container(state: .running)
        return ContainerControlOutcome(exitCode: 0, observedContainer: summary, matchedExpectation: true)
    }

    func stopContainer(id _: String) async throws -> ContainerControlOutcome {
        let summary = container(state: .stopped)
        return ContainerControlOutcome(exitCode: 0, observedContainer: summary, matchedExpectation: true)
    }

    func createContainer(_ request: ContainerCreateRequest) async throws -> ContainerCreateOutcome {
        createCount += 1
        if mode == .missingCreateReadback {
            return ContainerCreateOutcome(exitCode: 0, observedContainer: nil, matchedExpectation: false)
        }
        let state: ContainerState = request.startAfterCreate ? .running : .created
        if request.startAfterCreate { optionalStartCount += 1 }
        return ContainerCreateOutcome(
            exitCode: 0,
            observedContainer: container(state: state),
            matchedExpectation: true
        )
    }

    private func image() -> ImageSummary {
        ImageSummary(
            id: String(repeating: "a", count: 64),
            name: "docker.io/library/postgres:latest",
            digest: "sha256:" + String(repeating: "a", count: 64),
            platforms: [ImagePlatform(os: "linux", architecture: "arm64")],
            sizeBytes: 1_024,
            observedAt: observedAt
        )
    }

    private func container(state: ContainerState) -> ContainerSummary {
        ContainerSummary(
            id: "demo",
            displayName: "demo",
            imageReference: "postgres:latest",
            state: state,
            rawState: state.rawValue,
            ipv4Address: nil,
            ipv6Address: nil,
            createdAt: nil,
            observedAt: observedAt
        )
    }
}
