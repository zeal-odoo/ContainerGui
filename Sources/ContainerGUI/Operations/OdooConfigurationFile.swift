import CryptoKit
import Darwin
import Foundation

enum OdooConfigurationFile {
    static let maximumBytes = 128 * 1024

    static func read(_ url: URL) throws -> OdooDatabaseEndpoint {
        try withDirectory(url) { directory, name in
            let (data, _) = try contents(directory: directory, name: name)
            return try Document(data).endpoint
        }
    }

    static func write(_ url: URL, request: OdooDatabaseSaveRequest) throws {
        let request = try request.validated(for: request.confirmationTarget)
        try withDirectory(url) { directory, name in
            let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard descriptor >= 0 else { throw OdooConfigurationError.unavailable }
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw OdooConfigurationError.unavailable }
            let (original, attributes) = try contents(descriptor: descriptor)
            guard attributes.st_mode & 0o200 != 0 else { throw OdooConfigurationError.unavailable }
            let document = try Document(original)
            guard document.endpoint.revision == request.expectedRevision else { throw OdooConfigurationError.stale }
            let replacement = try document.replacing(host: request.host, port: request.port)
            let token = UUID().uuidString
            let backup = ".\(name).container-gui-\(token).bak"
            let temporary = ".\(name).container-gui-\(token).tmp"
            try create(directory: directory, name: backup, data: original, mode: 0o600)
            defer { unlinkat(directory, temporary, 0) }
            try create(directory: directory, name: temporary, data: replacement, mode: attributes.st_mode & 0o777, owner: attributes)
            let (latest, latestAttributes) = try contents(directory: directory, name: name)
            guard latest == original, latestAttributes.st_ino == attributes.st_ino,
                  latestAttributes.st_dev == attributes.st_dev,
                  latestAttributes.st_mode == attributes.st_mode,
                  latestAttributes.st_gid == attributes.st_gid else { throw OdooConfigurationError.stale }
            guard renameat(directory, temporary, directory, name) == 0 else { throw OdooConfigurationError.unavailable }
            _ = fsync(directory)
            let observed = try Document(contents(directory: directory, name: name).0).endpoint
            guard observed.host == request.host, observed.port == request.port else { throw OdooConfigurationError.invalid }
        }
    }

    private static func withDirectory<T>(_ url: URL, body: (Int32, String) throws -> T) throws -> T {
        guard url.isFileURL, url.path.hasPrefix("/"), url.lastPathComponent != ".", url.lastPathComponent != ".." else {
            throw OdooConfigurationError.unavailable
        }
        let directory = open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw OdooConfigurationError.unavailable }
        defer { close(directory) }
        var attributes = stat()
        guard fstat(directory, &attributes) == 0, attributes.st_uid == geteuid(),
              attributes.st_mode & 0o022 == 0 else { throw OdooConfigurationError.unavailable }
        return try body(directory, url.lastPathComponent)
    }

    private static func contents(directory: Int32, name: String) throws -> (Data, stat) {
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw OdooConfigurationError.unavailable }
        defer { close(descriptor) }
        return try contents(descriptor: descriptor)
    }

    private static func contents(descriptor: Int32) throws -> (Data, stat) {
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0,
              attributes.st_mode & S_IFMT == S_IFREG, attributes.st_nlink == 1,
              attributes.st_uid == geteuid(), attributes.st_size <= maximumBytes,
              attributes.st_size >= 0, attributes.st_mode & 0o200 != 0,
              attributes.st_mode & 0o7022 == 0 else { throw OdooConfigurationError.unavailable }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else { throw OdooConfigurationError.unavailable }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= maximumBytes else { throw OdooConfigurationError.unavailable }
        }
        return (data, attributes)
    }

    private static func create(directory: Int32, name: String, data: Data, mode: mode_t, owner: stat? = nil) throws {
        let descriptor = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw OdooConfigurationError.unavailable }
        defer { close(descriptor) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                guard count > 0 else { throw OdooConfigurationError.unavailable }
                offset += count
            }
        }
        if let owner, fchown(descriptor, owner.st_uid, owner.st_gid) != 0 { throw OdooConfigurationError.unavailable }
        guard fchmod(descriptor, mode) == 0, fsync(descriptor) == 0 else { throw OdooConfigurationError.unavailable }
    }

    private struct Document {
        let lines: [String]
        let indices: [String: Int]
        let sectionEnd: Int
        let newline: String
        let endpoint: OdooDatabaseEndpoint

        init(_ data: Data) throws {
            guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
                throw OdooConfigurationError.invalid
            }
            lines = text.components(separatedBy: "\n")
            newline = text.contains("\r\n") ? "\r" : ""
            var options = false
            var found = false
            var end = lines.count - (lines.last == "" ? 1 : 0)
            var keys: [String: Int] = [:]
            var values: [String: String] = [:]
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") { continue }
                if trimmed.hasPrefix("[") {
                    if options { end = index }
                    options = trimmed.lowercased() == "[options]"
                    if options {
                        guard !found else { throw OdooConfigurationError.invalid }
                        found = true
                    }
                    continue
                }
                guard options else { continue }
                guard let separator = line.firstIndex(of: "=") else { throw OdooConfigurationError.invalid }
                let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
                guard !key.isEmpty, keys[key] == nil else { throw OdooConfigurationError.invalid }
                keys[key] = index
                values[key] = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard found else { throw OdooConfigurationError.invalid }
            let host = values["db_host"] ?? ""
            guard host.isEmpty || host == "False" || OdooDatabaseSaveRequest.isValidHost(host) else { throw OdooConfigurationError.invalid }
            guard let port = Int(values["db_port"] ?? "5432"), (1...65535).contains(port) else { throw OdooConfigurationError.invalid }
            endpoint = .init(host: host == "False" ? "" : host, port: port, revision: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            indices = keys
            sectionEnd = end
        }

        func replacing(host: String, port: Int) throws -> Data {
            var updated = lines
            var additions: [String] = []
            for (key, value) in [("db_host", host), ("db_port", String(port))] {
                if let index = indices[key], let separator = updated[index].firstIndex(of: "=") {
                    let prefix = updated[index][...separator]
                    let spacing = updated[index][updated[index].index(after: separator)...].prefix { $0 == " " || $0 == "\t" }
                    updated[index] = "\(prefix)\(spacing)\(value)\(updated[index].hasSuffix("\r") ? "\r" : "")"
                } else {
                    additions.append("\(key) = \(value)\(newline)")
                }
            }
            updated.insert(contentsOf: additions, at: sectionEnd)
            let result = Data(updated.joined(separator: "\n").utf8)
            guard result.count <= maximumBytes else { throw OdooConfigurationError.invalid }
            return result
        }
    }
}
