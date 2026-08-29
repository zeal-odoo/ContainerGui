import Foundation

struct PortMapping: Codable, Equatable, Sendable {
    let hostPort: Int
    let containerPort: Int
    let protocolName: String

    private enum CodingKeys: String, CodingKey {
        case hostPort, containerPort
        case protocolName = "protocol"
    }

    init(hostPort: Int, containerPort: Int, protocolName: String = "tcp") {
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.protocolName = protocolName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hostPort = try container.decode(Int.self, forKey: .hostPort)
        containerPort = try container.decode(Int.self, forKey: .containerPort)
        protocolName = try container.decodeIfPresent(String.self, forKey: .protocolName) ?? "tcp"
    }

    var normalizedSpec: String {
        "127.0.0.1:\(hostPort):\(containerPort)/\(protocolName)"
    }
}

struct EnvironmentEntry: Codable, Equatable, Sendable {
    let name: String
    let value: String
}

struct ContainerCreateRequest: Codable, Equatable, Sendable {
    let name: String
    let image: String
    let cpus: Double?
    let memoryMiB: Int?
    let ports: [PortMapping]
    let environment: [EnvironmentEntry]
    let arguments: [String]
    let startAfterCreate: Bool
    let ssh: SSHCreateConfiguration?

    private enum CodingKeys: String, CodingKey {
        case name, image, cpus, memoryMiB, ports, environment, arguments, startAfterCreate, ssh
    }

    init(
        name: String,
        image: String,
        cpus: Double? = nil,
        memoryMiB: Int? = nil,
        ports: [PortMapping] = [],
        environment: [EnvironmentEntry] = [],
        arguments: [String] = [],
        startAfterCreate: Bool = false,
        ssh: SSHCreateConfiguration? = nil
    ) {
        self.name = name
        self.image = image
        self.cpus = cpus
        self.memoryMiB = memoryMiB
        self.ports = ports
        self.environment = environment
        self.arguments = arguments
        self.startAfterCreate = startAfterCreate
        self.ssh = ssh
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        image = try container.decode(String.self, forKey: .image)
        cpus = try container.decodeIfPresent(Double.self, forKey: .cpus)
        memoryMiB = try container.decodeIfPresent(Int.self, forKey: .memoryMiB)
        ports = try container.decodeIfPresent([PortMapping].self, forKey: .ports) ?? []
        environment = try container.decodeIfPresent([EnvironmentEntry].self, forKey: .environment) ?? []
        arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        startAfterCreate = try container.decodeIfPresent(Bool.self, forKey: .startAfterCreate) ?? false
        ssh = try container.decodeIfPresent(SSHCreateConfiguration.self, forKey: .ssh)
    }

    func validated() throws -> Self {
        var errors: [String: String] = [:]
        if name.count > 128 || name.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#,
            options: .regularExpression
        ) == nil {
            errors["name"] = "容器名称格式无效"
        }
        if !isValidImageReference(image) {
            errors["image"] = "镜像引用格式无效"
        }
        if let cpus, !cpus.isFinite || cpus <= 0 || cpus > 1024 {
            errors["cpus"] = "CPU 必须大于 0 且不超过 1024"
        }
        if let memoryMiB, !(1...1_048_576).contains(memoryMiB) {
            errors["memoryMiB"] = "内存必须在 1...1048576 MiB 之间"
        }
        if ports.contains(where: { (1...1_023).contains($0.hostPort) }) {
            errors["ports"] = "主机端口必须使用 1024...65535；1024 以下需要 root 权限"
        } else if ports.count > 32 || ports.contains(where: {
            !(1...65_535).contains($0.hostPort)
                || !(1...65_535).contains($0.containerPort)
                || ($0.protocolName != "tcp" && $0.protocolName != "udp")
        }) || Set(ports.map(\.hostPort)).count != ports.count {
            errors["ports"] = "端口映射无效或主机端口重复"
        }
        let environmentNames = environment.map(\.name)
        if environment.count > 64
            || Set(environmentNames).count != environmentNames.count
            || environment.contains(where: {
                $0.name.range(
                    of: #"^[A-Za-z_][A-Za-z0-9_]*$"#,
                    options: .regularExpression
                ) == nil || $0.value.count > 4096 || $0.value.contains("\0")
            }) {
            errors["environment"] = "环境变量名称、数量或值无效"
        }
        if arguments.count > 64 || arguments.contains(where: { $0.count > 4096 || $0.contains("\0") }) {
            errors["arguments"] = "进程参数数量或内容无效"
        }
        if let ssh {
            do {
                _ = try ssh.validated()
            } catch let problem as ProblemDetail {
                for error in problem.fieldErrors ?? [] {
                    errors[error.field] = error.message
                }
            }
            if ports.contains(where: { $0.hostPort == ssh.hostPort }) {
                errors["ssh.hostPort"] = "SSH 主机端口不能与其他端口映射重复"
            }
            if ports.count >= 32 {
                errors["ports"] = "启用 SSH 后端口映射总数不能超过 32"
            }
            if !arguments.isEmpty {
                errors["arguments"] = "启用 SSH 时不能同时填写进程参数"
            }
            if !startAfterCreate {
                errors["startAfterCreate"] = "启用 SSH 时必须创建并启动容器"
            }
            let reservedEnvironmentNames = [
                SSHCreateConfiguration.userEnvironmentName,
                SSHCreateConfiguration.publicKeyEnvironmentName,
            ]
            if environment.contains(where: { reservedEnvironmentNames.contains($0.name) }) {
                errors["environment"] = "环境变量使用了 SSH 快速配置的保留名称"
            }
        }
        guard errors.isEmpty else {
            throw ProblemDetail(code: .validationFailed, fieldErrors: errors)
        }
        return self
    }

    var safeRequestSummary: [String: JSONValue] {
        var summary: [String: JSONValue] = [
            "name": .string(name),
            "image": .string(image),
            "ports": .array(ports.map { .string($0.normalizedSpec) }),
            "environmentNames": .array(environment.map { .string($0.name) }),
            "argumentCount": .number(Double(arguments.count)),
            "startAfterCreate": .bool(startAfterCreate),
        ]
        if let cpus { summary["cpus"] = .number(cpus) }
        if let memoryMiB { summary["memoryMiB"] = .number(Double(memoryMiB)) }
        if let ssh { summary["ssh"] = .object(ssh.safeRequestSummary) }
        return summary
    }
}

struct ContainerCreateOutcome: Equatable, Sendable {
    let exitCode: Int32
    let observedContainer: ContainerSummary?
    let matchedExpectation: Bool
}
