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

struct ImageDeleteRequest: Codable, Equatable, Sendable {
    let reference: String
    let confirmationTarget: String

    func validated() throws -> Self {
        guard isValidImageReference(reference) else {
            throw ProblemDetail(
                code: .validationFailed,
                fieldErrors: ["reference": "镜像引用格式无效"]
            )
        }
        guard confirmationTarget == reference else {
            throw ProblemDetail(code: .confirmationMismatch)
        }
        return self
    }

    var safeRequestSummary: [String: JSONValue] {
        ["reference": .string(reference)]
    }
}

struct ImageDeleteOutcome: Equatable, Sendable {
    let exitCode: Int32
    let targetAbsent: Bool
    let observedAt: Date
}

func imageMatchesReference(_ image: ImageSummary, reference: String) -> Bool {
    if image.name == reference || image.id == reference || image.digest == reference {
        return true
    }
    if let digestSeparator = reference.lastIndex(of: "@"),
       String(reference[reference.index(after: digestSeparator)...]) == image.digest {
        return true
    }
    return normalizedImageReference(image.name) == normalizedImageReference(reference)
}

func isProtectedSystemImage(_ image: ImageSummary) -> Bool {
    let prefix = "ghcr.io/apple/containerization/vminit"
    return image.name == prefix
        || image.name.hasPrefix(prefix + ":")
        || image.name.hasPrefix(prefix + "@")
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

private func normalizedImageReference(_ value: String) -> String {
    guard !value.hasPrefix("sha256:") else { return value }
    guard value.contains("/") else { return "docker.io/library/\(value)" }
    let firstComponent = value.split(separator: "/", maxSplits: 1).first.map(String.init) ?? value
    if firstComponent.contains(".") || firstComponent.contains(":") || firstComponent == "localhost" {
        return value
    }
    return "docker.io/\(value)"
}
