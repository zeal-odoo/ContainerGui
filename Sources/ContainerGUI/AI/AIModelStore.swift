import CryptoKit
import Darwin
import Foundation

struct AIModelInstallation: Codable, Sendable {
    let name: String
    let installed: Bool
    let downloading: Bool
    let downloadedBytes: Int64
    let totalBytes: Int64
}

enum AIModelStoreError: String, Error, Sendable {
    case invalidManifest = "ai_model_invalid_manifest"
    case unsafeDirectory = "ai_model_unsafe_directory"
    case insufficientDiskSpace = "ai_model_insufficient_disk_space"
    case notInstalled = "ai_model_not_installed"
    case verificationFailed = "ai_model_verification_failed"
    case downloadFailed = "ai_model_download_failed"
}

protocol AIModelTransport: Sendable {
    func download(from url: URL, to handle: FileHandle, expectedBytes: Int64,
                  progress: @escaping @Sendable (Int64) -> Void) async throws
}

actor AIModelStore {
    static let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/ContainerGUI/Models/qwen3-1.7b-ane-0977a61d")

    private let directory: URL
    private let catalog: AIModelCatalog
    private let transport: any AIModelTransport
    private let availableBytes: @Sendable (URL) throws -> Int64
    private var installationTask: Task<Void, Error>?
    private var verificationTask: Task<[FileStamp], Error>?
    private var downloadedBytes: Int64 = 0
    private var verifiedStamps: [FileStamp]?

    init(directory: URL = AIModelStore.defaultDirectory,
         catalog: AIModelCatalog = .qwen3,
         transport: any AIModelTransport = AIModelHTTPTransport(),
         availableBytes: @escaping @Sendable (URL) throws -> Int64 = { url in
             let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
             guard let bytes = values.volumeAvailableCapacityForImportantUsage else {
                 throw AIModelStoreError.insufficientDiskSpace
             }
             return bytes
         }) {
        self.directory = directory.standardizedFileURL
        self.catalog = catalog
        self.transport = transport
        self.availableBytes = availableBytes
    }

    func status() async -> AIModelInstallation {
        var installed = false
        do {
            let stamps = try Self.stamps(in: directory, catalog: catalog)
            if verifiedStamps != stamps {
                _ = try await verifiedDirectory()
            }
            installed = true
        } catch {
            verifiedStamps = nil
        }
        return AIModelInstallation(name: catalog.name, installed: installed,
                                   downloading: installationTask != nil,
                                   downloadedBytes: installed ? catalog.totalBytes : downloadedBytes,
                                   totalBytes: catalog.totalBytes)
    }

    func install() async throws {
        if let installationTask {
            try await installationTask.value
            return
        }
        let task = Task { try await performInstall() }
        installationTask = task
        defer { installationTask = nil }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func cancel() async {
        installationTask?.cancel()
        _ = try? await installationTask?.value
    }

    func verifiedDirectory() async throws -> URL {
        if let verificationTask {
            verifiedStamps = try await verificationTask.value
            try Task.checkCancellation()
            return directory.appendingPathComponent("installed")
        }
        verifiedStamps = nil
        let directory = directory
        let catalog = catalog
        let verification = Task.detached(priority: .utility) {
            let before = try Self.stamps(in: directory, catalog: catalog)
            let payload = directory.appendingPathComponent("installed")
            for file in catalog.files {
                try Self.verify(file, in: payload)
            }
            let after = try Self.stamps(in: directory, catalog: catalog)
            guard before == after else { throw AIModelStoreError.verificationFailed }
            return after
        }
        verificationTask = verification
        defer { verificationTask = nil }
        let stamps = try await withTaskCancellationHandler {
            try await verification.value
        } onCancel: {
            verification.cancel()
        }
        try Task.checkCancellation()
        verifiedStamps = stamps
        return directory.appendingPathComponent("installed")
    }

    private func performInstall() async throws {
        try catalog.validate()
        try Task.checkCancellation()
        if (try? await verifiedDirectory()) != nil { return }
        try Task.checkCancellation()
        try prepareCache()
        let staging = directory.appendingPathComponent("staging")
        try Self.ensureDirectory(staging)
        try Self.validateTree(staging, catalog: catalog, requiresAllFiles: false)
        let catalog = catalog
        let retainedVerification = Task.detached(priority: .utility) {
            var retained = Set<String>()
            for file in catalog.files {
                try Task.checkCancellation()
                if (try? Self.verify(file, in: staging)) != nil { retained.insert(file.path) }
            }
            return retained
        }
        let retained = try await withTaskCancellationHandler {
            try await retainedVerification.value
        } onCancel: { retainedVerification.cancel() }
        let missingBytes = catalog.files.filter { !retained.contains($0.path) }.reduce(Int64(0)) { $0 + $1.size }
        guard try availableBytes(directory) >= missingBytes + 256 * 1024 * 1024 else {
            throw AIModelStoreError.insufficientDiskSpace
        }
        downloadedBytes = 0
        for file in catalog.files {
            try Task.checkCancellation()
            let destination = staging.appendingPathComponent(file.path)
            if retained.contains(file.path) {
                downloadedBytes += file.size
                continue
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try Self.requireRegularFile(destination)
                try FileManager.default.removeItem(at: destination)
            }
            try Self.ensureParents(of: file.path, in: staging)
            let descriptor = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { throw AIModelStoreError.unsafeDirectory }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            let completed = downloadedBytes
            do {
                try await transport.download(from: catalog.url(for: file), to: handle, expectedBytes: file.size) { bytes in
                    Task { await self.recordProgress(completed + min(bytes, file.size)) }
                }
                try handle.synchronize()
                try handle.close()
                try Task.checkCancellation()
                let verification = Task.detached(priority: .utility) { try Self.verify(file, in: staging) }
                try await withTaskCancellationHandler { try await verification.value } onCancel: { verification.cancel() }
            } catch {
                try? handle.close()
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                throw (error as? AIModelStoreError) ?? AIModelStoreError.downloadFailed
            }
            downloadedBytes = completed + file.size
        }
        try Task.checkCancellation()
        let finalVerification = Task.detached(priority: .utility) {
            let before = try Self.payloadStamps(in: staging, catalog: catalog)
            for file in catalog.files { try Self.verify(file, in: staging) }
            guard before == (try Self.payloadStamps(in: staging, catalog: catalog)) else {
                throw AIModelStoreError.verificationFailed
            }
        }
        try await withTaskCancellationHandler { try await finalVerification.value } onCancel: { finalVerification.cancel() }
        try Task.checkCancellation()
        let ready = staging.appendingPathComponent(".ready")
        if FileManager.default.fileExists(atPath: ready.path) { try Self.requireRegularFile(ready) }
        try Data(catalog.identity.utf8).write(to: ready, options: .atomic)
        let installed = directory.appendingPathComponent("installed")
        if FileManager.default.fileExists(atPath: installed.path) {
            try Self.requireDirectory(installed)
            // This exact generated payload is inside the ownership-checked private cache.
            try FileManager.default.removeItem(at: installed)
        }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: installed)
        verifiedStamps = try Self.stamps(in: directory, catalog: catalog)
    }

    private func recordProgress(_ bytes: Int64) {
        guard installationTask != nil else { return }
        downloadedBytes = max(downloadedBytes, min(bytes, catalog.totalBytes))
    }

    private func prepareCache() throws {
        guard directory.isFileURL, directory.pathComponents.count > 2 else { throw AIModelStoreError.unsafeDirectory }
        let manager = FileManager.default
        let owner = directory.appendingPathComponent(".container-gui-model-cache")
        if manager.fileExists(atPath: directory.path) {
            try Self.requireDirectory(directory)
            guard (try? Self.readSmallFile(owner)) == Data(catalog.identity.utf8) else {
                throw AIModelStoreError.unsafeDirectory
            }
        } else {
            try manager.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.ensureDirectory(directory)
            try Data(catalog.identity.utf8).write(to: owner, options: .withoutOverwriting)
        }
    }

    private struct FileStamp: Equatable, Sendable {
        let path: String
        let size: Int64
        let modified: Date
        let inode: UInt64
        let changedSeconds: Int64
        let changedNanoseconds: Int64
    }

    private static func stamps(in directory: URL, catalog: AIModelCatalog) throws -> [FileStamp] {
        try catalog.validate()
        try requireDirectory(directory)
        guard try readSmallFile(directory.appendingPathComponent(".container-gui-model-cache")) == Data(catalog.identity.utf8) else {
            throw AIModelStoreError.notInstalled
        }
        let payload = directory.appendingPathComponent("installed")
        try requireDirectory(payload)
        guard try readSmallFile(payload.appendingPathComponent(".ready")) == Data(catalog.identity.utf8) else {
            throw AIModelStoreError.notInstalled
        }
        return try payloadStamps(in: payload, catalog: catalog)
    }

    private static func payloadStamps(in payload: URL, catalog: AIModelCatalog) throws -> [FileStamp] {
        try validateTree(payload, catalog: catalog, requiresAllFiles: true)
        return try catalog.files.map { file in
            let url = payload.appendingPathComponent(file.path)
            try requireRegularFile(url)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber, size.int64Value == file.size,
                  let modified = attributes[.modificationDate] as? Date,
                  let inode = attributes[.systemFileNumber] as? NSNumber else { throw AIModelStoreError.verificationFailed }
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw AIModelStoreError.verificationFailed }
            return FileStamp(path: file.path, size: size.int64Value, modified: modified, inode: inode.uint64Value,
                             changedSeconds: Int64(info.st_ctimespec.tv_sec), changedNanoseconds: Int64(info.st_ctimespec.tv_nsec))
        }
    }

    private static func verify(_ file: AIModelFile, in directory: URL) throws {
        try requireDirectory(directory)
        var parent = directory
        for component in file.path.split(separator: "/").dropLast() {
            parent.appendPathComponent(String(component))
            try requireDirectory(parent)
        }
        let url = directory.appendingPathComponent(file.path)
        try requireRegularFile(url)
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw AIModelStoreError.verificationFailed }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_size == file.size,
              info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { throw AIModelStoreError.verificationFailed }
        var hash = SHA256()
        var count: Int64 = 0
        while true {
            try Task.checkCancellation()
            // Foundation's autoreleased read buffers otherwise accumulate on a
            // long-running async thread even though Swift releases each Data value.
            let readCount = try autoreleasepool {
                let bytes = try handle.read(upToCount: 1024 * 1024) ?? Data()
                count += Int64(bytes.count)
                guard count <= file.size else { throw AIModelStoreError.verificationFailed }
                hash.update(data: bytes)
                return bytes.count
            }
            if readCount == 0 { break }
        }
        guard count == file.size, hash.finalize().map({ String(format: "%02x", $0) }).joined() == file.sha256 else {
            throw AIModelStoreError.verificationFailed
        }
    }

    private static func validateTree(_ directory: URL, catalog: AIModelCatalog, requiresAllFiles: Bool) throws {
        try requireDirectory(directory)
        let paths = Set(catalog.files.map(\.path))
        var directories = Set<String>()
        for file in catalog.files {
            var parts = file.path.split(separator: "/").map(String.init)
            while parts.count > 1 { parts.removeLast(); directories.insert(parts.joined(separator: "/")) }
        }
        guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
            throw AIModelStoreError.unsafeDirectory
        }
        var found = Set<String>()
        for case let path as String in enumerator {
            let url = directory.appendingPathComponent(path)
            if directories.contains(path) {
                try requireDirectory(url)
            } else if paths.contains(path) || path == ".ready" {
                try requireRegularFile(url)
                found.insert(path)
            } else {
                throw AIModelStoreError.unsafeDirectory
            }
        }
        guard !requiresAllFiles || paths.isSubset(of: found) else { throw AIModelStoreError.notInstalled }
    }

    private static func requireDirectory(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw AIModelStoreError.unsafeDirectory }
    }

    private static func requireRegularFile(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.referenceCount] as? NSNumber)?.intValue == 1 else { throw AIModelStoreError.unsafeDirectory }
    }

    private static func readSmallFile(_ url: URL) throws -> Data {
        try requireRegularFile(url)
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw AIModelStoreError.unsafeDirectory }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: 129) ?? Data()
        guard bytes.count <= 128 else { throw AIModelStoreError.verificationFailed }
        return bytes
    }

    private static func ensureDirectory(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try requireDirectory(url)
        } else {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
    }

    private static func ensureParents(of path: String, in directory: URL) throws {
        var parent = directory
        for component in path.split(separator: "/").dropLast() {
            parent.appendPathComponent(String(component))
            try ensureDirectory(parent)
        }
    }
}

struct AIModelHTTPTransport: AIModelTransport {
    func download(from url: URL, to handle: FileHandle, expectedBytes: Int64,
                  progress: @escaping @Sendable (Int64) -> Void) async throws {
        guard AIModelCatalog.permitsDownloadURL(url) else { throw AIModelStoreError.downloadFailed }
        let receiver = ModelDownloadReceiver(handle: handle, expectedBytes: expectedBytes, progress: progress)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 3600
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: receiver, delegateQueue: queue)
        defer { session.invalidateAndCancel() }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                receiver.continuation = continuation
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
                request.setValue("ContainerGUI-ModelInstaller", forHTTPHeaderField: "User-Agent")
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                session.dataTask(with: request).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }
}

// Initialized before resume; all mutable download state then belongs to the serial delegate queue.
private final class ModelDownloadReceiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let handle: FileHandle
    let expectedBytes: Int64
    let progress: @Sendable (Int64) -> Void
    var continuation: CheckedContinuation<Void, Error>?
    private var received: Int64 = 0
    private var lastProgress: Int64 = 0
    private var failure: AIModelStoreError?
    private var redirects = 0

    init(handle: FileHandle, expectedBytes: Int64, progress: @escaping @Sendable (Int64) -> Void) {
        self.handle = handle
        self.expectedBytes = expectedBytes
        self.progress = progress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                          ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        redirects += 1
        guard redirects <= 5, let url = request.url, AIModelCatalog.permitsDownloadURL(url) else {
            failure = .downloadFailed
            completionHandler(nil)
            return
        }
        var sanitized = request
        sanitized.setValue(nil, forHTTPHeaderField: "Authorization")
        sanitized.setValue(nil, forHTTPHeaderField: "Cookie")
        completionHandler(sanitized)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let url = http.url, AIModelCatalog.permitsDownloadURL(url),
              response.expectedContentLength < 0 || response.expectedContentLength == expectedBytes else {
            failure = .downloadFailed
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil else { return }
        guard Int64(data.count) <= expectedBytes - received else {
            failure = .verificationFailed
            dataTask.cancel()
            return
        }
        do {
            try handle.write(contentsOf: data)
            received += Int64(data.count)
            if received - lastProgress >= 1024 * 1024 || received == expectedBytes {
                lastProgress = received
                progress(received)
            }
        } catch {
            failure = .downloadFailed
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let failure {
            continuation?.resume(throwing: failure)
        } else if (error as? URLError)?.code == .cancelled {
            continuation?.resume(throwing: CancellationError())
        } else if error != nil || received != expectedBytes {
            continuation?.resume(throwing: AIModelStoreError.downloadFailed)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}
