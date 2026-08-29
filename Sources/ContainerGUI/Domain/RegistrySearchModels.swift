import Foundation

enum RemoteRegistry: String, Codable, CaseIterable, Sendable {
    case dockerHub
    case ghcr
}

enum GHCRNamespaceType: String, Codable, CaseIterable, Sendable {
    case user
    case organization
}

struct RemoteRepositorySearchRequest: Equatable, Sendable {
    let registry: RemoteRegistry
    let query: String?
    let ownerType: GHCRNamespaceType?
    let owner: String?
    let page: Int

    init(
        registry: RemoteRegistry,
        query: String? = nil,
        ownerType: GHCRNamespaceType? = nil,
        owner: String? = nil,
        page: Int = 1
    ) {
        self.registry = registry
        self.query = query
        self.ownerType = ownerType
        self.owner = owner
        self.page = page
    }

    func validated() throws -> Self {
        var errors: [String: String] = [:]
        if !(1...500).contains(page) {
            errors["page"] = "页码必须在 1...500 之间"
        }

        let normalizedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOwner = owner?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch registry {
        case .dockerHub:
            if !isValidSearchQuery(normalizedQuery) {
                errors["query"] = "Docker Hub 搜索词必须为 1...128 个可见字符"
            }
        case .ghcr:
            if ownerType == nil {
                errors["ownerType"] = "GHCR 必须选择用户或组织"
            }
            if !isValidGitHubOwner(normalizedOwner) {
                errors["owner"] = "GitHub 用户或组织名称格式无效"
            }
        }

        guard errors.isEmpty else {
            throw ProblemDetail(code: .validationFailed, fieldErrors: errors)
        }
        return Self(
            registry: registry,
            query: normalizedQuery,
            ownerType: ownerType,
            owner: normalizedOwner,
            page: page
        )
    }
}

struct RemoteTagListRequest: Equatable, Sendable {
    let registry: RemoteRegistry
    let repository: String
    let ownerType: GHCRNamespaceType?
    let owner: String?
    let page: Int

    init(
        registry: RemoteRegistry,
        repository: String,
        ownerType: GHCRNamespaceType? = nil,
        owner: String? = nil,
        page: Int = 1
    ) {
        self.registry = registry
        self.repository = repository
        self.ownerType = ownerType
        self.owner = owner
        self.page = page
    }

    func validated() throws -> Self {
        var errors: [String: String] = [:]
        if !(1...500).contains(page) {
            errors["page"] = "页码必须在 1...500 之间"
        }
        let normalizedRepository = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isValidRepositoryPath(normalizedRepository)
            || (registry == .dockerHub && normalizedRepository.split(separator: "/").count != 2) {
            errors["repository"] = "镜像仓库路径格式无效"
        }

        let normalizedOwner = owner?.trimmingCharacters(in: .whitespacesAndNewlines)
        if registry == .ghcr {
            if ownerType == nil {
                errors["ownerType"] = "GHCR 必须选择用户或组织"
            }
            if !isValidGitHubOwner(normalizedOwner) {
                errors["owner"] = "GitHub 用户或组织名称格式无效"
            }
        }

        guard errors.isEmpty else {
            throw ProblemDetail(code: .validationFailed, fieldErrors: errors)
        }
        return Self(
            registry: registry,
            repository: normalizedRepository,
            ownerType: ownerType,
            owner: normalizedOwner,
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

private func isValidGitHubOwner(_ value: String?) -> Bool {
    guard let value, (1...39).contains(value.count), !value.contains("--") else { return false }
    return value.range(
        of: #"^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$"#,
        options: .regularExpression
    ) != nil
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
