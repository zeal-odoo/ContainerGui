import Hummingbird
import HummingbirdTesting
import HTTPTypes
import XCTest

@testable import ContainerGUI

final class LocalAccessCompatibilityTests: XCTestCase {
    func testStaticFilesAndReadAPIStayAccessibleWithoutCredentials() async throws {
        let configuration = try AppConfiguration(environment: [:])
        let router = AppFactory.makeRouter(
            configuration: configuration,
            reader: LocalAccessStubReader()
        )
        let app = Application(router: router)

        try await app.test(.router) { client in
            for uri in ["/", "/api/v1"] {
                try await client.execute(uri: uri, method: .get) { response in
                    XCTAssertEqual(response.status, .ok)
                    XCTAssertNil(response.headers[HTTPField.Name("WWW-Authenticate")!])
                }
            }
        }
    }
}

private struct LocalAccessStubReader: ContainerReading {
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
