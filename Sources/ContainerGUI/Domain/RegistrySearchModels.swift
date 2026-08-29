import Foundation

enum RemoteRegistry: String, Codable, CaseIterable, Sendable {
    case dockerHub
}

struct RemoteRepositorySearchRequest: Equatable, Sendable {
    let registry: RemoteRegistry
    let query: String?
    let page: Int

    init(
        registry: RemoteRegistry,
        query: String? = nil,
        page: Int = 1
    ) {
        self.registry = registry
        self.query = query
        self.page = page
    }

    func validated() throws -> Self {
        var errors: [String: String] = [:]
        if !(1...500).contains(page) {
            errors["page"] = "页码必须在 1...500 之间"
        }

        let normalizedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isValidSearchQuery(normalizedQuery) {
            errors["query"] = "Docker Hub 搜索词必须为 1...128 个可见字符"
        }

        guard errors.isEmpty else {
            throw ProblemDetail(code: .validationFailed, fieldErrors: errors)
        }
        return Self(
            registry: registry,
            query: normalizedQuery,
            page: page
        )
    }
}

struct RemoteTagListRequest: Equatable, Sendable {
    let registry: RemoteRegistry
    let repository: String
    let page: Int

    init(
        registry: RemoteRegistry,
        repository: String,
        page: Int = 1
    ) {
        self.registry = registry
        self.repository = repository
        self.page = page
    }

    func validated() throws -> Self {
        var errors: [String: String] = [:]
        if !(1...500).contains(page) {
            errors["page"] = "页码必须在 1...500 之间"
        }
        let normalizedRepository = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isValidRepositoryPath(normalizedRepository)
            || normalizedRepository.split(separator: "/").count != 2 {
            errors["repository"] = "镜像仓库路径格式无效"
        }

        guard errors.isEmpty else {
            throw ProblemDetail(code: .validationFailed, fieldErrors: errors)
        }
        return Self(
            registry: registry,
            repository: normalizedRepository,
            page: page
        )
    }
}

struct RemoteRepositorySummary: Codable, Equatable, Sendable {
    let registry: RemoteRegistry
    let repository: String
    let reference: String
    let name: String
    let namespace: String
    let description: String?
    let isOfficial: Bool?
    let starCount: Int?
    let pullCount: Int?
    let updatedAt: Date?
}

struct RemoteTagSummary: Codable, Equatable, Sendable {
    let name: String
    let reference: String
    let digest: String?
    let sizeBytes: UInt64?
    let updatedAt: Date?
}

struct RemoteRepositoryPage: Codable, Equatable, Sendable {
    let items: [RemoteRepositorySummary]
    let page: Int
    let pageSize: Int
    let totalCount: Int?
    let hasNextPage: Bool
    let observedAt: Date
}

struct RemoteTagPage: Codable, Equatable, Sendable {
    let items: [RemoteTagSummary]
    let page: Int
    let pageSize: Int
    let totalCount: Int?
    let hasNextPage: Bool
    let observedAt: Date
}

private func isValidSearchQuery(_ value: String?) -> Bool {
    guard let value, (1...128).contains(value.count) else { return false }
    return !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
}

func isValidRepositoryPath(_ value: String) -> Bool {
    guard (1...255).contains(value.count), !value.hasPrefix("/"), !value.hasSuffix("/") else {
        return false
    }
    let components = value.split(separator: "/", omittingEmptySubsequences: false)
    return !components.isEmpty && components.allSatisfy { component in
        component != "." && component != ".." && component.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#,
            options: .regularExpression
        ) != nil
    }
}

func isValidRemoteTag(_ value: String) -> Bool {
    guard (1...256).contains(value.count) else { return false }
    return value.range(
        of: #"^[A-Za-z0-9_][A-Za-z0-9._-]*$"#,
        options: .regularExpression
    ) != nil
}
