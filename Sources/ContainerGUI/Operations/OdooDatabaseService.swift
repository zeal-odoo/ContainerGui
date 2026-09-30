import Foundation

final class OdooDatabaseService<Reader: ContainerReading>: Sendable {
    private let reader: Reader
    private let executor: any CommandExecuting
    private let executableURL: URL?
    private let coordinator: OperationCoordinator
    private let queryTimeout: Duration
    private let mutationTimeout: Duration

    init(reader: Reader, executor: any CommandExecuting, executableURL: URL?, coordinator: OperationCoordinator, queryTimeout: Duration = .seconds(5), mutationTimeout: Duration = .seconds(30)) {
        self.reader = reader
        self.executor = executor
        self.executableURL = executableURL
        self.coordinator = coordinator
        self.queryTimeout = queryTimeout
        self.mutationTimeout = mutationTimeout
    }

    func read(id: String) async throws -> OdooDatabaseView {
        let target = try await target(id: id)
        if let restriction = target.restriction {
            return .init(containerId: id, isOdoo: target.isOdoo, editable: false, storage: target.storage, restriction: restriction)
        }
        do {
            let endpoint = try await endpoint(target)
            return .init(containerId: id, isOdoo: true, editable: true, storage: target.storage, endpoint: endpoint)
        } catch let error as OdooConfigurationError {
            return .init(containerId: id, isOdoo: true, editable: false, storage: target.storage, restriction: error == .invalid ? "invalidConfig" : "configUnavailable")
        }
    }

    func submit(id: String, request: OdooDatabaseSaveRequest, idempotencyKey: String) async throws -> Operation {
        let request = try request.validated(for: id)
        let fingerprint = "updateOdooDatabaseConfig:\(id):\(request.host):\(request.port):\(request.expectedRevision)"
        if let existing = try await coordinator.existing(idempotencyKey: idempotencyKey, fingerprint: fingerprint) { return existing }
        let target = try await target(id: id)
        guard target.restriction == nil else { throw ProblemDetail(code: .stateConflict, message: "配置文件不可安全编辑，请检查位置、权限和容器状态。") }
        let current: OdooDatabaseEndpoint
        do { current = try await endpoint(target) }
        catch let error as OdooConfigurationError { throw error.problem }
        if let existing = try await coordinator.existing(idempotencyKey: idempotencyKey, fingerprint: fingerprint) { return existing }
        guard current.revision == request.expectedRevision else { throw OdooConfigurationError.stale.problem }
        let result = try await coordinator.createWithDisposition(
            idempotencyKey: idempotencyKey,
            fingerprint: fingerprint,
            kind: .updateOdooDatabaseConfig,
            target: .container(id: id),
            safeRequestSummary: ["containerId": .string(id), "databaseEndpointChanged": .bool(true)]
        )
        if result.created { Task { await execute(result.operation, request: request, originalTarget: target) } }
        return result.operation
    }

    private func execute(_ operation: Operation, request: OdooDatabaseSaveRequest, originalTarget: Target) async {
        do {
            try await coordinator.markRunning(operation.id)
            let current = try await target(id: operation.target.id)
            guard current.restriction == nil, current.file == originalTarget.file,
                  current.detail.summary.state == originalTarget.detail.summary.state,
                  current.detail.summary.createdAt == originalTarget.detail.summary.createdAt,
                  current.detail.summary.imageReference == originalTarget.detail.summary.imageReference else {
                throw ProblemDetail(code: .stateConflict)
            }
            if let file = current.file {
                try await Task.detached(priority: .utility) { try OdooConfigurationFile.write(file, request: request) }.value
            } else {
                _ = try await guest(current, request: request)
            }
            try await coordinator.markVerifying(operation.id, exitCode: 0)
            let observed = try await read(id: operation.target.id)
            let matched = observed.editable && observed.host == request.host && observed.port == request.port
            let readback = OperationReadback(expectationMatched: matched, observedOdooDatabase: observed)
            if matched { _ = try await coordinator.succeed(operation.id, readback: readback) }
            else { _ = try await coordinator.fail(operation.id, problem: .init(code: .stateConflict), readback: readback) }
        } catch {
            let problem = (error as? OdooConfigurationError)?.problem ?? error.containerGUIProblem
            _ = try? await coordinator.fail(operation.id, problem: problem)
        }
    }

    private struct Target: Sendable {
        let detail: ContainerDetail
        let isOdoo: Bool
        var file: URL? = nil
        var restriction: String? = nil
        var storage: String { file == nil ? "container" : "hostMount" }
    }

    private func target(id: String) async throws -> Target {
        let detail = try await reader.containerDetail(id: id)
        guard detail.summary.id == id else { throw ProblemDetail(code: .targetNotFound) }
        let configuration = detail.configuration.objectValue ?? [:]
        let process = configuration["initProcess"]?.objectValue ?? [:]
        let arguments = process["arguments"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let imageName = detail.summary.imageReference?.split(separator: "/").last?.split(separator: ":").first?.split(separator: "@").first
        let isOdoo = imageName == "odoo" || [process["executable"]?.stringValue, arguments.first].compactMap { $0 }.contains { URL(fileURLWithPath: $0).lastPathComponent == "odoo" }
        guard isOdoo else { return Target(detail: detail, isOdoo: false, restriction: "notOdoo") }
        var target = Target(detail: detail, isOdoo: true)
        if detail.odooConfigurationIsDefault == false {
            target.restriction = "unsupportedLocation"
            return target
        }
        for (index, argument) in arguments.enumerated() {
            if ["-c", "--config"].contains(argument), arguments.indices.contains(index + 1), arguments[index + 1] != "/etc/odoo/odoo.conf" {
                target.restriction = "unsupportedLocation"
                return target
            }
            if (argument.hasPrefix("--config=") && argument != "--config=/etc/odoo/odoo.conf") || argument.hasPrefix("--db_host") || argument.hasPrefix("--db_port") {
                target.restriction = "unsupportedLocation"
                return target
            }
        }
        let mounts = configuration["mounts"]?.arrayValue ?? []
        let candidates = mounts.compactMap { $0.objectValue }.filter {
            let destination = $0["destination"]?.stringValue
            return destination == "/etc/odoo" || destination == "/etc/odoo/odoo.conf"
        }
        if candidates.count > 1 {
            target.restriction = "unsupportedLocation"
        } else if let mount = candidates.first {
            guard mount["type"]?.objectValue?["virtiofs"] != nil,
                  let source = mount["source"]?.stringValue, source.hasPrefix("/"),
                  !source.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
                target.restriction = "unsupportedLocation"
                return target
            }
            if mount["destination"]?.stringValue == "/etc/odoo/odoo.conf" {
                // Replacing a single-file bind mount may leave the guest on its old inode.
                target.restriction = "singleFileMount"
            } else {
                target.file = URL(fileURLWithPath: source, isDirectory: true).appendingPathComponent("odoo.conf")
            }
        } else if detail.summary.state != .running {
            target.restriction = "stoppedInternal"
        }
        return target
    }

    private func endpoint(_ target: Target) async throws -> OdooDatabaseEndpoint {
        if let file = target.file {
            return try await Task.detached(priority: .utility) { try OdooConfigurationFile.read(file) }.value
        }
        return try await guest(target)
    }

    private func guest(_ target: Target, request: OdooDatabaseSaveRequest? = nil) async throws -> OdooDatabaseEndpoint {
        guard target.detail.summary.state == .running else { throw ProblemDetail(code: .stateConflict) }
        guard let executableURL else { throw ProblemDetail(code: .cliNotFound) }
        var arguments = ["exec", "--user", "root", target.detail.summary.id, "python3", "-c", OdooDatabaseGuest.script, request == nil ? "read" : "write", "/etc/odoo/odoo.conf"]
        if let request { arguments += [request.host, String(request.port), request.expectedRevision] }
        let result = try await executor.run(.init(executableURL: executableURL, arguments: arguments, timeout: request == nil ? queryTimeout : mutationTimeout, maximumOutputBytes: 4096))
        guard result.exitCode == 0 else {
            let reason = (try? JSONDecoder().decode([String: String].self, from: result.stdout))?["error"]
            if reason == "stale" { throw OdooConfigurationError.stale }
            if reason == "invalid" { throw OdooConfigurationError.invalid }
            if reason == "unavailable" || reason == "unsupportedLocation" { throw OdooConfigurationError.unavailable }
            throw ProblemDetail(code: .cliExitNonzero)
        }
        let endpoint = try JSONDecoder().decode(OdooDatabaseEndpoint.self, from: result.stdout)
        guard (endpoint.host.isEmpty || OdooDatabaseSaveRequest.isValidHost(endpoint.host)), (1...65535).contains(endpoint.port),
              endpoint.revision.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
            throw ProblemDetail(code: .cliOutputInvalid)
        }
        return endpoint
    }
}
