import CryptoKit
import Foundation
import XCTest

@testable import ContainerGUI

final class AIModelStoreTests: XCTestCase {
    func testFixedCatalogOnlyContainsPinnedNativeArtifacts() throws {
        let catalog = AIModelCatalog.qwen3
        XCTAssertEqual(catalog.revision, "0977a61d00e39118aab5ed1e510f1d228df5eefd")
        XCTAssertEqual(catalog.files.count, 22)
        XCTAssertGreaterThan(catalog.totalBytes, 1_900_000_000)
        XCTAssertLessThan(catalog.totalBytes, 2_000_000_000)
        for file in catalog.files {
            XCTAssertEqual(try catalog.url(for: file).host, "huggingface.co")
            XCTAssertTrue(try catalog.url(for: file).path.contains(catalog.revision))
            XCTAssertFalse(file.path.hasSuffix(".py"))
            XCTAssertNotEqual(file.path, "config.json")
            XCTAssertEqual(file.sha256.count, 64)
        }
    }

    func testInstallVerifiesEveryFileAndReturnsInstalledPayload() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = FixtureModelTransport(contents: Data("model".utf8))
        let store = AIModelStore(directory: directory, catalog: fixtureCatalog(), transport: transport)
        let before = await store.status()
        XCTAssertFalse(before.installed)
        try await store.install()
        let installed = await store.status()
        XCTAssertTrue(installed.installed)
        XCTAssertFalse(installed.downloading)
        XCTAssertEqual(installed.downloadedBytes, 5)
        let payload = try await store.verifiedDirectory()
        XCTAssertEqual(try Data(contentsOf: payload.appendingPathComponent("model/weights.bin")), Data("model".utf8))
        try await store.install()
        let requests = await transport.requests
        XCTAssertEqual(requests, 1)
    }

    func testCorruptAndOversizedDownloadsNeverBecomeReadyAndRetrySucceeds() async throws {
        for bytes in [Data("wrong".utf8), Data("too large".utf8)] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let transport = FixtureModelTransport(contents: bytes)
            let store = AIModelStore(directory: directory, catalog: fixtureCatalog(), transport: transport)
            do {
                try await store.install()
                XCTFail("Invalid payload must not be installed")
            } catch {}
            let failed = await store.status()
            XCTAssertFalse(failed.installed)
            XCTAssertFalse(failed.downloading)
            await transport.setContents(Data("model".utf8))
            try await store.install()
            let retried = await store.status()
            XCTAssertTrue(retried.installed)
        }
    }

    func testModifiedInstalledFileFailsVerification() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AIModelStore(directory: directory, catalog: fixtureCatalog(), transport: FixtureModelTransport())
        try await store.install()
        let payload = try await store.verifiedDirectory()
        try Data("wrong".utf8).write(to: payload.appendingPathComponent("model/weights.bin"))
        do {
            _ = try await store.verifiedDirectory()
            XCTFail("Equal-size corruption must fail SHA verification")
        } catch {}
        let status = await store.status()
        XCTAssertFalse(status.installed)
    }

    func testConcurrentInstallRequestsShareOneDownload() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = FixtureModelTransport(delay: .milliseconds(50))
        let store = AIModelStore(directory: directory, catalog: fixtureCatalog(), transport: transport)
        async let first: Void = store.install()
        async let second: Void = store.install()
        _ = try await (first, second)
        let requests = await transport.requests
        XCTAssertEqual(requests, 1)
    }

    func testPayloadSymlinkAndUnexpectedFileInvalidateReadiness() async throws {
        let directory = temporaryDirectory()
        let outside = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinel = outside.appendingPathComponent("sentinel")
        try Data("model".utf8).write(to: sentinel)
        let store = AIModelStore(directory: directory, catalog: fixtureCatalog(), transport: FixtureModelTransport())
        try await store.install()
        let payload = try await store.verifiedDirectory()
        let unexpected = payload.appendingPathComponent("unexpected.py")
        try Data("unexpected".utf8).write(to: unexpected)
        let unexpectedStatus = await store.status()
        XCTAssertFalse(unexpectedStatus.installed)
        try FileManager.default.removeItem(at: unexpected)
        let weights = payload.appendingPathComponent("model/weights.bin")
        try FileManager.default.removeItem(at: weights)
        try FileManager.default.createSymbolicLink(at: weights, withDestinationURL: sentinel)
        let symlinkStatus = await store.status()
        XCTAssertFalse(symlinkStatus.installed)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("model".utf8))
    }

    func testTraversalAndSymlinksAreRejectedWithoutChangingOutsideFiles() async throws {
        let directory = temporaryDirectory()
        let outside = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinel = outside.appendingPathComponent("sentinel")
        try Data("keep".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: outside)
        let store = AIModelStore(directory: directory, catalog: fixtureCatalog(), transport: FixtureModelTransport())
        do {
            try await store.install()
            XCTFail("Symlink cache must be refused")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))

        let unsafe = fixtureCatalog(path: "../sentinel")
        XCTAssertThrowsError(try unsafe.validate())
        XCTAssertThrowsError(try unsafe.url(for: unsafe.files[0]))
    }

    func testUnownedDirectoryIsNotOverwritten() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sentinel = directory.appendingPathComponent("personal.txt")
        try Data("keep".utf8).write(to: sentinel)
        let store = AIModelStore(directory: directory, catalog: fixtureCatalog(), transport: FixtureModelTransport())
        do {
            try await store.install()
            XCTFail("Existing unrelated directory must be refused")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
    }

    func testInsufficientDiskSpacePreventsNetworkRequest() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = FixtureModelTransport()
        let store = AIModelStore(directory: directory, catalog: fixtureCatalog(), transport: transport, availableBytes: { _ in 0 })
        do {
            try await store.install()
            XCTFail("Insufficient space must fail before downloading")
        } catch let error as AIModelStoreError {
            XCTAssertEqual(error, .insufficientDiskSpace)
        }
        let requests = await transport.requests
        XCTAssertEqual(requests, 0)
    }

    func testRetryOnlyNeedsDiskSpaceForFilesNotAlreadyVerified() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = fixtureCatalog()
        let second = AIModelFile(path: "model/second.bin", size: 5, sha256: base.files[0].sha256)
        let catalog = AIModelCatalog(name: base.name, repository: base.repository, revision: base.revision, files: base.files + [second])
        let interrupted = AIModelStore(directory: directory, catalog: catalog,
                                       transport: FixtureModelTransport(failAtRequest: 2))
        do {
            try await interrupted.install()
            XCTFail("Second fixture request should interrupt installation")
        } catch {}
        let resumedTransport = FixtureModelTransport()
        let resumed = AIModelStore(directory: directory, catalog: catalog, transport: resumedTransport,
                                   availableBytes: { _ in 256 * 1024 * 1024 + 5 })
        try await resumed.install()
        let requests = await resumedTransport.requests
        XCTAssertEqual(requests, 1)
        let status = await resumed.status()
        XCTAssertTrue(status.installed)
    }

    func testCancellationLeavesNoReadyPayloadAndCanRetry() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = FixtureModelTransport(delay: .seconds(30))
        let store = AIModelStore(directory: directory, catalog: fixtureCatalog(), transport: transport)
        let installing = Task { try await store.install() }
        for _ in 0..<100 {
            if await transport.requests > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await store.cancel()
        do {
            try await installing.value
            XCTFail("Cancelled installation must throw")
        } catch {}
        let cancelled = await store.status()
        XCTAssertFalse(cancelled.installed)
        XCTAssertFalse(cancelled.downloading)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("staging/.ready").path))
        await transport.setDelay(.zero)
        try await store.install()
        let retried = await store.status()
        XCTAssertTrue(retried.installed)
    }

    func testRedirectPolicyRejectsCredentialAndForeignDestinations() {
        for url in ["http://huggingface.co/a", "https://example.com/a", "https://huggingface.co.evil.test/a", "https://user:password@huggingface.co/a", "https://huggingface.co:1234/a"] {
            XCTAssertFalse(AIModelCatalog.permitsDownloadURL(URL(string: url)!))
        }
        for url in ["https://huggingface.co/a", "https://cas-bridge.xethub.hf.co/a?token=public-signature", "https://cdn-lfs.hf.co/a"] {
            XCTAssertTrue(AIModelCatalog.permitsDownloadURL(URL(string: url)!))
        }
    }

    func testDownloadPinnedModelForOptInRuntimeValidation() async throws {
        guard ProcessInfo.processInfo.environment["CONTAINER_GUI_AI_DOWNLOAD_TEST"] == "1" else {
            throw XCTSkip("Set CONTAINER_GUI_AI_DOWNLOAD_TEST=1 for the authorized 1.95 GB model download")
        }
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/ai-model-test")
        let store = AIModelStore(directory: directory)
        try await store.install()
        let payload = try await store.verifiedDirectory()
        print("AI_MODEL_VERIFIED_DIRECTORY=\(payload.path)")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ContainerGUI-AIModelStoreTests-\(UUID().uuidString)")
    }

    private func fixtureCatalog(path: String = "model/weights.bin") -> AIModelCatalog {
        AIModelCatalog(name: "Test model", repository: AIModelCatalog.qwen3.repository, revision: AIModelCatalog.qwen3.revision, files: [
            AIModelFile(path: path, size: 5, sha256: SHA256.hash(data: Data("model".utf8)).map { String(format: "%02x", $0) }.joined())
        ])
    }
}

private actor FixtureModelTransport: AIModelTransport {
    private var contents: Data
    private var delay: Duration
    private let failAtRequest: Int?
    private(set) var requests = 0

    init(contents: Data = Data("model".utf8), delay: Duration = .zero, failAtRequest: Int? = nil) {
        self.contents = contents
        self.delay = delay
        self.failAtRequest = failAtRequest
    }

    func setContents(_ contents: Data) { self.contents = contents }
    func setDelay(_ delay: Duration) { self.delay = delay }

    func download(from url: URL, to handle: FileHandle, expectedBytes: Int64, progress: @escaping @Sendable (Int64) -> Void) async throws {
        requests += 1
        if requests == failAtRequest { throw AIModelStoreError.downloadFailed }
        if delay > .zero { try await Task.sleep(for: delay) }
        try Task.checkCancellation()
        try handle.write(contentsOf: contents)
        progress(Int64(contents.count))
    }
}
