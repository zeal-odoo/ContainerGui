import CryptoKit
import Foundation

enum SSHContainerLabels {
    static let enabled = "io.github.zeal-odoo.container-gui.ssh.enabled"
    static let hostPort = "io.github.zeal-odoo.container-gui.ssh.host-port"
    static let username = "io.github.zeal-odoo.container-gui.ssh.username"
}

struct SSHCreateConfiguration: Codable, Equatable, Sendable {
    static let fixedHost = "127.0.0.1"
    static let defaultHostPort = 2222
    static let defaultUsername = "dev"
    static let userEnvironmentName = "CONTAINER_GUI_SSH_USER"
    static let publicKeyEnvironmentName = "CONTAINER_GUI_SSH_AUTHORIZED_KEY"

    let hostPort: Int
    let username: String
    let publicKey: String

    func validated() throws -> Self {
        var errors: [String: String] = [:]
        if !(1_024...65_535).contains(hostPort) {
            errors["ssh.hostPort"] = "SSH 主机端口必须在 1024...65535 之间"
        }
        if !Self.isValidUsername(username) {
            errors["ssh.username"] = "SSH 用户名必须为 1...32 位小写安全名称，且不能为 root"
        }
        if parsedPublicKey == nil {
            errors["ssh.publicKey"] = "SSH 公钥格式无效，请粘贴单行公钥或选择 .pub 文件"
        }
        guard errors.isEmpty else {
            throw ProblemDetail(code: .validationFailed, fieldErrors: errors)
        }
        return self
    }

    var publicKeyType: String {
        parsedPublicKey?.type ?? "unknown"
    }

    var publicKeyFingerprint: String {
        guard let data = parsedPublicKey?.data else { return "invalid" }
        let digest = Data(SHA256.hash(data: data)).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        return "SHA256:\(digest)"
    }

    var safeRequestSummary: [String: JSONValue] {
        [
            "host": .string(Self.fixedHost),
            "hostPort": .number(Double(hostPort)),
            "username": .string(username),
            "publicKeyType": .string(publicKeyType),
            "publicKeyFingerprint": .string(publicKeyFingerprint),
        ]
    }

    static func isValidUsername(_ value: String) -> Bool {
        value != "root" && value.range(
            of: #"^[a-z_][a-z0-9_-]{0,31}$"#,
            options: .regularExpression
        ) != nil
    }

    private var parsedPublicKey: (type: String, data: Data)? {
        guard publicKey.count <= 4_096,
              publicKey == publicKey.trimmingCharacters(in: .whitespacesAndNewlines),
              !publicKey.contains("\n"),
              !publicKey.contains("\r"),
              !publicKey.contains("\0") else {
            return nil
        }
        let parts = publicKey.split(
            maxSplits: 2,
            omittingEmptySubsequences: true,
            whereSeparator: { $0 == " " || $0 == "\t" }
        )
        guard parts.count >= 2 else { return nil }
        let type = String(parts[0])
        let supportedTypes = [
            "ssh-ed25519",
            "ssh-rsa",
            "ecdsa-sha2-nistp256",
            "ecdsa-sha2-nistp384",
            "ecdsa-sha2-nistp521",
            "sk-ssh-ed25519@openssh.com",
            "sk-ecdsa-sha2-nistp256@openssh.com",
        ]
        guard supportedTypes.contains(type),
              let data = Data(base64Encoded: String(parts[1])),
              (16...16_384).contains(data.count) else {
            return nil
        }
        return (type, data)
    }
}

struct ContainerSSHConnection: Codable, Equatable, Sendable {
    let host: String
    let hostPort: Int
    let username: String

    var connectionCommand: String {
        "ssh -p \(hostPort) \(username)@\(host)"
    }

    private enum CodingKeys: String, CodingKey {
        case host, hostPort, username, connectionCommand
    }

    init(hostPort: Int, username: String) {
        self.host = SSHCreateConfiguration.fixedHost
        self.hostPort = hostPort
        self.username = username
    }

    init?(labels: [String: JSONValue]) {
        guard labels[SSHContainerLabels.enabled]?.stringValue == "true",
              let rawPort = labels[SSHContainerLabels.hostPort]?.stringValue,
              let hostPort = Int(rawPort),
              (1_024...65_535).contains(hostPort),
              let username = labels[SSHContainerLabels.username]?.stringValue,
              SSHCreateConfiguration.isValidUsername(username) else {
            return nil
        }
        self.init(hostPort: hostPort, username: username)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let host = try container.decode(String.self, forKey: .host)
        let hostPort = try container.decode(Int.self, forKey: .hostPort)
        let username = try container.decode(String.self, forKey: .username)
        guard host == SSHCreateConfiguration.fixedHost,
              (1_024...65_535).contains(hostPort),
              SSHCreateConfiguration.isValidUsername(username) else {
            throw DecodingError.dataCorruptedError(
                forKey: .host,
                in: container,
                debugDescription: "Invalid SSH connection metadata"
            )
        }
        self.init(hostPort: hostPort, username: username)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(hostPort, forKey: .hostPort)
        try container.encode(username, forKey: .username)
        try container.encode(connectionCommand, forKey: .connectionCommand)
    }
}

enum ContainerSSHState: String, Codable, Equatable, Sendable {
    case notConfigured
    case stopped
    case initializing
    case ready
    case failed
}

struct ContainerSSHStatus: Codable, Equatable, Sendable {
    let containerID: String
    let state: ContainerSSHState
    let connection: ContainerSSHConnection?
    let observedAt: Date

    enum CodingKeys: String, CodingKey {
        case state, connection, observedAt
        case containerID = "containerId"
    }
}

enum SSHContainerBootstrap {
    static let script = #"""
    set -eu

    if [ ! -x /usr/sbin/sshd ]; then
      if ! command -v apt-get >/dev/null 2>&1; then
        echo "Container GUI SSH requires a Debian or Ubuntu image with apt-get." >&2
        exit 64
      fi
      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y --no-install-recommends openssh-server
      rm -rf /var/lib/apt/lists/*
    fi

    ssh_user="$CONTAINER_GUI_SSH_USER"
    if ! id "$ssh_user" >/dev/null 2>&1; then
      useradd --create-home --shell /bin/sh "$ssh_user"
    fi
    ssh_home="$(getent passwd "$ssh_user" | cut -d: -f6)"
    if [ -z "$ssh_home" ]; then
      echo "Container GUI SSH could not resolve the user home directory." >&2
      exit 65
    fi

    install -d -m 0700 -o "$ssh_user" -g "$ssh_user" "$ssh_home/.ssh"
    umask 077
    printf '%s\n' "$CONTAINER_GUI_SSH_AUTHORIZED_KEY" > "$ssh_home/.ssh/authorized_keys"
    chown "$ssh_user:$ssh_user" "$ssh_home/.ssh/authorized_keys"
    chmod 0600 "$ssh_home/.ssh/authorized_keys"

    random_password="$(head -c 48 /dev/urandom | base64 | tr -d '\n')"
    printf '%s:%s\n' "$ssh_user" "$random_password" | chpasswd
    unset random_password

    install -d -m 0755 /run/sshd /etc/ssh/sshd_config.d
    ssh-keygen -A
    {
      printf '%s\n' \
        'PasswordAuthentication no' \
        'KbdInteractiveAuthentication no' \
        'ChallengeResponseAuthentication no' \
        'PermitEmptyPasswords no' \
        'PermitRootLogin no' \
        'PubkeyAuthentication yes' \
        'UsePAM no' \
        'X11Forwarding no'
      printf 'AllowUsers %s\n' "$ssh_user"
    } > /etc/ssh/sshd_config.d/99-container-gui.conf
    /usr/sbin/sshd -t
    exec /usr/sbin/sshd -D -e
    """#
}
