import Foundation

/// The installed CLI version is read locally, never supplied by the browser.
actor ContainerReleaseChecker<Transport: RegistryHTTPTransport>: UpdateChecking {
    private let transport: Transport
    private let maximumResponseBytes: Int
    private let installedVersion: @Sendable () async throws -> String?
    private let now: @Sendable () -> Date
    private var cached: (summary: UpdateSummary, date: Date)?
    private var pending: (version: String, task: Task<UpdateSummary, Error>)?

    init(
        transport: Transport,
        maximumResponseBytes: Int,
        installedVersion: @escaping @Sendable () async throws -> String?,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.maximumResponseBytes = maximumResponseBytes
        self.installedVersion = installedVersion
        self.now = now
    }

    func checkForUpdates() async throws -> UpdateSummary {
        guard let version = try await installedVersion(), SemanticVersion(version) != nil else {
            throw ProblemDetail(code: .updateCheckUnavailable)
        }
        if let cached, cached.summary.currentVersion == version,
           (0..<300).contains(now().timeIntervalSince(cached.date)) {
            return cached.summary
        }
        if let pending {
            let result = try await pending.task.value
            if pending.version == version { return result }
            // A CLI upgrade happened during the request; compare again on the next check.
            throw ProblemDetail(code: .updateCheckUnavailable)
        }
        let checker = GitHubReleaseChecker(transport: transport, maximumResponseBytes: maximumResponseBytes,
                                          currentVersion: version, repository: .appleContainer)
        let task = Task { try await checker.checkForUpdates() }
        pending = (version, task)
        defer { pending = nil }
        let summary = try await task.value
        cached = (summary, now())
        return summary
    }
}
