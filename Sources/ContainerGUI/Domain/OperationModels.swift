import Foundation

enum OperationKind: String, Codable, Sendable {
    case startContainer
    case stopContainer
    case runContainer
    case deleteContainer
    case startSystem
    case pullImage
    case createContainer
}

enum OperationTarget: Codable, Equatable, Hashable, Sendable {
    case container(id: String)
    case image(reference: String)
    case system

    var id: String {
        switch self {
        case .container(let id): id
        case .image(let reference): reference
        case .system: "system"
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, id }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let id = try container.decode(String.self, forKey: .id)
        switch kind {
        case "container": self = .container(id: id)
        case "image": self = .image(reference: id)
        case "system": self = .system
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown target kind")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .container(let id):
            try container.encode("container", forKey: .kind)
            try container.encode(id, forKey: .id)
        case .image(let reference):
            try container.encode("image", forKey: .kind)
            try container.encode(reference, forKey: .id)
        case .system:
            try container.encode("system", forKey: .kind)
            try container.encode("system", forKey: .id)
        }
    }
}

enum OperationState: String, Codable, Equatable, Sendable {
    case queued
    case running
    case verifying
    case succeeded
    case failed
    case cancelled

    var isTerminal: Bool { self == .succeeded || self == .failed || self == .cancelled }
}

struct OperationReadback: Codable, Equatable, Sendable {
    let expectationMatched: Bool
    let observedContainer: JSONValue?
    let observedImage: JSONValue?
    let observedSystemState: String?
    let targetAbsent: Bool?
    let observedAt: Date

    enum CodingKeys: String, CodingKey {
        case observedContainer, observedImage, observedSystemState, targetAbsent, observedAt
        case expectationMatched = "matchedExpectation"
    }

    init(
        observedState: String? = nil,
        expectationMatched: Bool,
        observedContainer: JSONValue? = nil,
        observedImage: JSONValue? = nil,
        targetAbsent: Bool? = nil,
        observedAt: Date = Date()
    ) {
        self.expectationMatched = expectationMatched
        self.observedContainer = observedContainer
        self.observedImage = observedImage
        self.observedSystemState = observedState
        self.targetAbsent = targetAbsent
        self.observedAt = observedAt
    }
}

struct Operation: Codable, Equatable, Sendable {
    let id: UUID
    let kind: OperationKind
    let target: OperationTarget
    var state: OperationState
    let requestedAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    let safeRequestSummary: [String: JSONValue]
    var progress: ImagePullProgress? = nil
    var exitCode: Int32?
    var error: ProblemDetail?
    var readback: OperationReadback?
}
