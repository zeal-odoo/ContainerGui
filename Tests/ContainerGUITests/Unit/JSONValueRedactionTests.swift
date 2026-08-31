import Foundation
import XCTest

@testable import ContainerGUI

final class JSONValueRedactionTests: XCTestCase {
    func testRedactsEveryEnvironmentValueAndCredentialURIForm() throws {
        let value = JSONValue.object([
            "configuration": .object([
                "environment": .array([
                    .string("VISIBLE=ordinary-value"),
                    .string("DATABASE_URL=postgres://db-user:db-password@database/app"),
                    .object([
                        "name": .string("AWS_SECRET_ACCESS_KEY"),
                        "value": .string("aws-secret-value"),
                    ]),
                    .object([
                        "Name": .string("DB-PASS"),
                        "Value": .array([.string("nested-secret-value")]),
                    ]),
                ]),
                "env": .object([
                    "PGPASSWORD": .string("pg-secret-value"),
                    "FEATURE_FLAG": .string("enabled"),
                ]),
            ]),
            "serviceURL": .string(
                "postgres://service-user:uri-secret@database/app?token=query-secret&mode=read"
            ),
            "downloadURL": .string(
                "https://bearer-userinfo@example.invalid/archive?X-Amz-Signature=signed-secret&mode=read"
            ),
            "displayName": .string("demo"),
        ])

        let encoded = String(
            decoding: try JSONEncoder.containerGUI.encode(value.redacted()),
            as: UTF8.self
        )

        for secret in [
            "ordinary-value",
            "db-password",
            "aws-secret-value",
            "pg-secret-value",
            "enabled",
            "nested-secret-value",
            "uri-secret",
            "query-secret",
            "service-user",
            "bearer-userinfo",
            "signed-secret",
        ] {
            XCTAssertFalse(encoded.contains(secret), secret)
        }
        for diagnosticValue in [
            "VISIBLE",
            "DATABASE_URL",
            "AWS_SECRET_ACCESS_KEY",
            "PGPASSWORD",
            "FEATURE_FLAG",
            "DB-PASS",
            "database",
            "mode=read",
            "demo",
        ] {
            XCTAssertTrue(encoded.contains(diagnosticValue), diagnosticValue)
        }
    }
}
