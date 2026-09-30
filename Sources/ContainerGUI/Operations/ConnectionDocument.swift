import CryptoKit
import Foundation

struct ConnectionDocument: Sendable {
    enum Format: Sendable { case dotenv, nginx }
    private struct Edit: Sendable {
        let id: String
        let range: NSRange
        let isPort: Bool
        let isAuthority: Bool
    }
    private struct Token {
        let value: String
        let range: NSRange
    }

    let endpoints: [ContainerConnectionEndpoint]
    let revision: String
    private let text: String
    private let edits: [Edit]

    init(_ data: Data, format: Format) throws {
        guard data.count <= OdooConfigurationFile.maximumBytes, let text = String(data: data, encoding: .utf8), !text.contains("\0") else { throw OdooConfigurationError.invalid }
        self.text = text
        revision = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        switch format {
        case .dotenv: (endpoints, edits) = try Self.dotenv(text)
        case .nginx: (endpoints, edits) = try Self.nginx(text)
        }
    }

    func replacing(endpointId: String, host: String, port: Int) throws -> Data {
        guard endpoints.contains(where: { $0.id == endpointId }), OdooDatabaseSaveRequest.isValidHost(host), (1...65535).contains(port) else { throw OdooConfigurationError.invalid }
        var updated = text
        for edit in edits.filter({ $0.id == endpointId }).sorted(by: { $0.range.location > $1.range.location }) {
            let value = edit.isAuthority ? "\(host.contains(":") ? "[\(host)]" : host):\(port)" : edit.isPort ? String(port) : host
            updated = (updated as NSString).replacingCharacters(in: edit.range, with: value)
        }
        let data = Data(updated.utf8)
        guard data.count <= OdooConfigurationFile.maximumBytes else { throw OdooConfigurationError.invalid }
        return data
    }

    private static func dotenv(_ text: String) throws -> ([ContainerConnectionEndpoint], [Edit]) {
        // Do not mistake lines inside a multiline secret for real database assignments.
        let quoted = try NSRegularExpression(pattern: #"^(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')"#)
        if text.range(of: #"(?m)^[\t ]*(?:export[\t ]+)?['"](?:DB_HOST|DB_PORT)['"][\t ]*="#, options: .regularExpression) != nil { throw OdooConfigurationError.invalid }
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") { continue }
            if let separator = trimmed.firstIndex(of: "=") {
                let value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\"") || value.hasPrefix("'") {
                    guard quoted.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)) != nil else { throw OdooConfigurationError.invalid }
                }
            }
        }
        let expression = try NSRegularExpression(pattern: #"(?m)^[\t ]*(?:export[\t ]+)?(DB_HOST|DB_PORT)[\t ]*=[\t ]*([^\r\n]*)"#)
        let string = text as NSString
        var values: [String: String] = [:]
        var edits: [Edit] = []
        for match in expression.matches(in: text, range: NSRange(location: 0, length: string.length)) {
            let key = string.substring(with: match.range(at: 1))
            guard values[key] == nil else { throw OdooConfigurationError.invalid }
            let raw = string.substring(with: match.range(at: 2)) as NSString
            var range = NSRange(location: 0, length: raw.length)
            if raw.hasPrefix("\"") || raw.hasPrefix("'") {
                let quote = raw.substring(to: 1)
                let end = raw.range(of: quote, range: NSRange(location: 1, length: raw.length - 1))
                guard end.location != NSNotFound else { throw OdooConfigurationError.invalid }
                let suffix = raw.substring(from: end.location + 1).trimmingCharacters(in: .whitespaces)
                guard suffix.isEmpty || suffix.hasPrefix("#") else { throw OdooConfigurationError.invalid }
                range = NSRange(location: 1, length: end.location - 1)
            } else {
                let comment = raw.range(of: #"[\t ]+#"#, options: .regularExpression)
                let value = raw.substring(to: comment.location == NSNotFound ? raw.length : comment.location).trimmingCharacters(in: .whitespaces)
                range.length = (value as NSString).length
            }
            values[key] = raw.substring(with: range)
            edits.append(.init(id: "database", range: NSRange(location: match.range(at: 2).location + range.location, length: range.length), isPort: key == "DB_PORT", isAuthority: false))
        }
        guard let host = values["DB_HOST"], OdooDatabaseSaveRequest.isValidHost(host), let rawPort = values["DB_PORT"], let port = Int(rawPort), (1...65535).contains(port) else { throw OdooConfigurationError.invalid }
        return ([.init(id: "database", label: "数据库连接", host: host, port: port)], edits)
    }

    private static func nginx(_ text: String) throws -> ([ContainerConnectionEndpoint], [Edit]) {
        let string = text as NSString
        let lexer = try NSRegularExpression(pattern: #"#[^\r\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[{};]|[^\s{};#"']+"#)
        var tokens: [Token] = []
        var offset = 0
        for match in lexer.matches(in: text, range: NSRange(location: 0, length: string.length)) {
            guard string.substring(with: NSRange(location: offset, length: match.range.location - offset)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OdooConfigurationError.invalid }
            let value = string.substring(with: match.range)
            if !value.hasPrefix("\"") && !value.hasPrefix("'") && !value.hasPrefix("#") && value.contains("\\") { throw OdooConfigurationError.invalid }
            if !value.hasPrefix("#") { tokens.append(.init(value: value, range: match.range)) }
            offset = NSMaxRange(match.range)
        }
        guard string.substring(from: offset).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OdooConfigurationError.invalid }
        let url = try NSRegularExpression(pattern: #"^(https?)://(\[[0-9A-Fa-f:]+\]|[A-Za-z0-9._-]+)(?::([0-9]{1,5}))?([/?][^\s]*)?$"#)
        var directive: [Token] = []
        var contexts: [String] = []
        var endpoints: [ContainerConnectionEndpoint] = []
        var edits: [Edit] = []
        for token in tokens {
            switch token.value {
            case "{":
                guard !directive.isEmpty, directive[0].value != "upstream", !directive[0].value.hasPrefix("\""), !directive[0].value.hasPrefix("'") else { throw OdooConfigurationError.invalid }
                let location = directive.first?.value == "location" ? directive.last?.value : nil
                contexts.append(location.flatMap { $0.range(of: #"^/[A-Za-z0-9/_-]*$"#, options: .regularExpression) == nil ? nil : $0 } ?? contexts.last ?? "")
                directive = []
            case "}":
                guard directive.isEmpty, !contexts.isEmpty else { throw OdooConfigurationError.invalid }
                contexts.removeLast()
            case ";":
                guard !directive.isEmpty, !directive[0].value.hasPrefix("\""), !directive[0].value.hasPrefix("'") else { throw OdooConfigurationError.invalid }
                if directive[0].value == "include" {
                    guard directive.count == 2, ["/etc/nginx/mime.types", "mime.types"].contains(directive[1].value) else { throw OdooConfigurationError.invalid }
                }
                if directive[0].value == "proxy_pass" {
                    guard directive.count == 2, endpoints.count < 32 else { throw OdooConfigurationError.invalid }
                    let target = directive[1]
                    let value = target.value as NSString
                    guard !target.value.contains("$"), !target.value.contains("\\"), let match = url.firstMatch(in: target.value, range: NSRange(location: 0, length: value.length)) else { throw OdooConfigurationError.invalid }
                    let host = value.substring(with: match.range(at: 2)).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    let portRange = match.range(at: 3)
                    let port = portRange.location == NSNotFound ? (value.substring(with: match.range(at: 1)) == "https" ? 443 : 80) : Int(value.substring(with: portRange)) ?? 0
                    guard OdooDatabaseSaveRequest.isValidHost(host), (1...65535).contains(port) else { throw OdooConfigurationError.invalid }
                    let id = "proxy-\(endpoints.count + 1)"
                    let label = contexts.last.flatMap { $0.isEmpty ? nil : $0 } ?? "proxy_pass \(endpoints.count + 1)"
                    endpoints.append(.init(id: id, label: label, host: host, port: port))
                    let authority = match.range(at: 2)
                    let end = portRange.location == NSNotFound ? NSMaxRange(authority) : NSMaxRange(portRange)
                    edits.append(.init(id: id, range: NSRange(location: target.range.location + authority.location, length: end - authority.location), isPort: false, isAuthority: true))
                }
                directive = []
            default: directive.append(token)
            }
        }
        guard directive.isEmpty, contexts.isEmpty, !endpoints.isEmpty else { throw OdooConfigurationError.invalid }
        return (endpoints, edits)
    }
}
