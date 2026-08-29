import Foundation

struct ImagePlatform: Codable, Equatable, Hashable, Sendable {
    let os: String
    let architecture: String
    let variant: String?

    init(os: String, architecture: String, variant: String? = nil) {
        self.os = os
        self.architecture = architecture
        self.variant = variant
    }

    var identifier: String {
        [os, architecture, variant].compactMap { $0 }.joined(separator: "/")
    }
}

struct ImageSummary: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let digest: String
    let platforms: [ImagePlatform]
    let sizeBytes: UInt64
    let observedAt: Date
}

struct ImageList: Codable, Equatable, Sendable {
    let items: [ImageSummary]
    let observedAt: Date
}

struct ImagePullRequest: Codable, Equatable, Sendable {
    let reference: String
    let platform: String?

    init(reference: String, platform: String? = nil) {
        self.reference = reference
        self.platform = platform
    }

    func validated() throws -> Self {
        var errors: [String: String] = [:]
        if !isValidImageReference(reference) {
            errors["reference"] = "镜像引用格式无效"
        }
        if let platform, !isValidImagePlatform(platform) {
            errors["platform"] = "平台必须为 linux/arm64 或 linux/amd64"
        }
        guard errors.isEmpty else {
            throw ProblemDetail(code: .validationFailed, fieldErrors: errors)
        }
        return self
    }

    var safeRequestSummary: [String: JSONValue] {
        var summary: [String: JSONValue] = ["reference": .string(reference)]
        if let platform { summary["platform"] = .string(platform) }
        return summary
    }
}

enum ImagePullProgressPhase: String, Codable, Equatable, Sendable {
    case fetching
    case unpacking
    case verifying
}

struct ImagePullProgress: Codable, Equatable, Sendable {
    let phase: ImagePullProgressPhase
    let percentComplete: Int
    let completedUnits: Int?
    let totalUnits: Int?
    let updatedAt: Date

    init(
        phase: ImagePullProgressPhase,
        percentComplete: Int,
        completedUnits: Int? = nil,
        totalUnits: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.phase = phase
        self.percentComplete = min(max(percentComplete, 0), 100)
        self.completedUnits = completedUnits
        self.totalUnits = totalUnits
        self.updatedAt = updatedAt
    }

    func preservingPercent(atLeast minimum: Int) -> Self {
        Self(
            phase: phase,
            percentComplete: max(percentComplete, minimum),
            completedUnits: completedUnits,
            totalUnits: totalUnits,
            updatedAt: updatedAt
        )
    }
}

struct ImagePullOutcome: Equatable, Sendable {
    let exitCode: Int32
    let observedImage: ImageSummary
    let matchedExpectation: Bool
}

func isValidImageReference(_ value: String) -> Bool {
    guard (1...512).contains(value.count) else { return false }
    return value.range(
        of: #"^[A-Za-z0-9][A-Za-z0-9._:/@-]*$"#,
        options: .regularExpression
    ) != nil
}

private func isValidImagePlatform(_ value: String) -> Bool {
    value.range(
        of: #"^linux/(arm64|amd64)(/[A-Za-z0-9._-]+)?$"#,
        options: .regularExpression
    ) != nil
}
