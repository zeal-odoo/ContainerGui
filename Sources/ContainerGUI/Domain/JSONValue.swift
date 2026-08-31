import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    func redacted() -> JSONValue {
        switch self {
        case .object(let object):
            return .object(object.reduce(into: [:]) { result, element in
                if Self.isEnvironmentKey(element.key) {
                    result[element.key] = element.value.redactedEnvironment()
                } else if Self.isSensitive(element.key) {
                    result[element.key] = .string("[REDACTED]")
                } else {
                    result[element.key] = element.value.redacted()
                }
            })
        case .array(let values):
            return .array(values.map { $0.redacted() })
        case .string(let value):
            return .string(
                Self.redactedEmbeddedAssignment(value)
                    ?? Self.redactedCredentialURI(value)
                    ?? value
            )
        default:
            return self
        }
    }

    private func redactedEnvironment() -> JSONValue {
        switch self {
        case .object(let object):
            let normalizedKeys = Set(object.keys.map { $0.lowercased() })
            if normalizedKeys.contains("name"), normalizedKeys.contains("value") {
                return .object(object.reduce(into: [:]) { result, element in
                    result[element.key] = element.key.lowercased() == "value"
                        ? element.value.redactedEnvironmentValue()
                        : element.value.redacted()
                })
            }
            return .object(object.mapValues { $0.redactedEnvironmentValue() })
        case .array(let values):
            return .array(values.map { value in
                if case .string(let string) = value,
                   let redacted = Self.redactedAnyAssignment(string) {
                    return .string(redacted)
                }
                return value.redactedEnvironment()
            })
        default:
            return .string("[REDACTED]")
        }
    }

    private func redactedEnvironmentValue() -> JSONValue {
        switch self {
        case .object(let object):
            return .object(object.mapValues { $0.redactedEnvironmentValue() })
        case .array(let values):
            return .array(values.map { $0.redactedEnvironmentValue() })
        default:
            return .string("[REDACTED]")
        }
    }

    private static func isEnvironmentKey(_ key: String) -> Bool {
        let normalized = key.lowercased().replacingOccurrences(of: "-", with: "_")
        return normalized == "environment" || normalized == "env"
    }

    private static func isSensitive(_ key: String) -> Bool {
        let normalized = key.lowercased().replacingOccurrences(of: "-", with: "_")
        if normalized == SSHCreateConfiguration.publicKeyEnvironmentName.lowercased() {
            return true
        }
        let sensitiveNames = [
            "password", "passwd", "pass", "secret", "token", "api_key", "apikey",
            "access_key", "authorization", "credential", "private_key", "database_url", "dsn",
        ]
        let components = Set(normalized.split(separator: "_").map(String.init))
        return sensitiveNames.contains { name in
            normalized == name
                || normalized.hasSuffix("_\(name)")
                || components.contains(name)
        } || normalized.hasSuffix("password")
    }

    private static func redactedEmbeddedAssignment(_ value: String) -> String? {
        guard let separator = value.firstIndex(of: "="), separator != value.startIndex else {
            return nil
        }
        let name = String(value[..<separator])
        guard isSensitive(name)
                || name == SSHCreateConfiguration.publicKeyEnvironmentName else {
            return nil
        }
        return "\(name)=[REDACTED]"
    }

    private static func redactedAnyAssignment(_ value: String) -> String? {
        guard let separator = value.firstIndex(of: "="), separator != value.startIndex else {
            return nil
        }
        return "\(value[..<separator])=[REDACTED]"
    }

    private static func redactedCredentialURI(_ value: String) -> String? {
        guard var components = URLComponents(string: value),
              components.scheme != nil,
              components.host != nil else {
            return nil
        }
        var changed = false
        if components.user != nil {
            components.user = "[REDACTED]"
            changed = true
        }
        if components.password != nil {
            components.password = "[REDACTED]"
            changed = true
        }
        if let queryItems = components.queryItems {
            components.queryItems = queryItems.map { item in
                guard isSensitiveQueryName(item.name), item.value != nil else { return item }
                changed = true
                return URLQueryItem(name: item.name, value: "[REDACTED]")
            }
        }
        return changed ? components.string : nil
    }

    private static func isSensitiveQueryName(_ name: String) -> Bool {
        if isSensitive(name) { return true }
        let normalized = name.lowercased().replacingOccurrences(of: "-", with: "_")
        return [
            "auth", "code", "jwt", "key", "session", "session_id", "sessionid",
            "sig", "signature",
        ].contains { marker in
            normalized == marker || normalized.hasSuffix("_\(marker)")
        }
    }
}

extension JSONEncoder {
    static var containerGUI: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var containerGUI: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
