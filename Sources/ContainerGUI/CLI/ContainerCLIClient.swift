import Foundation

private actor CLIInstallationCache {
    private var cached: CLIInstallation?
    private var inFlight: Task<CLIInstallation, Error>?

    func value(
        probe: @escaping @Sendable () async throws -> CLIInstallation
    ) async throws -> CLIInstallation {
        if let cached { return cached }
        if let inFlight { return try await inFlight.value }

        let task = Task { try await probe() }
        inFlight = task
        do {
            let installation = try await task.value
            cached = installation
            inFlight = nil
            return installation
        } catch {
            inFlight = nil
            throw error
        }
    }

    func invalidate() {
        cached = nil
    }
}

protocol ContainerReading: Sendable {
    func systemHealth() async throws -> SystemHealth
    func listContainers() async throws -> ContainerList
    func containerDetail(id: String) async throws -> ContainerDetail
}

protocol ContainerControlling: Sendable {
    func listContainers() async throws -> ContainerList
    func startContainer(id: String) async throws -> ContainerControlOutcome
    func stopContainer(id: String) async throws -> ContainerControlOutcome
}

protocol ContainerLogReading: Sendable {
    func recentLogs(id: String, tail: Int) async throws -> RecentLogs
    func followLogs(id: String, tail: Int) async throws -> AsyncThrowingStream<CommandStreamEvent, Error>
}

final class ContainerCLIClient: ContainerReading, ContainerControlling, ContainerLogReading, @unchecked Sendable {
    private let executor: any CommandExecuting
    private let executableURL: URL?
    private let unavailableCompatibility: CLICompatibility
    private let queryTimeout: Duration
    private let mutationTimeout: Duration
    private let maximumOutputBytes: Int
    private let installationCache = CLIInstallationCache()

    init(
        executor: any CommandExecuting,
        executableURL: URL?,
        unavailableCompatibility: CLICompatibility = .missing,
        queryTimeout: Duration = .seconds(5),
        mutationTimeout: Duration = .seconds(30),
        maximumOutputBytes: Int = 16 * 1024 * 1024
    ) {
        self.executor = executor
        self.executableURL = executableURL
        self.unavailableCompatibility = unavailableCompatibility
        self.queryTimeout = queryTimeout
        self.mutationTimeout = mutationTimeout
        self.maximumOutputBytes = maximumOutputBytes
    }

    func installation(now: Date = Date()) async throws -> CLIInstallation {
        try await installationCache.value { [self] in
            try await probeInstallation(now: now)
        }
    }

    private func probeInstallation(now: Date) async throws -> CLIInstallation {
        guard executableURL != nil else {
            return CLIInstallation(
                versionText: "",
                semanticVersion: nil,
                compatibility: unavailableCompatibility,
                checkedAt: now
            )
        }
        let result = try await execute(["--version"])
        guard result.exitCode == 0 else {
            return CLIInstallation(
                versionText: "",
                semanticVersion: nil,
                compatibility: .unrecognized,
                checkedAt: now
            )
        }
        let versionText = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        let classification = CLIVersionResolver.classify(versionText: versionText)
        return CLIInstallation(
            versionText: String(versionText.prefix(1024)),
            semanticVersion: classification.semanticVersion?.description,
            compatibility: classification.compatibility,
            checkedAt: now
        )
    }

    func systemHealth() async throws -> SystemHealth {
        let observedAt = Date()
        let tool = try await installation(now: observedAt)
        guard tool.compatibility == .supported else {
            return SystemHealth(
                tool: tool,
                serviceState: .unavailable,
                apiServerVersion: nil,
                apiServerBuild: nil,
                apiServerCommit: nil,
                diagnosticCode: compatibilityProblem(tool.compatibility).code.rawValue,
                diagnosticMessage: compatibilityProblem(tool.compatibility).message,
                observedAt: observedAt
            )
        }
        let result: CommandResult
        do {
            result = try await execute(["system", "status", "--format", "json"])
        } catch {
            await installationCache.invalidate()
            throw error
        }
        guard result.exitCode == 0 else {
            return SystemHealth(
                tool: tool,
                serviceState: .unavailable,
                apiServerVersion: nil,
                apiServerBuild: nil,
                apiServerCommit: nil,
                diagnosticCode: ProblemCode.cliExitNonzero.rawValue,
                diagnosticMessage: ProblemCode.cliExitNonzero.safeMessage,
                observedAt: observedAt
            )
        }
        return try CLIOutputParser.parseSystemHealth(
            data: result.stdout,
            installation: tool,
            observedAt: observedAt
        )
    }

    func listContainers() async throws -> ContainerList {
        try await requireSupportedInstallation()
        let result = try await execute(["list", "--all", "--format", "json"])
        guard result.exitCode == 0 else { throw ContainerCLIError.nonZeroExit(result.exitCode) }
        return try CLIOutputParser.parseContainerList(data: result.stdout)
    }

    func containerDetail(id: String) async throws -> ContainerDetail {
        guard !id.isEmpty, !id.hasPrefix("-") else { throw ContainerCLIError.invalidIdentifier }
        let current = try await listContainers()
        guard current.items.contains(where: { $0.id == id }) else {
            throw ContainerCLIError.targetNotFound
        }
        let result = try await execute(["inspect", id])
        guard result.exitCode == 0 else { throw ContainerCLIError.nonZeroExit(result.exitCode) }
        return try CLIOutputParser.parseContainerDetail(data: result.stdout, expectedID: id)
    }

    func startContainer(id: String) async throws -> ContainerControlOutcome {
        let current = try await requireContainer(id: id)
        guard current.state == .stopped || current.state == .created else {
            throw ProblemDetail(code: .stateConflict)
        }
        let result = try await execute(["start", id], timeout: mutationTimeout)
        guard result.exitCode == 0 else { throw ContainerCLIError.nonZeroExit(result.exitCode) }
        let observed = try await requireContainer(id: id)
        return ContainerControlOutcome(
            exitCode: result.exitCode,
            observedContainer: observed,
            matchedExpectation: observed.state == .running
        )
    }

    func stopContainer(id: String) async throws -> ContainerControlOutcome {
        let current = try await requireContainer(id: id)
        guard current.state == .running else { throw ProblemDetail(code: .stateConflict) }
        let result = try await execute(["stop", "--time", "10", id], timeout: mutationTimeout)
        guard result.exitCode == 0 else { throw ContainerCLIError.nonZeroExit(result.exitCode) }
        let observed = try await requireContainer(id: id)
        return ContainerControlOutcome(
            exitCode: result.exitCode,
            observedContainer: observed,
            matchedExpectation: observed.state == .stopped
        )
    }

    func recentLogs(id: String, tail: Int) async throws -> RecentLogs {
        try validateTail(tail)
        _ = try await requireContainer(id: id)
        let result = try await execute(["logs", "-n", String(tail), id])
        guard result.exitCode == 0 else { throw ContainerCLIError.nonZeroExit(result.exitCode) }
        return RecentLogs(
            containerID: id,
            text: result.stdoutString,
            truncated: false,
            observedAt: Date()
        )
    }

    func followLogs(id: String, tail: Int) async throws -> AsyncThrowingStream<CommandStreamEvent, Error> {
        try validateTail(tail)
        _ = try await requireContainer(id: id)
        guard let executableURL else { throw ContainerCLIError.unavailable(unavailableCompatibility) }
        return executor.stream(
            CommandRequest(
                executableURL: executableURL,
                arguments: ["logs", "--follow", "-n", String(tail), id],
                timeout: .seconds(86_400),
                maximumOutputBytes: maximumOutputBytes
            )
        )
    }

    private func requireSupportedInstallation() async throws {
        let tool = try await installation()
        guard tool.compatibility == .supported else {
            throw ContainerCLIError.unavailable(tool.compatibility)
        }
    }

    private func execute(_ arguments: [String], timeout: Duration? = nil) async throws -> CommandResult {
        guard let executableURL else {
            throw ContainerCLIError.unavailable(unavailableCompatibility)
        }
        return try await executor.run(
            CommandRequest(
                executableURL: executableURL,
                arguments: arguments,
                timeout: timeout ?? queryTimeout,
                maximumOutputBytes: maximumOutputBytes
            )
        )
    }

    private func requireContainer(id: String) async throws -> ContainerSummary {
        guard !id.isEmpty, !id.hasPrefix("-") else { throw ContainerCLIError.invalidIdentifier }
        let list = try await listContainers()
        guard let summary = list.items.first(where: { $0.id == id }) else {
            throw ContainerCLIError.targetNotFound
        }
        return summary
    }

    private func validateTail(_ tail: Int) throws {
        guard (0...10_000).contains(tail) else {
            throw ProblemDetail(code: .validationFailed, fieldErrors: ["tail": "必须在 0...10000 之间"])
        }
    }

    private func compatibilityProblem(_ compatibility: CLICompatibility) -> ProblemDetail {
        switch compatibility {
        case .missing: ProblemDetail(code: .cliNotFound)
        case .notExecutable: ProblemDetail(code: .cliNotExecutable)
        case .unsupported, .unrecognized: ProblemDetail(code: .cliVersionUnsupported)
        case .supported: ProblemDetail(code: .internalError)
        }
    }
}
