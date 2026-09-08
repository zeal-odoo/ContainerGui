import Darwin
import Foundation
import XCTest

@testable import ContainerGUI

final class AILogHistoryTests: XCTestCase {
    func testPersistsRedactedResultAcrossInstancesAndUsesPrivatePermissions() async throws {
        let directory = try historyDirectory()
        let store = AILogHistoryStore(directory: directory)
        let record = historyRecord()
        try await store.append(record)
        let reloaded = try await AILogHistoryStore(directory: directory).list(containerID: "demo", page: 1)
        XCTAssertEqual(reloaded.items.map(\.id), [record.id])
        XCTAssertFalse(reloaded.items[0].result.evidence.contains("clear-secret"))
        XCTAssertFalse(reloaded.items[0].result.text.contains("private-secret"))
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        let disk = try String(contentsOf: files[0], encoding: .utf8)
        XCTAssertFalse(disk.contains("clear-secret"))
        XCTAssertFalse(disk.contains("private-secret"))
        for (url, mode) in [(directory, 0o700), (files[0], 0o600)] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, mode)
        }
    }

    func testPaginationFilteringAndLatestThousandRetention() async throws {
        let directory = try historyDirectory()
        let store = AILogHistoryStore(directory: directory)
        let first = historyRecord(index: 0)
        try await store.append(first)
        for index in 1...1_000 { try await store.append(historyRecord(index: index)) }
        let all = try await store.list(containerID: nil, page: 1)
        XCTAssertEqual(all.total, 1_000)
        XCTAssertEqual(all.retentionLimit, 1_000)
        XCTAssertEqual(all.items.count, 10)
        XCTAssertEqual(all.items.first?.createdAt, historyRecord(index: 1_000).createdAt)
        let last = try await store.list(containerID: "demo", page: 100)
        XCTAssertEqual(last.items.count, 10)
        XCTAssertFalse(last.items.contains(where: { $0.id == first.id }))
        let missing = try await store.list(containerID: "other", page: 1)
        XCTAssertEqual(missing.total, 0)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(names.count, 1_000)
    }

    func testValidationEmptyReadAndPreciseDeletion() async throws {
        let directory = try historyDirectory()
        let store = AILogHistoryStore(directory: directory)
        let empty = try await store.list(containerID: "demo", page: 1)
        XCTAssertTrue(empty.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path), "Passive reads do not create storage")
        for page in [0, 101, Int.max] {
            do { _ = try await store.list(containerID: "demo", page: page); XCTFail("Invalid page") } catch {}
        }
        do { _ = try await store.list(containerID: "../demo", page: 1); XCTFail("Invalid identifier") } catch {}
        let keep = historyRecord()
        let remove = historyRecord(index: 1, containerID: "other")
        try await store.append(keep)
        try await store.append(remove)
        try await store.delete(id: remove.id)
        let remaining = try await store.list(containerID: nil, page: 100)
        XCTAssertEqual(remaining.page, 1)
        XCTAssertEqual(remaining.items.map(\.id), [keep.id])
        do { try await store.delete(id: remove.id); XCTFail("Not found") }
        catch let error as ProblemDetail { XCTAssertEqual(error.code, .targetNotFound) }
    }

    func testRejectsDirectoryAndAncestorSymlinksWithoutTouchingOutside() async throws {
        let directory = try historyDirectory()
        let outside = directory.deletingLastPathComponent().appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: outside)
        for target in [directory, directory.appendingPathComponent("child")] {
            let store = AILogHistoryStore(directory: target)
            do { try await store.append(historyRecord()); XCTFail("Must not follow a symlink") } catch {}
            do { _ = try await store.list(containerID: nil, page: 1); XCTFail("Must not read a symlink") } catch {}
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }

    func testRejectsLinkedCorruptOversizedAndPublicFiles() async throws {
        for variant in ["symlink", "hardlink", "corrupt", "oversized", "public"] {
            let directory = try historyDirectory()
            let store = AILogHistoryStore(directory: directory)
            try await store.append(historyRecord())
            let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
            let sentinel = directory.deletingLastPathComponent().appendingPathComponent("sentinel")
            try Data("outside-secret".utf8).write(to: sentinel)
            switch variant {
            case "symlink", "hardlink":
                try FileManager.default.removeItem(at: file)
                if variant == "symlink" { try FileManager.default.createSymbolicLink(at: file, withDestinationURL: sentinel) }
                else { try FileManager.default.linkItem(at: sentinel, to: file) }
            case "corrupt": try Data("invalid JSON".utf8).write(to: file)
            case "oversized": try Data(repeating: 65, count: 100_000).write(to: file)
            default: try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
            }
            do { _ = try await store.list(containerID: nil, page: 1); XCTFail("Must reject \(variant)") } catch {}
            XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "outside-secret")
        }
    }

    func testEncodedEscapesAndBoundedUntrustedText() async throws {
        let directory = try historyDirectory()
        let store = AILogHistoryStore(directory: directory)
        let text = String(repeating: String(repeating: "\u{0001}", count: 3_000) + "\n", count: 2)
        let record = AILogHistoryRecord(containerId: "demo", language: "zh", result: .init(
            text: text, evidence: text, observedAt: Date(), inputTokens: 1, outputTokens: 2, elapsedSeconds: 0.1))
        try await store.append(record)
        let page = try await store.list(containerID: nil, page: 1)
        XCTAssertLessThanOrEqual(page.items[0].result.text.utf8.count, 6_144)
        XCTAssertEqual(page.items.count, 1)
    }
}

extension XCTestCase {
    func historyDirectory() throws -> URL {
        let temporary = try XCTUnwrap(realpath(FileManager.default.temporaryDirectory.path, nil))
        defer { free(temporary) }
        let root = URL(fileURLWithPath: String(cString: temporary))
            .appendingPathComponent("ContainerGUI-history-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root.appendingPathComponent("history")
    }
}

func historyRecord(index: Int = 0, containerID: String = "demo") -> AILogHistoryRecord {
    AILogHistoryRecord(containerId: containerID, language: "zh",
                       createdAt: Date(timeIntervalSince1970: 1_788_800_000 + Double(index)),
                       result: .init(text: "Check database\nsecret=private-secret", evidence: "connection refused\nPASSWORD=clear-secret",
                                     observedAt: Date(timeIntervalSince1970: 1_788_799_999 + Double(index)),
                                     inputTokens: 50, outputTokens: 8, elapsedSeconds: 0.01))
}
