import Darwin
import Foundation
import XCTest

@testable import ContainerGUI

final class ContainerConnectionTests: XCTestCase {
    func testEndpointValidationRejectsCommandsURLsInvalidIDsAndRevisions() throws {
        let revision = String(repeating: "a", count: 64)
        for host in ["https://db", "user:secret@db", "db:5432", "$(id)", "db\nother", ""] {
            XCTAssertThrowsError(try ContainerConnectionSaveRequest(endpointId: "database", host: host, port: 5432, confirmationTarget: "app", expectedRevision: revision).validated(for: "app"))
        }
        for port in [0, -1, 65536] {
            XCTAssertThrowsError(try ContainerConnectionSaveRequest(endpointId: "database", host: "db", port: port, confirmationTarget: "app", expectedRevision: revision).validated(for: "app"))
        }
        let valid = ContainerConnectionSaveRequest(endpointId: "proxy-1", host: " ::1 ", port: 65535, confirmationTarget: "app", expectedRevision: revision)
        XCTAssertEqual(try valid.validated(for: "app").host, "::1")
        XCTAssertThrowsError(try valid.validated(for: "other"))
        XCTAssertThrowsError(try ContainerConnectionSaveRequest(endpointId: "../config", host: "db", port: 5432, confirmationTarget: "app", expectedRevision: "old").validated(for: "app"))
    }

    func testDotenvPreservesQuotesCommentsCredentialsAndCRLF() throws {
        let original = "# settings\r\nDB_HOST = \"old.local\" # keep\r\nDB_PORT='5432'\r\nDB_PASSWORD=secret-fixture\r\nAPI_KEY=private-fixture\r\n"
        let document = try ConnectionDocument(Data(original.utf8), format: .dotenv)
        XCTAssertEqual(document.endpoints.first?.host, "old.local")
        let changed = try document.replacing(endpointId: "database", host: "new.local", port: 5433)
        XCTAssertEqual(String(decoding: changed, as: UTF8.self), original.replacingOccurrences(of: "old.local", with: "new.local").replacingOccurrences(of: "'5432'", with: "'5433'"))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(document.endpoints), as: UTF8.self).contains("secret-fixture"))
        for text in ["DB_HOST=db\n", "DB_HOST=db\nDB_HOST=other\nDB_PORT=5432\n", "DB_HOST=${HOST}\nDB_PORT=5432\n", "DB_HOST=db\nDB_PORT=oops\n"] {
            XCTAssertThrowsError(try ConnectionDocument(Data(text.utf8), format: .dotenv))
        }
    }

    func testNginxEditsOneDirectiveAndPreservesSchemeURITrailingSlashAndOtherPorts() throws {
        let original = "# proxy_pass http://ignore:1;\r\nserver {\r\n location /query/ { proxy_pass http://old.local:8503/route/?q=keep; }\r\n location / { proxy_pass https://old.local:5000/; }\r\n set $example \"proxy_pass http://ignore:2;\";\r\n}\r\n"
        let document = try ConnectionDocument(Data(original.utf8), format: .nginx)
        XCTAssertEqual(document.endpoints.count, 2)
        XCTAssertEqual(document.endpoints[0].port, 8503)
        XCTAssertEqual(document.endpoints[0].label, "/query/")
        let changed = try document.replacing(endpointId: "proxy-1", host: "::1", port: 8603)
        XCTAssertEqual(String(decoding: changed, as: UTF8.self), original.replacingOccurrences(of: "http://old.local:8503", with: "http://[::1]:8603"))
        XCTAssertThrowsError(try document.replacing(endpointId: "proxy-9", host: "new.local", port: 5432))
        let defaultPort = try ConnectionDocument(Data("location / { proxy_pass https://db.local/path; }".utf8), format: .nginx)
        XCTAssertEqual(defaultPort.endpoints.first?.port, 443)
        XCTAssertEqual(String(decoding: try defaultPort.replacing(endpointId: "proxy-1", host: "new.local", port: 444), as: UTF8.self), "location / { proxy_pass https://new.local:444/path; }")
    }

    func testNginxRejectsDynamicUpstreamIncludesSocketsCredentialsAndOversizedFiles() throws {
        for text in ["proxy_pass http://$host:5000;", "upstream backend { server db:5000; } proxy_pass http://backend;", "include /etc/nginx/conf.d/*.conf; proxy_pass http://db:80;", "proxy_pass http://unix:/tmp/socket;", "proxy_pass http://user:secret@db:80;", "proxy_pass http://db:0;", "proxy_pass http://db:80", "proxy_pass \"http://db:80\";", "server { proxy_pass http://db:80;", String(repeating: "x", count: 131073)] {
            XCTAssertThrowsError(try ConnectionDocument(Data(text.utf8), format: .nginx), text.prefix(80).description)
        }
        XCTAssertNoThrow(try ConnectionDocument(Data("include /etc/nginx/mime.types; proxy_pass http://db:80;".utf8), format: .nginx))
    }

    func testMultilineSecretsQuotedDatabaseKeysAndEscapedDirectivesAreNotEditable() throws {
        for text in ["API_KEY=\"private\nDB_HOST=hidden.local\nDB_PORT=5432\n\"\n", "'DB_HOST'=override.local\nDB_HOST=db.local\nDB_PORT=5432\n"] {
            XCTAssertThrowsError(try ConnectionDocument(Data(text.utf8), format: .dotenv))
        }
        for text in ["proxy_pass http://db.local:80; inc\\lude /custom.conf;", "location /a\\{b { proxy_pass http://db.local:80; }"] {
            XCTAssertThrowsError(try ConnectionDocument(Data(text.utf8), format: .nginx))
        }
    }

    func testHostSaveBackupsPermissionsRevisionsAndSingleFileInode() throws {
        for preserveInode in [true, false] {
            let fixture = try fileFixture("DB_HOST=old.local\nDB_PORT=5432\nDB_PASSWORD=secret-fixture\n")
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            let original = try OdooConfigurationFile.readData(fixture.file)
            let inode = try FileManager.default.attributesOfItem(atPath: fixture.file.path)[.systemFileNumber] as? NSNumber
            let document = try ConnectionDocument(original, format: .dotenv)
            try OdooConfigurationFile.writeData(fixture.file, preserveInode: preserveInode) { data in
                let current = try ConnectionDocument(data, format: .dotenv)
                guard current.revision == document.revision else { throw OdooConfigurationError.stale }
                return try current.replacing(endpointId: "database", host: "new.local", port: 5433)
            }
            let observed = try ConnectionDocument(OdooConfigurationFile.readData(fixture.file), format: .dotenv)
            XCTAssertEqual(observed.endpoints.first?.host, "new.local")
            let attributes = try FileManager.default.attributesOfItem(atPath: fixture.file.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o640)
            if preserveInode { XCTAssertEqual(attributes[.systemFileNumber] as? NSNumber, inode) }
            let backups = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "bak" }
            XCTAssertEqual(backups.count, 1)
            XCTAssertEqual(try Data(contentsOf: backups[0]), original)
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: backups[0].path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            let after = try Data(contentsOf: fixture.file)
            XCTAssertThrowsError(try OdooConfigurationFile.writeData(fixture.file, preserveInode: preserveInode) { data in
                guard try ConnectionDocument(data, format: .dotenv).revision == document.revision else { throw OdooConfigurationError.stale }
                return Data()
            })
            XCTAssertEqual(try Data(contentsOf: fixture.file), after)
        }
    }

    func testLinkedUnsafeReadonlyAndOversizedHostFilesNeverChange() throws {
        let fixture = try fileFixture("DB_HOST=db\nDB_PORT=5432\n")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let original = try Data(contentsOf: fixture.file)
        let link = fixture.directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.file)
        XCTAssertThrowsError(try OdooConfigurationFile.readData(link))
        let hard = fixture.directory.appendingPathComponent("hard")
        try FileManager.default.linkItem(at: fixture.file, to: hard)
        XCTAssertThrowsError(try OdooConfigurationFile.writeData(fixture.file, preserveInode: true) { _ in Data() })
        try FileManager.default.removeItem(at: hard)
        for mode in [0o400, 0o666] {
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: fixture.file.path)
            XCTAssertThrowsError(try OdooConfigurationFile.readData(fixture.file))
            XCTAssertThrowsError(try OdooConfigurationFile.writeData(fixture.file, preserveInode: true) { _ in Data() })
            XCTAssertEqual(try Data(contentsOf: fixture.file), original)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.file.path)
        XCTAssertThrowsError(try OdooConfigurationFile.writeData(fixture.file) { _ in Data(repeating: 0, count: 131073) })
        XCTAssertEqual(try Data(contentsOf: fixture.file), original)
    }

    private func fileFixture(_ text: String) throws -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("connection-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("config")
        try Data(text.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)
        return (directory, file)
    }
}
