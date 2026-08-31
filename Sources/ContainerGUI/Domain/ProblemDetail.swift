import Foundation

enum ProblemCode: String, Codable, CaseIterable, Sendable {
    case authenticationRequired = "AUTHENTICATION_REQUIRED"
    case cliNotFound = "CLI_NOT_FOUND"
    case cliNotExecutable = "CLI_NOT_EXECUTABLE"
    case cliVersionUnsupported = "CLI_VERSION_UNSUPPORTED"
    case serviceUnavailable = "SERVICE_UNAVAILABLE"
    case cliTimeout = "CLI_TIMEOUT"
    case cliExitNonzero = "CLI_EXIT_NONZERO"
    case cliOutputInvalid = "CLI_OUTPUT_INVALID"
    case targetNotFound = "TARGET_NOT_FOUND"
    case stateConflict = "STATE_CONFLICT"
    case operationInProgress = "OPERATION_IN_PROGRESS"
    case idempotencyConflict = "IDEMPOTENCY_CONFLICT"
    case confirmationMismatch = "CONFIRMATION_MISMATCH"
    case validationFailed = "VALIDATION_FAILED"
    case originRejected = "ORIGIN_REJECTED"
    case requestTooLarge = "REQUEST_TOO_LARGE"
    case logSessionLimit = "LOG_SESSION_LIMIT"
    case outputLimitExceeded = "OUTPUT_LIMIT_EXCEEDED"
    case registryRateLimited = "REGISTRY_RATE_LIMITED"
    case registryUnavailable = "REGISTRY_UNAVAILABLE"
    case internalError = "INTERNAL_ERROR"

    var status: Int {
        switch self {
        case .authenticationRequired: 401
        case .originRejected: 403
        case .targetNotFound: 404
        case .stateConflict, .operationInProgress, .idempotencyConflict: 409
        case .requestTooLarge, .outputLimitExceeded: 413
        case .logSessionLimit, .registryRateLimited: 429
        case .validationFailed, .confirmationMismatch: 422
        case .cliTimeout: 504
        case .cliNotFound, .cliNotExecutable, .cliVersionUnsupported, .serviceUnavailable: 503
        case .registryUnavailable: 502
        case .cliExitNonzero, .cliOutputInvalid, .internalError: 500
        }
    }

    var safeMessage: String {
        switch self {
        case .authenticationRequired: "需要有效的本机访问凭据。"
        case .cliNotFound: "未找到 Apple container 命令行工具。"
        case .cliNotExecutable: "Apple container 工具不可执行。"
        case .cliVersionUnsupported: "当前 Apple container 版本暂不受支持。"
        case .serviceUnavailable: "容器系统服务当前不可用。"
        case .cliTimeout: "容器命令执行超时，请稍后重试。"
        case .cliExitNonzero: "容器命令执行失败。"
        case .cliOutputInvalid: "容器命令返回了无法识别的数据。"
        case .targetNotFound: "未找到指定容器。"
        case .stateConflict: "目标当前状态不允许此操作。"
        case .operationInProgress: "该目标已有操作正在进行。"
        case .idempotencyConflict: "该幂等键已用于不同请求。"
        case .confirmationMismatch: "确认目标与实际目标不一致。"
        case .validationFailed: "请求内容未通过校验。"
        case .originRejected: "请求来源不符合本机同源要求。"
        case .requestTooLarge: "请求内容超过允许大小。"
        case .logSessionLimit: "实时日志连接数已达到上限。"
        case .outputLimitExceeded: "容器命令输出超过安全上限。"
        case .registryRateLimited: "镜像平台请求过于频繁，请稍后重试。"
        case .registryUnavailable: "镜像平台当前不可用，请稍后重试。"
        case .internalError: "发生内部错误。"
        }
    }

    var retryable: Bool {
        switch self {
        case .serviceUnavailable, .cliTimeout, .operationInProgress, .logSessionLimit,
             .registryRateLimited, .registryUnavailable, .internalError: true
        default: false
        }
    }
}

struct FieldError: Codable, Equatable, Sendable {
    let field: String
    let message: String
}

struct ProblemDetail: Error, Codable, Equatable, Sendable {
    let type: String
    let title: String
    let status: Int
    let code: ProblemCode
    let message: String
    let retryable: Bool
    let operationID: UUID?
    let fieldErrors: [FieldError]?
    let diagnosticID: UUID

    enum CodingKeys: String, CodingKey {
        case type, title, status, code, message, retryable, fieldErrors
        case operationID = "operationId"
        case diagnosticID = "diagnosticId"
    }

    init(
        code: ProblemCode,
        message: String? = nil,
        operationID: UUID? = nil,
        fieldErrors: [String: String]? = nil,
        diagnosticID: UUID = UUID()
    ) {
        self.type = "urn:container-gui:problem:\(code.rawValue.lowercased())"
        self.title = code.safeMessage
        self.status = code.status
        self.code = code
        self.message = message ?? code.safeMessage
        self.retryable = code.retryable
        self.operationID = operationID
        self.fieldErrors = fieldErrors?.keys.sorted().compactMap { key in
            fieldErrors?[key].map { FieldError(field: key, message: $0) }
        }
        self.diagnosticID = diagnosticID
    }
}
