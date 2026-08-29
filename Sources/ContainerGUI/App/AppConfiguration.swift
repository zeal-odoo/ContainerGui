import Foundation

enum AppConfigurationError: Error, Equatable, CustomStringConvertible {
    case invalidPort(String)
    case invalidCLIPath

    var description: String {
        switch self {
        case .invalidPort(let value):
            "CONTAINER_GUI_PORT 必须是 1024...65535，当前值：\(value)"
        case .invalidCLIPath:
            "CONTAINER_GUI_CLI_PATH 不能为空"
        }
    }
}

struct AppConfiguration: Sendable, Equatable {
    static let fixedHost = "127.0.0.1"
    static let defaultPort = 8787

    let port: Int
    let explicitCLIPath: String?

    let maximumRequestBodyBytes = 64 * 1024
    let maximumCommandOutputBytes = 16 * 1024 * 1024
    let queryTimeout: Duration = .seconds(5)
    let mutationTimeout: Duration = .seconds(30)
    let imagePullTimeout: Duration = .seconds(30 * 60)
    let gracefulStopTimeout: Duration = .seconds(10)
    let operationTTL: Duration = .seconds(15 * 60)
    let maximumConcurrentMutations = 4
    let maximumOperationRecords = 1_000
    let maximumLogSessions = 8
    let maximumRegistryResponseBytes = 2 * 1024 * 1024
    let registryTimeoutSeconds: TimeInterval = 5

    var host: String { Self.fixedHost }
    var origin: String { "http://\(host):\(port)" }

    init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        let rawPort = environment["CONTAINER_GUI_PORT"] ?? String(Self.defaultPort)
        guard let port = Int(rawPort), (1024...65535).contains(port) else {
            throw AppConfigurationError.invalidPort(rawPort)
        }

        let rawPath = environment["CONTAINER_GUI_CLI_PATH"]
        if let rawPath, rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AppConfigurationError.invalidCLIPath
        }

        self.port = port
        self.explicitCLIPath = rawPath
    }
}
