import Darwin
import Foundation

struct OdooDatabaseEndpoint: Codable, Equatable, Sendable {
    let host: String
    let port: Int
    let revision: String
}

struct OdooDatabaseView: Codable, Equatable, Sendable {
    let containerId: String
    let isOdoo: Bool
    let editable: Bool
    var storage: String? = nil
    var endpoint: OdooDatabaseEndpoint? = nil
    var restriction: String? = nil
    let observedAt: Date

    var host: String? { endpoint?.host }
    var port: Int? { endpoint?.port }
    var revision: String? { endpoint?.revision }

    enum CodingKeys: String, CodingKey {
        case containerId, isOdoo, editable, storage, host, port, revision, restriction, observedAt
    }

    init(containerId: String, isOdoo: Bool, editable: Bool, storage: String? = nil, endpoint: OdooDatabaseEndpoint? = nil, restriction: String? = nil, observedAt: Date = Date()) {
        self.containerId = containerId
        self.isOdoo = isOdoo
        self.editable = editable
        self.storage = storage
        self.endpoint = endpoint
        self.restriction = restriction
        self.observedAt = observedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        containerId = try values.decode(String.self, forKey: .containerId)
        isOdoo = try values.decode(Bool.self, forKey: .isOdoo)
        editable = try values.decode(Bool.self, forKey: .editable)
        storage = try values.decodeIfPresent(String.self, forKey: .storage)
        restriction = try values.decodeIfPresent(String.self, forKey: .restriction)
        observedAt = try values.decode(Date.self, forKey: .observedAt)
        if let host = try values.decodeIfPresent(String.self, forKey: .host),
           let port = try values.decodeIfPresent(Int.self, forKey: .port),
           let revision = try values.decodeIfPresent(String.self, forKey: .revision) {
            endpoint = .init(host: host, port: port, revision: revision)
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(containerId, forKey: .containerId)
        try values.encode(isOdoo, forKey: .isOdoo)
        try values.encode(editable, forKey: .editable)
        try values.encodeIfPresent(storage, forKey: .storage)
        try values.encodeIfPresent(host, forKey: .host)
        try values.encodeIfPresent(port, forKey: .port)
        try values.encodeIfPresent(revision, forKey: .revision)
        try values.encodeIfPresent(restriction, forKey: .restriction)
        try values.encode(observedAt, forKey: .observedAt)
    }
}

struct OdooDatabaseSaveRequest: Codable, Sendable {
    let host: String
    let port: Int
    let confirmationTarget: String
    let expectedRevision: String

    func validated(for id: String) throws -> Self {
        guard confirmationTarget == id else { throw ProblemDetail(code: .confirmationMismatch) }
        let normalized = host.trimmingCharacters(in: .whitespaces)
        var errors: [String: String] = [:]
        if !Self.isValidHost(normalized) { errors["host"] = "请输入有效的数据库地址或主机名。" }
        if !(1...65535).contains(port) { errors["port"] = "数据库端口必须在 1...65535 之间。" }
        if expectedRevision.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) == nil {
            errors["expectedRevision"] = "请重新读取数据库配置后再保存。"
        }
        guard errors.isEmpty else { throw ProblemDetail(code: .validationFailed, fieldErrors: errors) }
        return Self(host: normalized, port: port, confirmationTarget: confirmationTarget, expectedRevision: expectedRevision)
    }

    static func isValidHost(_ host: String) -> Bool {
        guard (1...255).contains(host.utf8.count) else { return false }
        if host.contains(":") {
            var address = in6_addr()
            return host.withCString { inet_pton(AF_INET6, $0, &address) } == 1
        }
        if host.allSatisfy({ $0.isNumber || $0 == "." }) {
            var address = in_addr()
            return host.withCString { inet_pton(AF_INET, $0, &address) } == 1
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            (1...63).contains(label.count)
                && label.range(of: #"^[A-Za-z0-9](?:[A-Za-z0-9_-]*[A-Za-z0-9])?$"#, options: .regularExpression) != nil
        }
    }
}

enum OdooConfigurationError: Error {
    case unavailable
    case invalid
    case stale

    var problem: ProblemDetail {
        switch self {
        case .stale: ProblemDetail(code: .stateConflict, message: "配置已改变，请重新读取后再保存。")
        case .unavailable: ProblemDetail(code: .stateConflict, message: "配置文件不可安全编辑，请检查位置、权限和容器状态。")
        case .invalid: ProblemDetail(code: .stateConflict, message: "配置格式不受支持，无法安全编辑数据库地址。")
        }
    }
}
