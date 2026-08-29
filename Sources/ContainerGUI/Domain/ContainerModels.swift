import Foundation

struct CLIInstallation: Codable, Equatable, Sendable {
    let versionText: String
    let semanticVersion: String?
    let compatibility: CLICompatibility
    let checkedAt: Date
}

enum SystemServiceState: String, Codable, Equatable, Sendable {
    case healthy
    case stopped
    case unregistered
    case degraded
    case unavailable
    case unknown
}

struct SystemHealth: Codable, Equatable, Sendable {
    let tool: CLIInstallation
    let serviceState: SystemServiceState
    let apiServerVersion: String?
    let apiServerBuild: String?
    let apiServerCommit: String?
    let diagnosticCode: String?
    let diagnosticMessage: String?
    let observedAt: Date
}

enum ContainerState: String, Codable, Equatable, Sendable {
    case running
    case stopped
    case created
    case stopping
    case error
    case unknown

    static func normalize(_ value: String?) -> ContainerState {
        switch value?.lowercased() {
        case "running": .running
        case "stopped", "exited": .stopped
        case "created": .created
        case "stopping": .stopping
        case "error", "failed": .error
        default: .unknown
        }
    }
}

struct ContainerSummary: Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let imageReference: String?
    let state: ContainerState
    let rawState: String?
    let ipv4Address: String?
    let ipv6Address: String?
    let createdAt: Date?
    let observedAt: Date
}

struct ContainerList: Codable, Equatable, Sendable {
    let items: [ContainerSummary]
    let observedAt: Date
}

struct ContainerDetail: Codable, Equatable, Sendable {
    let summary: ContainerSummary
    let configuration: JSONValue
    let status: JSONValue
    let raw: JSONValue
    let observedAt: Date
}

struct RecentLogs: Codable, Equatable, Sendable {
    let containerID: String
    let text: String
    let truncated: Bool
    let observedAt: Date

    enum CodingKeys: String, CodingKey {
        case text, truncated, observedAt
        case containerID = "containerId"
    }
}
