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

protocol ContainerMetricsReading: Sendable {
    func containerMetrics() async throws -> ContainerMetricsSnapshot
}

protocol ImageReading: Sendable {
    func listImages() async throws -> ImageList
    func inspectImage(reference: String) async throws -> ImageSummary
}

protocol ResourceMutating: Sendable {
    func pullImage(
        _ request: ImagePullRequest,
        progress: @escaping @Sendable (ImagePullProgress) async -> Void
    ) async throws -> ImagePullOutcome
    func deleteImage(reference: String) async throws -> ImageDeleteOutcome
    func createContainer(_ request: ContainerCreateRequest) async throws -> ContainerCreateOutcome
}

extension ResourceMutating {
    func pullImage(_ request: ImagePullRequest) async throws -> ImagePullOutcome {
        try await pullImage(request, progress: { _ in })
    }
}

protocol ContainerControlling: Sendable {
    func listContainers() async throws -> ContainerList
    func startContainer(id: String) async throws -> ContainerControlOutcome
    func stopContainer(id: String) async throws -> ContainerControlOutcome
    func deleteContainer(id: String) async throws -> ContainerDeleteOutcome
}

protocol ContainerLogReading: Sendable {
    func recentLogs(id: String, tail: Int) async throws -> RecentLogs
    func followLogs(id: String, tail: Int) async throws -> AsyncThrowingStream<CommandStreamEvent, Error>
}

final class ContainerCLIClient: ContainerReading, ContainerMetricsReading, ContainerControlling, ContainerLogReading, ImageReading, ResourceMutating, @unchecked Sendable {
    private let executor: any CommandExecuting
    private let executableURL: URL?
    private let unavailableCompatibility: CLICompatibility
    private let queryTimeout: Duration
    private let mutationTimeout: Duration
    private let imagePullTimeout: Duration
    private let maximumOutputBytes: Int
    private let installationCache = CLIInstallationCache()
    private let metricsSampler = ContainerMetricsSampler()

    init(
        executor: any CommandExecuting,
        executableURL: URL?,
        unavailableCompatibility: CLICompatibility = .missing,
        queryTimeout: Duration = .seconds(5),
        mutationTimeout: Duration = .seconds(30),
        imagePullTimeout: Duration = .seconds(30 * 60),
        maximumOutputBytes: Int = 16 * 1024 * 1024
    ) {
        self.executor = executor
        self.executableURL = executableURL
        self.unavailableCompatibility = unavailableCompatibility
        self.queryTimeout = queryTimeout
        self.mutationTimeout = mutationTimeout
        self.imagePullTimeout = imagePullTimeout
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

    func containerMetrics() async throws -> ContainerMetricsSnapshot {
        try await metricsSampler.snapshot { [self] in
            try await requireSupportedInstallation()
            let result = try await execute(["stats", "--no-stream", "--format", "json"])
            guard result.exitCode == 0 else { throw ContainerCLIError.nonZeroExit(result.exitCode) }
            return try CLIOutputParser.parseContainerResourceSamples(data: result.stdout)
        }
    }

    func listImages() async throws -> ImageList {
        try await requireSupportedInstallation()
        let result = try await execute(["image", "list", "--format", "json"])
        guard result.exitCode == 0 else { throw ContainerCLIError.nonZeroExit(result.exitCode) }
        return try CLIOutputParser.parseImageList(data: result.stdout)
    }

    func inspectImage(reference: String) async throws -> ImageSummary {
        _ = try ImagePullRequest(reference: reference).validated()
        try await requireSupportedInstallation()
        let result = try await execute(["image", "inspect", reference])
        guard result.exitCode == 0 else { throw ContainerCLIError.nonZeroExit(result.exitCode) }
        return try CLIOutputParser.parseImageInspect(data: result.stdout)
    }

    func pullImage(
        _ request: ImagePullRequest,
        progress: @escaping @Sendable (ImagePullProgress) async -> Void
    ) async throws -> ImagePullOutcome {
        let request = try request.validated()
        try await requireSupportedInstallation()
        var arguments = ["image", "pull", "--progress", "plain"]
        if let platform = request.platform {
            arguments += ["--platform", platform]
        }
        arguments.append(request.reference)
        let exitCode = try await executeImagePull(arguments, progress: progress)
        guard exitCode == 0 else { throw ContainerCLIError.nonZeroExit(exitCode) }
        let observed = try await inspectImage(reference: request.reference)
        let platformMatched = request.platform.map { expected in
            let allowsVariant = expected.split(separator: "/").count == 2
            return observed.platforms.contains { platform in
                platform.identifier == expected
                    || (allowsVariant && platform.identifier.hasPrefix(expected + "/"))
            }
        } ?? true
        return ImagePullOutcome(
            exitCode: exitCode,
            observedImage: observed,
            matchedExpectation: platformMatched
        )
    }

    func deleteImage(reference: String) async throws -> ImageDeleteOutcome {
        _ = try ImageDeleteRequest(reference: reference, confirmationTarget: reference).validated()
        let currentImages = try await listImages()
        guard let target = currentImages.items.first(where: { imageMatchesReference($0, reference: reference) }) else {
            throw ProblemDetail(code: .targetNotFound, message: "未找到指定镜像。")
        }
        guard !isProtectedSystemImage(target) else {
            throw ProblemDetail(code: .stateConflict, message: "Apple container 系统镜像不能删除。")
        }
        let containers = try await listContainers()
        guard !containers.items.contains(where: { container in
            container.imageReference.map { imageMatchesReference(target, reference: $0) } == true
        }) else {
            throw ProblemDetail(code: .stateConflict, message: "镜像仍被容器引用，请先删除相关容器。")
        }

        let result = try await execute(["image", "delete", target.name], timeout: mutationTimeout)
        guard result.exitCode == 0 else { throw ContainerCLIError.nonZeroExit(result.exitCode) }
        let readback = try await listImages()
        let targetAbsent = !readback.items.contains { imageMatchesReference($0, reference: target.name) }
        return ImageDeleteOutcome(
            exitCode: result.exitCode,
            targetAbsent: targetAbsent,
            observedAt: readback.observedAt
        )
    }

    func createContainer(_ request: ContainerCreateRequest) async throws -> ContainerCreateOutcome {
        let request = try request.validated()
        try await requireSupportedInstallation()
        var arguments = ["create", "--name", request.name]
        if let cpus = request.cpus {
            arguments += ["--cpus", String(cpus)]
        }
        if let memoryMiB = request.memoryMiB {
            arguments += ["--memory", "\(memoryMiB)M"]
        }
        for port in request.ports {
            arguments += ["--publish", port.normalizedSpec]
        }
        if let ssh = request.ssh {
            arguments += ["--publish", PortMapping(hostPort: ssh.hostPort, containerPort: 22).normalizedSpec]
            arguments += ["--label", "\(SSHContainerLabels.enabled)=true"]
            arguments += ["--label", "\(SSHContainerLabels.hostPort)=\(ssh.hostPort)"]
            arguments += ["--label", "\(SSHContainerLabels.username)=\(ssh.username)"]
        }
        for environment in request.environment {
            arguments += ["--env", "\(environment.name)=\(environment.value)"]
        }
        if let ssh = request.ssh {
            arguments += ["--env", "\(SSHCreateConfiguration.userEnvironmentName)=\(ssh.username)"]
            arguments += ["--env", "\(SSHCreateConfiguration.publicKeyEnvironmentName)=\(ssh.publicKey)"]
            arguments += ["--init", "--entrypoint", "/bin/sh"]
        }
        arguments += ["--", request.image]
        if request.ssh != nil {
            arguments += ["-c", SSHContainerBootstrap.script]
        } else {
            arguments += request.arguments
        }

        let createResult = try await execute(arguments, timeout: mutationTimeout)
        guard createResult.exitCode == 0 else {
            throw ContainerCLIError.nonZeroExit(createResult.exitCode)
        }
        let created = try await findContainer(named: request.name)
        guard let created,
              created.state == .created || created.state == .stopped else {
            return ContainerCreateOutcome(
                exitCode: createResult.exitCode,
                observedContainer: created,
                matchedExpectation: false
            )
        }
        guard request.startAfterCreate else {
            return ContainerCreateOutcome(
                exitCode: createResult.exitCode,
                observedContainer: created,
                matchedExpectation: true
            )
        }

        let startResult = try await execute(["start", request.name], timeout: mutationTimeout)
        guard startResult.exitCode == 0 else {
            throw ContainerCLIError.nonZeroExit(startResult.exitCode)
        }
        let running = try await findContainer(named: request.name)
        return ContainerCreateOutcome(
            exitCode: startResult.exitCode,
            observedContainer: running,
            matchedExpectation: running?.state == .running
        )
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

    func deleteContainer(id: String) async throws -> ContainerDeleteOutcome {
        let current = try await requireContainer(id: id)
        guard current.state == .stopped || current.state == .created else {
            throw ProblemDetail(code: .stateConflict)
        }
        let result = try await execute(["delete", id], timeout: mutationTimeout)
        guard result.exitCode == 0 else { throw ContainerCLIError.nonZeroExit(result.exitCode) }
        let readback = try await listContainers()
        let targetAbsent = !readback.items.contains {
            $0.id == id || $0.displayName == id
        }
        return ContainerDeleteOutcome(
            exitCode: result.exitCode,
            targetAbsent: targetAbsent,
            observedAt: readback.observedAt
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

    private func executeImagePull(
        _ arguments: [String],
        progress: @escaping @Sendable (ImagePullProgress) async -> Void
    ) async throws -> Int32 {
        guard let executableURL else {
            throw ContainerCLIError.unavailable(unavailableCompatibility)
        }
        let events = executor.stream(CommandRequest(
            executableURL: executableURL,
            arguments: arguments,
            timeout: imagePullTimeout,
            maximumOutputBytes: maximumOutputBytes
        ))
        var stdoutLines = ProgressLineBuffer()
        var stderrLines = ProgressLineBuffer()
        var outputBytes = 0
        var exitCode: Int32?

        for try await event in events {
            let lines: [String]
            switch event {
            case .stdout(let data):
                outputBytes = try checkedOutputSize(current: outputBytes, adding: data.count)
                lines = stdoutLines.append(data)
            case .stderr(let data):
                outputBytes = try checkedOutputSize(current: outputBytes, adding: data.count)
                lines = stderrLines.append(data)
            case .dropped:
                continue
            case .exited(let status):
                exitCode = status
                continue
            }
            for line in lines {
                if let update = CLIOutputParser.parseImagePullProgress(line: line) {
                    await progress(update)
                }
            }
        }
        for line in stdoutLines.finish() + stderrLines.finish() {
            if let update = CLIOutputParser.parseImagePullProgress(line: line) {
                await progress(update)
            }
        }
        guard let exitCode else { throw CommandExecutionError.streamFailed }
        return exitCode
    }

    private func checkedOutputSize(current: Int, adding: Int) throws -> Int {
        guard adding <= maximumOutputBytes - current else {
            throw CommandExecutionError.outputLimitExceeded(limit: maximumOutputBytes)
        }
        return current + adding
    }

    private func requireContainer(id: String) async throws -> ContainerSummary {
        guard !id.isEmpty, !id.hasPrefix("-") else { throw ContainerCLIError.invalidIdentifier }
        let list = try await listContainers()
        guard let summary = list.items.first(where: { $0.id == id }) else {
            throw ContainerCLIError.targetNotFound
        }
        return summary
    }

    private func findContainer(named name: String) async throws -> ContainerSummary? {
        let list = try await listContainers()
        return list.items.first { $0.id == name || $0.displayName == name }
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

private struct ProgressLineBuffer {
    private var pending = Data()

    mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let separator = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let line = Data(pending[..<separator])
            var end = pending.index(after: separator)
            while end < pending.endIndex && (pending[end] == 0x0A || pending[end] == 0x0D) {
                end = pending.index(after: end)
            }
            pending.removeSubrange(..<end)
            if !line.isEmpty { lines.append(String(decoding: line, as: UTF8.self)) }
        }
        return lines
    }

    mutating func finish() -> [String] {
        guard !pending.isEmpty else { return [] }
        defer { pending.removeAll(keepingCapacity: false) }
        return [String(decoding: pending, as: UTF8.self)]
    }
}
