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

struct SemanticVersion: Codable, Equatable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    var description: String { "\(major).\(minor).\(patch)" }
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
