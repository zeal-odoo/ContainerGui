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

struct SharedDirectoryConfiguration: Codable, Equatable, Sendable {
    static let odooAddonsPath = "/mnt/extra-addons"

    let hostPath: String
    let containerPath: String

    var mountSpec: String {
        "type=bind,source=\(hostPath),target=\(containerPath)"
    }
}

struct OdooDatabaseConfiguration: Codable, Equatable, Sendable {
    let host: String
    let port: Int
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
    let sharedDirectory: SharedDirectoryConfiguration?
    let odooDatabase: OdooDatabaseConfiguration?

    private enum CodingKeys: String, CodingKey {
        case name, image, cpus, memoryMiB, ports, environment, arguments, startAfterCreate, ssh
        case sharedDirectory, odooDatabase
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
        ssh: SSHCreateConfiguration? = nil,
        sharedDirectory: SharedDirectoryConfiguration? = nil,
        odooDatabase: OdooDatabaseConfiguration? = nil
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
        self.sharedDirectory = sharedDirectory
        self.odooDatabase = odooDatabase
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
        sharedDirectory = try container.decodeIfPresent(SharedDirectoryConfiguration.self, forKey: .sharedDirectory)
        odooDatabase = try container.decodeIfPresent(OdooDatabaseConfiguration.self, forKey: .odooDatabase)
    }

    static func isOfficialOdooImageReference(_ reference: String) -> Bool {
        var repository = reference
        if let digestSeparator = repository.firstIndex(of: "@") {
            repository = String(repository[..<digestSeparator])
        }
        if let tagSeparator = repository.lastIndex(of: ":") {
            let slashOffset = repository.lastIndex(of: "/")
                .map { repository.distance(from: repository.startIndex, to: $0) } ?? -1
            let tagOffset = repository.distance(from: repository.startIndex, to: tagSeparator)
            if tagOffset > slashOffset {
                repository = String(repository[..<tagSeparator])
            }
        }
        return repository == "odoo" || repository == "docker.io/library/odoo"
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
        if let cpus, !cpus.isFinite || cpus.rounded() != cpus || cpus < 1 || cpus > 1024 {
            errors["cpus"] = "CPU 必须为 1...1024 的整数"
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
        let officialOdooImage = Self.isOfficialOdooImageReference(image)
        if let sharedDirectory {
            if !Self.isSafeMountPath(sharedDirectory.hostPath) {
                errors["sharedDirectory.hostPath"] = "本机目录必须是安全的非根绝对路径"
            } else {
                var isDirectory: ObjCBool = false
                if !FileManager.default.fileExists(
                    atPath: sharedDirectory.hostPath,
                    isDirectory: &isDirectory
                ) || !isDirectory.boolValue {
                    errors["sharedDirectory.hostPath"] = "本机目录不存在或不是目录"
                }
            }
            if !Self.isSafeMountPath(sharedDirectory.containerPath) {
                errors["sharedDirectory.containerPath"] = "容器目录必须是安全的非根绝对路径"
            } else if officialOdooImage
                        && sharedDirectory.containerPath != SharedDirectoryConfiguration.odooAddonsPath {
                errors["sharedDirectory.containerPath"] = "Odoo 自定义模块目录必须为 /mnt/extra-addons"
            }
        }
        if let odooDatabase {
            if !officialOdooImage {
                errors["odooDatabase"] = "数据库配置只适用于 Docker Hub 官方 Odoo 镜像"
            }
            if !Self.isValidDatabaseHost(odooDatabase.host) {
                errors["odooDatabase.host"] = "数据库地址格式无效"
            }
            if !(1...65_535).contains(odooDatabase.port) {
                errors["odooDatabase.port"] = "数据库端口必须在 1...65535 之间"
            }
            if environment.contains(where: { $0.name == "HOST" || $0.name == "PORT" }) {
                errors["environment"] = "已使用 Odoo 数据库字段，环境变量不能重复定义 HOST 或 PORT"
            }
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
        if let sharedDirectory {
            summary["sharedDirectory"] = .object([
                "configured": .bool(true),
                "containerPath": .string(sharedDirectory.containerPath),
            ])
        }
        if odooDatabase != nil { summary["odooDatabaseConfigured"] = .bool(true) }
        return summary
    }

    private static func isSafeMountPath(_ path: String) -> Bool {
        guard path.count <= 4096,
              path.hasPrefix("/"),
              path != "/",
              !path.contains(","),
              !path.contains("\0"),
              !path.contains("\n"),
              !path.contains("\r") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false)
            .contains(where: { $0 == "." || $0 == ".." })
    }

    private static func isValidDatabaseHost(_ host: String) -> Bool {
        guard (1...255).contains(host.count),
              host.contains(where: { $0.isLetter || $0.isNumber }),
              host.range(of: #"^[A-Za-z0-9._:-]+$"#, options: .regularExpression) != nil else {
            return false
        }
        return true
    }
}

struct ContainerCreateOutcome: Equatable, Sendable {
    let exitCode: Int32
    let observedContainer: ContainerSummary?
    let matchedExpectation: Bool
}
