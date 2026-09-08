import Darwin
import Foundation

struct AILogHistoryRecord: Codable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let containerId: String
    let createdAt: Date
    let model: String
    let modelRevision: String
    let language: String
    let appVersion: String
    let result: AILogResult

    init(id: UUID = UUID(), containerId: String, language: String, createdAt: Date = Date(), result: AILogResult) {
        self.schemaVersion = 1
        self.id = id
        self.containerId = containerId
        self.createdAt = Date(timeIntervalSince1970: floor(createdAt.timeIntervalSince1970))
        self.model = AIModelCatalog.qwen3.name
        self.modelRevision = AIModelCatalog.qwen3.revision
        self.language = language
        self.appVersion = AppVersion.current
        self.result = AILogResult(text: AILogEvidence.prepare(result.text), evidence: AILogEvidence.prepare(result.evidence),
                                  observedAt: result.observedAt, inputTokens: result.inputTokens,
                                  outputTokens: result.outputTokens, elapsedSeconds: result.elapsedSeconds)
    }

    fileprivate var valid: Bool {
        schemaVersion == 1 && AILogHistoryStore.validContainerID(containerId) && ["zh", "en"].contains(language)
            && createdAt.timeIntervalSince1970.isFinite && (0...4_102_444_800).contains(createdAt.timeIntervalSince1970)
            && result.observedAt.timeIntervalSince1970.isFinite
            && !result.text.isEmpty && !result.evidence.isEmpty
            && result.text.utf8.count <= 6_144 && result.evidence.utf8.count <= 6_144
            && result.text == AILogEvidence.prepare(result.text) && result.evidence == AILogEvidence.prepare(result.evidence)
            && (0...1_000_000).contains(result.inputTokens) && (0...1_000_000).contains(result.outputTokens)
            && result.elapsedSeconds.isFinite && (0...3_600).contains(result.elapsedSeconds)
            && !model.isEmpty && model.utf8.count <= 300 && modelRevision.utf8.count <= 128 && appVersion.utf8.count <= 32
    }

    fileprivate var filename: String {
        String(format: "%020lld", Int64(createdAt.timeIntervalSince1970)) + "-" + id.uuidString + ".json"
    }
}

struct AILogHistoryPage: Codable, Sendable {
    let items: [AILogHistoryRecord]
    let page: Int
    let pageSize: Int
    let total: Int
    let retentionLimit: Int
}

actor AILogHistoryStore {
    static let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/ContainerGUI/AILogHistory")
    static let retentionLimit = 1_000
    private static let maximumFileBytes = 96 * 1_024
    private let directory: URL

    init(directory: URL = AILogHistoryStore.defaultDirectory) { self.directory = directory }

    static func validContainerID(_ value: String) -> Bool {
        value.utf8.count <= 256 && value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$"#, options: .regularExpression) != nil
    }

    func append(_ record: AILogHistoryRecord) throws {
        guard record.valid else { throw Self.unavailable }
        guard let descriptor = try openDirectory(create: true) else { throw Self.unavailable }
        defer { close(descriptor) }
        let names = try recordNames(in: descriptor)
        let filename = record.filename
        guard !names.contains(filename) else { throw Self.unavailable }
        let data = try JSONEncoder.containerGUI.encode(record)
        guard data.count <= Self.maximumFileBytes else { throw Self.unavailable }
        let temporary = UUID().uuidString + ".tmp"
        let file = openat(descriptor, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw Self.unavailable }
        let handle = FileHandle(fileDescriptor: file, closeOnDealloc: true)
        defer { try? handle.close(); unlinkat(descriptor, temporary, 0) }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        guard renameat(descriptor, temporary, descriptor, filename) == 0 else { throw Self.unavailable }
        // Only known, valid records in this private directory can be pruned.
        let ordered = (names + [filename]).sorted(by: >)
        for old in ordered.dropFirst(Self.retentionLimit) {
            _ = try read(old, in: descriptor)
            guard unlinkat(descriptor, old, 0) == 0 else { throw Self.unavailable }
        }
        guard fsync(descriptor) == 0 else { throw Self.unavailable }
    }

    func list(containerID: String?, page: Int) throws -> AILogHistoryPage {
        guard (1...100).contains(page), containerID.map(Self.validContainerID) ?? true else {
            throw ProblemDetail(code: .validationFailed)
        }
        guard let descriptor = try openDirectory(create: false) else {
            return AILogHistoryPage(items: [], page: 1, pageSize: 10, total: 0, retentionLimit: Self.retentionLimit)
        }
        defer { close(descriptor) }
        let records = try recordNames(in: descriptor).sorted(by: >).map { try read($0, in: descriptor) }
            .filter { containerID == nil || $0.containerId == containerID }
        let currentPage = min(page, max(1, (records.count + 9) / 10))
        let items = Array(records.dropFirst((currentPage - 1) * 10).prefix(10))
        return AILogHistoryPage(items: items, page: currentPage, pageSize: 10, total: records.count, retentionLimit: Self.retentionLimit)
    }

    func delete(id: UUID) throws {
        guard let descriptor = try openDirectory(create: false) else { throw Self.notFound }
        defer { close(descriptor) }
        guard let name = try recordNames(in: descriptor).first(where: { $0.hasSuffix("-\(id.uuidString).json") }) else {
            throw Self.notFound
        }
        _ = try read(name, in: descriptor)
        guard unlinkat(descriptor, name, 0) == 0, fsync(descriptor) == 0 else { throw Self.unavailable }
    }

    // Traverse by directory descriptors: O_NOFOLLOW on only the last path component
    // would still allow a replaced/symlinked parent to escape the private directory.
    private func openDirectory(create: Bool) throws -> Int32? {
        guard directory.isFileURL, directory.pathComponents.count > 2,
              !directory.pathComponents.contains("..") else { throw Self.unavailable }
        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw Self.unavailable }
        var transferred = false
        defer { if !transferred { close(descriptor) } }
        for component in directory.pathComponents.dropFirst() {
            var child = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if child < 0, errno == ENOENT {
                guard create else { return nil }
                guard mkdirat(descriptor, component, 0o700) == 0 || errno == EEXIST else { throw Self.unavailable }
                child = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            guard child >= 0 else { throw Self.unavailable }
            close(descriptor)
            descriptor = child
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == geteuid(), info.st_mode & 0o077 == 0,
              flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw Self.unavailable }
        transferred = true
        return descriptor
    }

    private func recordNames(in descriptor: Int32) throws -> [String] {
        let duplicate = dup(descriptor)
        guard duplicate >= 0 else { throw Self.unavailable }
        guard let stream = fdopendir(duplicate) else { close(duplicate); throw Self.unavailable }
        defer { closedir(stream) }
        var names: [String] = []
        var count = 0
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                guard errno == 0 else { throw Self.unavailable }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            count += 1
            guard count <= 2_048 else { throw Self.unavailable }
            if name == "." || name == ".." || name == ".DS_Store" { continue }
            if name.hasSuffix(".tmp"), UUID(uuidString: String(name.dropLast(4))) != nil { continue }
            guard name.utf8.count == 62, name.range(of: #"^[0-9]{20}-[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\.json$"#, options: .regularExpression) != nil else {
                throw Self.unavailable
            }
            names.append(name)
        }
        return names
    }

    private func read(_ name: String, in descriptor: Int32) throws -> AILogHistoryRecord {
        let file = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { throw Self.unavailable }
        let handle = FileHandle(fileDescriptor: file, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              info.st_uid == geteuid(), info.st_mode & 0o077 == 0, info.st_size > 0,
              info.st_size <= Self.maximumFileBytes,
              let data = try handle.read(upToCount: Self.maximumFileBytes + 1), data.count == info.st_size,
              let record = try? JSONDecoder.containerGUI.decode(AILogHistoryRecord.self, from: data),
              record.valid, record.filename == name else { throw Self.unavailable }
        return record
    }

    private static var unavailable: ProblemDetail { ProblemDetail(code: .serviceUnavailable, message: "history_unavailable") }
    private static var notFound: ProblemDetail { ProblemDetail(code: .targetNotFound, message: "history_not_found") }
}
