import Foundation
import XCTest

@testable import ContainerGUI

final class ProblemDetailTests: XCTestCase {
    func testExposesStableCodeAndChineseMessage() throws {
        let problem = ProblemDetail(
            code: .cliNotFound,
            diagnosticID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        )
        let data = try JSONEncoder.containerGUI.encode(problem)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["code"] as? String, "CLI_NOT_FOUND")
        XCTAssertEqual((object["message"] as? String)?.contains("container"), true)
        XCTAssertEqual(object["retryable"] as? Bool, false)
        XCTAssertEqual(object["diagnosticId"] as? String, "11111111-1111-1111-1111-111111111111")
    }

    func testFieldErrorsNeverEchoValues() throws {
        let problem = ProblemDetail(
            code: .validationFailed,
            fieldErrors: ["environment.API_TOKEN": "该字段不能为空"],
            diagnosticID: UUID()
        )
        let encoded = String(decoding: try JSONEncoder.containerGUI.encode(problem), as: UTF8.self)

        XCTAssertTrue(encoded.contains("environment.API_TOKEN"))
        XCTAssertFalse(encoded.contains("super-secret"))
    }

    func testRecursiveRedactionIsCaseInsensitive() throws {
        let value: JSONValue = .object([
            "Name": .string("demo"),
            "PASSWORD": .string("secret-a"),
            "nested": .object([
                "api_Token": .string("secret-b"),
                "safe": .string("visible"),
            ]),
        ])
        let encoded = String(
            decoding: try JSONEncoder.containerGUI.encode(value.redacted()),
            as: UTF8.self
        )

        XCTAssertTrue(encoded.contains("[REDACTED]"))
        XCTAssertTrue(encoded.contains("visible"))
        XCTAssertFalse(encoded.contains("secret-a"))
        XCTAssertFalse(encoded.contains("secret-b"))
    }
}
