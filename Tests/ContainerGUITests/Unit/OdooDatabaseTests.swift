import Darwin
import Foundation
import XCTest

@testable import ContainerGUI

final class OdooDatabaseTests: XCTestCase {
    func testCustomEnvironmentConfigIsFlaggedWithoutExposingItsPath() throws {
        let data = Data(#"[{"id":"odoo","configuration":{"id":"odoo","image":{"reference":"odoo:19"},"initProcess":{"environment":["ODOO_RC=/private/custom.conf"]}},"status":{"state":"stopped"}}]"#.utf8)
        let detail = try CLIOutputParser.parseContainerDetail(data: data, expectedID: "odoo")
        XCTAssertEqual(detail.odooConfigurationIsDefault, false)
        XCTAssertFalse(String(decoding: try JSONEncoder.containerGUI.encode(detail), as: UTF8.self).contains("/private/custom.conf"))
    }

    func testEndpointValidation() throws {
        let revision = String(repeating: "a", count: 64)
        let valid = OdooDatabaseSaveRequest(host: " 192.168.66.4 ", port: 5432, confirmationTarget: "odoo", expectedRevision: revision)
        XCTAssertEqual(try valid.validated(for: "odoo").host, "192.168.66.4")
        for host in ["", "http://localhost", "user:password@host", "a\nb", "$(id)", "host:5432", "-host"] {
            XCTAssertThrowsError(try OdooDatabaseSaveRequest(host: host, port: 5432, confirmationTarget: "odoo", expectedRevision: revision).validated(for: "odoo"))
        }
        for port in [0, -1, 65536] {
            XCTAssertThrowsError(try OdooDatabaseSaveRequest(host: "localhost", port: port, confirmationTarget: "odoo", expectedRevision: revision).validated(for: "odoo"))
        }
        XCTAssertThrowsError(try valid.validated(for: "other"))
        XCTAssertThrowsError(try OdooDatabaseSaveRequest(host: "localhost", port: 5432, confirmationTarget: "odoo", expectedRevision: "stale").validated(for: "odoo"))
        for host in ["localhost", "db.local", "192.168.66.4", "::1", "fd18:9f8d::4"] {
            XCTAssertNoThrow(try OdooDatabaseSaveRequest(host: host, port: 65535, confirmationTarget: "odoo", expectedRevision: revision).validated(for: "odoo"))
        }
    }

    func testHostSavePreservesOtherBytesPermissionsAndPrivateBackup() throws {
        let fixture = try temporaryConfig("# local\r\n[options]\r\ndb_host = 192.168.66.2\r\ndb_port = 5432\r\ndb_password = secret-fixture\r\naddons_path = /mnt/addons\r\n")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let original = try Data(contentsOf: fixture.file)
        let before = try OdooConfigurationFile.read(fixture.file)
        XCTAssertEqual(before.host, "192.168.66.2")
        let request = OdooDatabaseSaveRequest(host: "192.168.66.4", port: 5433, confirmationTarget: "odoo", expectedRevision: before.revision)
        try OdooConfigurationFile.write(fixture.file, request: request)
        let after = try OdooConfigurationFile.read(fixture.file)
        XCTAssertEqual(after.host, request.host)
        XCTAssertEqual(after.port, request.port)
        XCTAssertNotEqual(after.revision, before.revision)
        let expected = String(decoding: original, as: UTF8.self).replacingOccurrences(of: "192.168.66.2", with: "192.168.66.4").replacingOccurrences(of: "db_port = 5432", with: "db_port = 5433")
        XCTAssertEqual(try Data(contentsOf: fixture.file), Data(expected.utf8))
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o640)
        let backups = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "bak" }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: backups[0].path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertThrowsError(try OdooConfigurationFile.write(fixture.file, request: request))
        XCTAssertEqual(try Data(contentsOf: fixture.file), Data(expected.utf8))
    }

    func testMissingKeysInsertedWithinOptionsWithoutChangingOtherSections() throws {
        let fixture = try temporaryConfig("[options]\ndb_password = private\n[other]\nvalue = keep")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let before = try OdooConfigurationFile.read(fixture.file)
        XCTAssertEqual(before.port, 5432)
        try OdooConfigurationFile.write(fixture.file, request: .init(host: "db.local", port: 5432, confirmationTarget: "odoo", expectedRevision: before.revision))
        XCTAssertEqual(try String(contentsOf: fixture.file, encoding: .utf8), "[options]\ndb_password = private\ndb_host = db.local\ndb_port = 5432\n[other]\nvalue = keep")
    }

    func testMalformedOversizeLinksAndReadOnlyAreRejectedWithoutChanges() throws {
        for text in ["[options]\ndb_host=x\ndb_host=y\n", "[options]\ndb_port=oops\n", "[other]\ndb_host=x\n", "[options]\n[options]\n", String(repeating: "x", count: 131073)] {
            let fixture = try temporaryConfig(text)
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            XCTAssertThrowsError(try OdooConfigurationFile.read(fixture.file))
            XCTAssertEqual(try String(contentsOf: fixture.file, encoding: .utf8), text)
        }
        let fixture = try temporaryConfig("[options]\ndb_host=db.local\n")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let symbolic = fixture.directory.appendingPathComponent("link.conf")
        try FileManager.default.createSymbolicLink(at: symbolic, withDestinationURL: fixture.file)
        XCTAssertThrowsError(try OdooConfigurationFile.read(symbolic))
        let hard = fixture.directory.appendingPathComponent("hard.conf")
        try FileManager.default.linkItem(at: fixture.file, to: hard)
        XCTAssertThrowsError(try OdooConfigurationFile.read(fixture.file))
        try FileManager.default.removeItem(at: hard)
        let before = try OdooConfigurationFile.read(fixture.file)
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: fixture.file.path)
        XCTAssertThrowsError(try OdooConfigurationFile.write(fixture.file, request: .init(host: "other", port: 5432, confirmationTarget: "odoo", expectedRevision: before.revision)))
        XCTAssertEqual(try String(contentsOf: fixture.file, encoding: .utf8), "[options]\ndb_host=db.local\n")
    }

    func testGuestHelperPreservesFixtureAndReturnsOnlyEndpoint() async throws {
        let fixture = try temporaryConfig("[options]\ndb_host = old.local\ndb_port = 5432\ndb_password = secret-fixture\n")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let executor = FoundationProcessExecutor()
        func command(_ arguments: [String]) -> CommandRequest {
            CommandRequest(executableURL: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", OdooDatabaseGuest.script] + arguments, environment: ["ODOO_RC": fixture.file.path], timeout: .seconds(5), maximumOutputBytes: 4096)
        }
        let read = try await executor.run(command(["read", fixture.file.path]))
        XCTAssertEqual(read.exitCode, 0)
        XCTAssertFalse(read.stdoutString.contains("secret-fixture"))
        let before = try JSONDecoder().decode(OdooDatabaseEndpoint.self, from: read.stdout)
        let saved = try await executor.run(command(["write", fixture.file.path, "new.local", "5433", before.revision]))
        XCTAssertEqual(saved.exitCode, 0)
        XCTAssertEqual(try OdooConfigurationFile.read(fixture.file).host, "new.local")
        XCTAssertTrue(try String(contentsOf: fixture.file, encoding: .utf8).contains("db_password = secret-fixture"))
        let stale = try await executor.run(command(["write", fixture.file.path, "other", "5432", before.revision]))
        XCTAssertNotEqual(stale.exitCode, 0)
        XCTAssertFalse(stale.stdoutString.contains("secret-fixture"))
    }

    private func temporaryConfig(_ text: String) throws -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("odoo-config-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("odoo.conf")
        try Data(text.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)
        return (directory, file)
    }
}
