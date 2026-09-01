import Foundation

enum CLIResolutionError: Error, Equatable, Sendable {
    case notFound
    case notExecutable(path: String)
}

enum CLICompatibility: String, Codable, Equatable, Sendable {
    case supported
    case unsupported
    case unrecognized
    case missing
    case notExecutable
}

struct SemanticVersion: Codable, Comparable, Equatable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" { value.removeFirst() }
        let buildParts = value.split(separator: "+", omittingEmptySubsequences: false)
        guard buildParts.count <= 2,
              buildParts.count == 1 || !buildParts[1].isEmpty else { return nil }
        let components = buildParts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]) else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct CLIVersionClassification: Equatable, Sendable {
    let semanticVersion: SemanticVersion?
    let compatibility: CLICompatibility
}

extension Error {
    var containerGUIProblem: ProblemDetail {
        if let error = self as? CLIResolutionError {
            switch error {
            case .notFound: return ProblemDetail(code: .cliNotFound)
            case .notExecutable: return ProblemDetail(code: .cliNotExecutable)
            }
        }
        if let error = self as? CommandExecutionError {
            switch error {
            case .timedOut: return ProblemDetail(code: .cliTimeout)
            case .outputLimitExceeded: return ProblemDetail(code: .outputLimitExceeded)
            default: return ProblemDetail(code: .internalError)
            }
        }
        if self is DecodingError { return ProblemDetail(code: .cliOutputInvalid) }
        if let error = self as? ContainerCLIError {
            switch error {
            case .unavailable(let compatibility):
                switch compatibility {
                case .missing: return ProblemDetail(code: .cliNotFound)
                case .notExecutable: return ProblemDetail(code: .cliNotExecutable)
                case .unsupported, .unrecognized: return ProblemDetail(code: .cliVersionUnsupported)
                case .supported: return ProblemDetail(code: .internalError)
                }
            case .nonZeroExit: return ProblemDetail(code: .cliExitNonzero)
            case .invalidOutput: return ProblemDetail(code: .cliOutputInvalid)
            case .targetNotFound: return ProblemDetail(code: .targetNotFound)
            case .invalidIdentifier:
                return ProblemDetail(code: .validationFailed, fieldErrors: ["containerId": "容器标识无效"])
            }
        }
        if let problem = self as? ProblemDetail { return problem }
        if let error = self as? OperationCoordinatorError {
            switch error {
            case .idempotencyConflict: return ProblemDetail(code: .idempotencyConflict)
            case .operationInProgress, .globalLimitReached:
                return ProblemDetail(code: .operationInProgress)
            case .operationNotFound: return ProblemDetail(code: .targetNotFound)
            case .illegalTransition, .readbackRequired, .readbackMismatch:
                return ProblemDetail(code: .stateConflict)
            }
        }
        return ProblemDetail(code: .internalError)
    }
}
