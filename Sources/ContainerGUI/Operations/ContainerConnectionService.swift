import Foundation

final class ContainerConnectionService<Reader: ContainerReading>: Sendable {
    private let reader: Reader
    private let odoo: OdooDatabaseService<Reader>
    private let coordinator: OperationCoordinator

    init(reader: Reader, odoo: OdooDatabaseService<Reader>, coordinator: OperationCoordinator) {
        self.reader = reader
        self.odoo = odoo
        self.coordinator = coordinator
    }

    func read(id: String) async throws -> ContainerConnectionView {
        let target = try await target(id: id)
        if target.isOdoo { return .init(odoo: try await odoo.read(id: id)) }
        guard target.restriction == nil || target.restriction == "runningSingleFile" else { return target.view() }
        do { return target.view(document: try await document(target)) }
        catch { return target.view(restriction: (error as? OdooConfigurationError) == .invalid ? "invalidConnectionConfig" : "configUnavailable") }
    }

    func submit(id: String, request: ContainerConnectionSaveRequest, idempotencyKey: String) async throws -> Operation {
        let request = try request.validated(for: id)
        let fingerprint = "updateContainerConnection:\(id):\(request.endpointId):\(request.host):\(request.port):\(request.expectedRevision)"
        let target = try await target(id: id)
        if target.isOdoo {
            guard request.endpointId == "database" else { throw ProblemDetail(code: .validationFailed) }
            return try await odoo.submit(id: id, request: .init(host: request.host, port: request.port, confirmationTarget: id, expectedRevision: request.expectedRevision), idempotencyKey: idempotencyKey)
        }
        if let existing = try await coordinator.existing(idempotencyKey: idempotencyKey, fingerprint: fingerprint) { return existing }
        guard target.restriction == nil else { throw ProblemDetail(code: .stateConflict, message: "此连接暂不支持安全编辑，请重新读取配置。") }
        let current: ConnectionDocument
        do { current = try await document(target) }
        catch { throw safeProblem(error) }
        guard current.revision == request.expectedRevision else { throw OdooConfigurationError.stale.problem }
        guard current.endpoints.contains(where: { $0.id == request.endpointId }) else { throw ProblemDetail(code: .validationFailed) }
        let result = try await coordinator.createWithDisposition(idempotencyKey: idempotencyKey, fingerprint: fingerprint, kind: .updateContainerConnection, target: .container(id: id), safeRequestSummary: ["containerId": .string(id), "connectionChanged": .bool(true)])
        if result.created { Task { await execute(result.operation, request: request, original: target) } }
        return result.operation
    }

    private func execute(_ operation: Operation, request: ContainerConnectionSaveRequest, original: Target) async {
        do {
            try await coordinator.markRunning(operation.id)
            let current = try await target(id: operation.target.id)
            guard current.restriction == nil, let file = current.file, let format = current.format,
                  current.file == original.file, current.preserveInode == original.preserveInode,
                  current.detail.configuration == original.detail.configuration,
                  current.detail.summary.state == original.detail.summary.state,
                  current.detail.summary.createdAt == original.detail.summary.createdAt,
                  current.detail.summary.imageReference == original.detail.summary.imageReference else { throw ProblemDetail(code: .stateConflict) }
            try await Task.detached(priority: .utility) {
                try OdooConfigurationFile.writeData(file, preserveInode: current.preserveInode) { data in
                    let document = try ConnectionDocument(data, format: format)
                    guard document.revision == request.expectedRevision else { throw OdooConfigurationError.stale }
                    return try document.replacing(endpointId: request.endpointId, host: request.host, port: request.port)
                }
            }.value
            try await coordinator.markVerifying(operation.id, exitCode: 0)
            let observed = try await read(id: operation.target.id)
            let endpoint = observed.endpoints.first { $0.id == request.endpointId }
            let matched = observed.editable && endpoint?.host == request.host && endpoint?.port == request.port
            let readback = OperationReadback(expectationMatched: matched, observedConnections: observed)
            if matched { _ = try await coordinator.succeed(operation.id, readback: readback) }
            else { _ = try await coordinator.fail(operation.id, problem: .init(code: .stateConflict), readback: readback) }
        } catch { _ = try? await coordinator.fail(operation.id, problem: safeProblem(error)) }
    }

    private struct Target: Sendable {
        let detail: ContainerDetail
        var isOdoo = false
        var kind = "unsupported"
        var file: URL? = nil
        var format: ConnectionDocument.Format? = nil
        var preserveInode = false
        var restriction: String? = nil

        func view(document: ConnectionDocument? = nil, restriction: String? = nil) -> ContainerConnectionView {
            let reason = restriction ?? self.restriction
            return .init(containerId: detail.summary.id, kind: kind, editable: reason == nil && document != nil, endpoints: document?.endpoints ?? [], revision: document?.revision, storage: file == nil ? nil : "hostMount", restriction: reason)
        }
    }

    private func target(id: String) async throws -> Target {
        let detail = try await reader.containerDetail(id: id)
        guard detail.summary.id == id else { throw ProblemDetail(code: .targetNotFound) }
        let configuration = detail.configuration.objectValue ?? [:]
        let process = configuration["initProcess"]?.objectValue ?? [:]
        let arguments = process["arguments"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let image = detail.summary.imageReference?.split(separator: "/").last?.split(whereSeparator: { $0 == ":" || $0 == "@" }).first.map(String.init) ?? ""
        let executables = [process["executable"]?.stringValue, arguments.first].compactMap { $0 }.map { URL(fileURLWithPath: $0).lastPathComponent }
        if image == "odoo" || executables.contains("odoo") { return Target(detail: detail, isOdoo: true, kind: "database") }
        let mounts = (configuration["mounts"]?.arrayValue ?? []).compactMap(\.objectValue)
        let isNginx = image == "nginx" || executables.contains("nginx")
        let dotenvCommands = ["ln -s /app-config/app.env /app/.env && exec python app.py", "rm -f /app/.env && ln -s /app-config/app.env /app/.env && exec python app.py"]
        let shell = process["executable"]?.stringValue.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        let usesDotenv = ["sh", "bash"].contains(shell) && arguments.count == 2 && arguments[0] == "-c" && dotenvCommands.contains(arguments[1])
        guard isNginx || usesDotenv else { return Target(detail: detail, restriction: "unsupported") }
        var target = Target(detail: detail, kind: isNginx ? "backend" : "database", format: isNginx ? .nginx : .dotenv)
        let environmentKeys = (process["environment"]?.arrayValue ?? []).compactMap(\.stringValue).map { String($0.split(separator: "=", maxSplits: 1).first ?? "") }
        if (isNginx && (mounts.contains { $0["destination"]?.stringValue?.hasPrefix("/etc/nginx/templates") == true } || environmentKeys.contains { $0.hasPrefix("NGINX_ENVSUBST") })) || (!isNginx && environmentKeys.contains { ["DB_HOST", "DB_PORT"].contains($0) }) {
            target.restriction = "unsupportedLocation"
            return target
        }
        let nginxArguments = arguments.first.map { URL(fileURLWithPath: $0).lastPathComponent } == "nginx" ? Array(arguments.dropFirst()) : arguments
        if isNginx && !nginxArguments.isEmpty && nginxArguments != ["-g", "daemon off;"] {
            target.restriction = "unsupportedLocation"
            return target
        }
        let destinations = isNginx ? ["/etc/nginx", "/etc/nginx/nginx.conf", "/etc/nginx/conf.d", "/etc/nginx/conf.d/default.conf"] : ["/app-config"]
        let candidates = mounts.filter { destinations.contains($0["destination"]?.stringValue ?? "") }
        guard candidates.count == 1, let mount = candidates.first, mount["type"]?.objectValue?["virtiofs"] != nil,
              let source = mount["source"]?.stringValue, source.hasPrefix("/"),
              !source.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              let destination = mount["destination"]?.stringValue else {
            target.restriction = "unsupportedLocation"
            return target
        }
        target.preserveInode = destination.hasSuffix(".conf")
        let mounted = URL(fileURLWithPath: source, isDirectory: !target.preserveInode)
        if target.preserveInode { target.file = mounted }
        else { target.file = mounted.appendingPathComponent(isNginx ? (destination == "/etc/nginx" ? "nginx.conf" : "default.conf") : "app.env") }
        if target.preserveInode && ![.stopped, .created].contains(detail.summary.state) {
            target.restriction = "runningSingleFile"
        } else if isNginx && !target.preserveInode {
            let safeDirectory = try? await Task.detached(priority: .utility) {
                if FileManager.default.fileExists(atPath: mounted.appendingPathComponent("templates").path) { return false }
                if destination == "/etc/nginx/conf.d" {
                    let names = try FileManager.default.contentsOfDirectory(atPath: mounted.path)
                    return names.filter { $0.hasSuffix(".conf") } == ["default.conf"] && !names.contains { $0.hasSuffix(".template") }
                }
                return true
            }.value
            if safeDirectory != true { target.restriction = safeDirectory == nil ? "configUnavailable" : "unsupportedLocation" }
        }
        return target
    }

    private func document(_ target: Target) async throws -> ConnectionDocument {
        guard let file = target.file, let format = target.format else { throw OdooConfigurationError.unavailable }
        return try await Task.detached(priority: .utility) { try ConnectionDocument(OdooConfigurationFile.readData(file), format: format) }.value
    }

    private func safeProblem(_ error: any Error) -> ProblemDetail {
        if let configuration = error as? OdooConfigurationError {
            if configuration == .stale { return configuration.problem }
            return .init(code: .stateConflict, message: "此连接暂不支持安全编辑，请重新读取配置。")
        }
        return error.containerGUIProblem
    }
}
