import Hummingbird
import HummingbirdTesting
import HTTPTypes
import XCTest

@testable import ContainerGUI

final class AuthenticationMiddlewareTests: XCTestCase {
    func testApplicationFactoryProtectsStaticFilesAndReadAPI() async throws {
        let authentication = APIAuthentication(token: String(repeating: "b", count: 64))
        let configuration = try AppConfiguration(environment: [:])
        let router = AppFactory.makeRouter(
            configuration: configuration,
            reader: AuthenticationStubReader(),
            authentication: authentication
        )
        let app = Application(router: router)

        try await app.test(.router) { client in
            for uri in ["/", "/api/v1"] {
                try await client.execute(uri: uri, method: .get) { response in
                    XCTAssertEqual(response.status, .unauthorized)
                }
            }
            for uri in ["/", "/api/v1"] {
                try await client.execute(
                    uri: uri,
                    method: .get,
                    headers: [.authorization: authentication.authorizationHeaderValue]
                ) { response in
                    XCTAssertEqual(response.status, .ok)
                }
            }
        }
    }

    func testRequiresValidBasicAuthenticationForReadsAndMutations() async throws {
        let authentication = APIAuthentication(
            token: String(repeating: "a", count: 64)
        )
        let router = Router()
        router.middlewares.add(
            APIAuthenticationMiddleware(authentication: authentication)
        )
        router.get("/api/v1/read") { _, _ in "read" }
        router.post("/api/v1/mutate") { _, _ in "mutated" }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/v1/read", method: .get) { response in
                XCTAssertEqual(response.status, .unauthorized)
                XCTAssertEqual(
                    response.headers[HTTPField.Name("WWW-Authenticate")!],
                    #"Basic realm="Container GUI", charset="UTF-8""#
                )
            }
            try await client.execute(
                uri: "/api/v1/mutate",
                method: .post,
                headers: [
                    .origin: "http://127.0.0.1:8787",
                    .contentType: "application/json",
                ],
                body: ByteBuffer(string: "{}")
            ) { response in
                XCTAssertEqual(response.status, .unauthorized)
            }
            try await client.execute(
                uri: "/api/v1/read",
                method: .get,
                headers: [.authorization: "Basic invalid"]
            ) { response in
                XCTAssertEqual(response.status, .unauthorized)
            }
            try await client.execute(
                uri: "/api/v1/read",
                method: .get,
                headers: [.authorization: authentication.authorizationHeaderValue]
            ) { response in
                XCTAssertEqual(response.status, .ok)
            }
            try await client.execute(
                uri: "/api/v1/mutate",
                method: .post,
                headers: [
                    .authorization: authentication.authorizationHeaderValue,
                    .origin: "http://127.0.0.1:8787",
                    .contentType: "application/json",
                ],
                body: ByteBuffer(string: "{}")
            ) { response in
                XCTAssertEqual(response.status, .ok)
            }
        }
    }

    func testTokenStoreCreatesPrivatePersistentCredential() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("container-gui-auth-\(UUID().uuidString)", isDirectory: true)
        let tokenFile = root.appendingPathComponent("auth-token")
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try APIAuthentication.loadOrCreate(tokenFileURL: tokenFile)
        let second = try APIAuthentication.loadOrCreate(tokenFileURL: tokenFile)

        XCTAssertEqual(first.token, second.token)
        XCTAssertEqual(first.token.count, 64)
        XCTAssertTrue(first.token.allSatisfy(\.isHexDigit))
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: tokenFile.path)
        XCTAssertEqual(directoryAttributes[.posixPermissions] as? Int, 0o700)
        XCTAssertEqual(fileAttributes[.posixPermissions] as? Int, 0o600)
    }
}

private struct AuthenticationStubReader: ContainerReading {
    func systemHealth() async throws -> SystemHealth {
        throw ProblemDetail(code: .serviceUnavailable)
    }

    func listContainers() async throws -> ContainerList {
        throw ProblemDetail(code: .serviceUnavailable)
    }

    func containerDetail(id: String) async throws -> ContainerDetail {
        throw ProblemDetail(code: .targetNotFound)
    }
}
