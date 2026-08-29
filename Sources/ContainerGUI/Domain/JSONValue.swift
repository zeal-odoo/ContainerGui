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
            return .object(
                object.mapValues { $0.redacted() }.mapValuesWithKeys { key, value in
                    Self.isSensitive(key) ? .string("[REDACTED]") : value
                }
            )
        case .array(let values):
            return .array(values.map { $0.redacted() })
        case .string(let value):
            return .string(Self.redactedEmbeddedAssignment(value) ?? value)
        default:
            return self
        }
    }

    private static func isSensitive(_ key: String) -> Bool {
        let normalized = key.lowercased().replacingOccurrences(of: "-", with: "_")
        if normalized == SSHCreateConfiguration.publicKeyEnvironmentName.lowercased() {
            return true
        }
        return ["password", "passwd", "secret", "token", "api_key", "apikey", "authorization", "credential", "private_key"]
            .contains { normalized == $0 || normalized.hasSuffix("_\($0)") }
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
}

private extension Dictionary where Key == String, Value == JSONValue {
    func mapValuesWithKeys(_ transform: (String, JSONValue) -> JSONValue) -> [String: JSONValue] {
        reduce(into: [:]) { result, element in
            result[element.key] = transform(element.key, element.value)
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
