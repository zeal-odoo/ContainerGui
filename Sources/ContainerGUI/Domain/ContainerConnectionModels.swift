import Foundation

struct ContainerConnectionEndpoint: Codable, Equatable, Sendable {
    let id: String
    let label: String
    let host: String
    let port: Int
}

struct ContainerConnectionView: Codable, Equatable, Sendable {
    let containerId: String
    let kind: String
    let editable: Bool
    var endpoints: [ContainerConnectionEndpoint] = []
    var revision: String? = nil
    var storage: String? = nil
    var restriction: String? = nil
    var observedAt: Date = Date()

    init(odoo: OdooDatabaseView) {
        containerId = odoo.containerId
        kind = "database"
        editable = odoo.editable
        storage = odoo.storage
        restriction = odoo.restriction
        revision = odoo.revision
        observedAt = odoo.observedAt
        if let host = odoo.host, let port = odoo.port {
            endpoints = [.init(id: "database", label: "Odoo", host: host, port: port)]
        }
    }

    init(containerId: String, kind: String, editable: Bool, endpoints: [ContainerConnectionEndpoint] = [], revision: String? = nil, storage: String? = nil, restriction: String? = nil) {
        self.containerId = containerId
        self.kind = kind
        self.editable = editable
        self.endpoints = endpoints
        self.revision = revision
        self.storage = storage
        self.restriction = restriction
    }
}

struct ContainerConnectionSaveRequest: Codable, Sendable {
    let endpointId: String
    let host: String
    let port: Int
    let confirmationTarget: String
    let expectedRevision: String

    func validated(for id: String) throws -> Self {
        guard confirmationTarget == id else { throw ProblemDetail(code: .confirmationMismatch) }
        let normalized = host.trimmingCharacters(in: .whitespaces)
        var errors: [String: String] = [:]
        if !OdooDatabaseSaveRequest.isValidHost(normalized) { errors["host"] = "请输入有效的连接地址或主机名。" }
        if !(1...65535).contains(port) { errors["port"] = "连接端口必须在 1...65535 之间。" }
        if endpointId.range(of: #"^(database|proxy-[1-9][0-9]?)$"#, options: .regularExpression) == nil { errors["endpointId"] = "请重新选择连接。" }
        if expectedRevision.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) == nil { errors["expectedRevision"] = "请重新读取配置后再保存。" }
        guard errors.isEmpty else { throw ProblemDetail(code: .validationFailed, fieldErrors: errors) }
        return .init(endpointId: endpointId, host: normalized, port: port, confirmationTarget: confirmationTarget, expectedRevision: expectedRevision)
    }
}
