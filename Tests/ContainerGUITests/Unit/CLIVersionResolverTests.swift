import Foundation
import XCTest

@testable import ContainerGUI

final class CLIVersionResolverTests: XCTestCase {
    func testResolvesExplicitExecutable() throws {
        let resolver = CLIVersionResolver(
            fileManager: .default,
            environment: ["PATH": "/usr/bin:/bin"]
        )

        XCTAssertEqual(try resolver.resolve(explicitPath: "/bin/sh").path, "/bin/sh")
    }

    func testReportsMissingAndNonExecutable() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("not executable".utf8).write(to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let resolver = CLIVersionResolver(fileManager: .default, environment: ["PATH": ""])
        XCTAssertThrowsError(try resolver.resolve(explicitPath: temporary.path)) { error in
            XCTAssertEqual(error as? CLIResolutionError, .notExecutable(path: temporary.path))
        }
        XCTAssertThrowsError(try resolver.resolve(explicitPath: "/definitely/missing/container"))
    }

    func testRecognizesSupportedVersion() {
        for text in ["container 1.3.1", "container version 1.3.1 (release)", "1.3.1"] {
            let result = CLIVersionResolver.classify(versionText: text)
            XCTAssertEqual(result.semanticVersion, SemanticVersion(major: 1, minor: 3, patch: 1))
            XCTAssertEqual(result.compatibility, .supported)
        }
    }

    func testRejectsUnsupportedMajorOrMinor() {
        for text in ["container 1.2.9", "container 1.4.0", "container 1.5.0", "container 2.0.0"] {
            XCTAssertEqual(CLIVersionResolver.classify(versionText: text).compatibility, .unsupported)
        }
    }

    func testSupports141AndCompatiblePatchReleases() {
        for version in ["1.3.0", "1.3.2", "1.4.1", "1.4.2"] {
            let result = CLIVersionResolver.classify(
                versionText: "container CLI version \(version) (build: release, commit: fixture)"
            )
            XCTAssertEqual(result.semanticVersion?.description, version)
            XCTAssertEqual(result.compatibility, .supported)
        }
    }

    func testRejectsUnrecognizedVersionText() {
        let result = CLIVersionResolver.classify(versionText: "container development build")
        XCTAssertNil(result.semanticVersion)
        XCTAssertEqual(result.compatibility, .unrecognized)
    }
}
