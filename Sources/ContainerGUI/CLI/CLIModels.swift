import Foundation

enum ContainerCLIError: Error, Equatable, Sendable {
    case unavailable(CLICompatibility)
    case nonZeroExit(Int32)
    case invalidOutput
    case targetNotFound
    case invalidIdentifier
}

struct ContainerControlOutcome: Equatable, Sendable {
    let exitCode: Int32
    let observedContainer: ContainerSummary
    let matchedExpectation: Bool
}

struct ContainerDeleteOutcome: Equatable, Sendable {
    let exitCode: Int32
    let targetAbsent: Bool
    let observedAt: Date
}

enum CLIOutputParser {
    private struct RawImage: Decodable {
        struct Configuration: Decodable {
            struct Descriptor: Decodable {
                let digest: String
            }

            let descriptor: Descriptor
            let name: String
        }

        struct Variant: Decodable {
            struct Platform: Decodable {
                let architecture: String
                let os: String
                let variant: String?
            }

            let platform: Platform
            let size: UInt64
        }

        let configuration: Configuration
        let id: String
        let variants: [Variant]
    }

    private struct RawContainerResourceSample: Decodable {
        let id: String
        let cpuUsageUsec: UInt64
        let memoryUsageBytes: UInt64
        let memoryLimitBytes: UInt64
    }

    static func parseSystemHealth(
        data: Data,
        installation: CLIInstallation,
        observedAt: Date = Date()
    ) throws -> SystemHealth {
        let root = try JSONDecoder.containerGUI.decode(JSONValue.self, from: data)
        guard let object = root.objectValue,
              let rawStatus = object["status"]?.stringValue else {
            throw ContainerCLIError.invalidOutput
        }
        let normalized = rawStatus.lowercased()
        let serviceState: SystemServiceState
        if normalized == "running" || normalized.contains("healthy") {
            serviceState = .healthy
        } else if normalized.contains("not registered") || normalized.contains("unregistered") {
            serviceState = .unregistered
        } else if normalized == "stopped" || normalized.contains("not running") {
            serviceState = .stopped
        } else if normalized.contains("degraded") || normalized.contains("error") {
            serviceState = .degraded
        } else {
            serviceState = .unknown
        }
        return SystemHealth(
            tool: installation,
            serviceState: serviceState,
            apiServerVersion: object["apiServerVersion"]?.stringValue,
            apiServerBuild: object["apiServerBuild"]?.stringValue,
            apiServerCommit: object["apiServerCommit"]?.stringValue,
            diagnosticCode: nil,
            diagnosticMessage: nil,
            observedAt: observedAt
        )
    }

    static func parseContainerList(data: Data, observedAt: Date = Date()) throws -> ContainerList {
        let root = try JSONDecoder.containerGUI.decode(JSONValue.self, from: data)
        guard let items = root.arrayValue else { throw ContainerCLIError.invalidOutput }
        return ContainerList(
            items: try items.map { try summary(from: $0, observedAt: observedAt) },
            observedAt: observedAt
        )
    }

    static func parseContainerDetail(
        data: Data,
        expectedID: String,
        observedAt: Date = Date()
    ) throws -> ContainerDetail {
        let root = try JSONDecoder.containerGUI.decode(JSONValue.self, from: data)
        let candidates = root.arrayValue ?? [root]
        guard let raw = candidates.first(where: { value in
            value.objectValue?["id"]?.stringValue == expectedID
        }), let object = raw.objectValue else {
            throw ContainerCLIError.targetNotFound
        }
        let summary = try summary(from: raw, observedAt: observedAt)
        let configuration = object["configuration"] ?? .object([:])
        let status = object["status"] ?? .object([:])
        return ContainerDetail(
            summary: summary,
            configuration: configuration.redacted(),
            status: status.redacted(),
            raw: raw.redacted(),
            observedAt: observedAt
        )
    }

    static func parseContainerResourceSamples(
        data: Data,
        observedAt: Date = Date()
    ) throws -> ContainerResourceSampleBatch {
        let rawSamples = try JSONDecoder.containerGUI.decode([RawContainerResourceSample].self, from: data)
        let identifiers = rawSamples.map(\.id)
        guard identifiers.allSatisfy({ !$0.isEmpty }),
              Set(identifiers).count == identifiers.count else {
            throw ContainerCLIError.invalidOutput
        }
        return ContainerResourceSampleBatch(
            samples: rawSamples.map { raw in
                ContainerResourceSample(
                    containerID: raw.id,
                    cpuUsageUsec: raw.cpuUsageUsec,
                    memoryUsageBytes: raw.memoryUsageBytes,
                    memoryLimitBytes: raw.memoryLimitBytes,
                    observedAt: observedAt
                )
            },
            observedAt: observedAt
        )
    }

    static func parseImageList(data: Data, observedAt: Date = Date()) throws -> ImageList {
        let rawImages = try JSONDecoder.containerGUI.decode([RawImage].self, from: data)
        guard rawImages.count <= 1_000 else { throw ContainerCLIError.invalidOutput }
        let images = try rawImages.map { raw in
            try imageSummary(from: raw, observedAt: observedAt)
        }
        guard Set(images.map(\.id)).count == images.count,
              Set(images.map(\.name)).count == images.count else {
            throw ContainerCLIError.invalidOutput
        }
        return ImageList(items: images, observedAt: observedAt)
    }

    static func parseImageInspect(data: Data, observedAt: Date = Date()) throws -> ImageSummary {
        let list = try parseImageList(data: data, observedAt: observedAt)
        guard list.items.count == 1, let image = list.items.first else {
            throw ContainerCLIError.invalidOutput
        }
        return image
    }

    static func parseImagePullProgress(
        line: String,
        observedAt: Date = Date()
    ) -> ImagePullProgress? {
        guard let stage = regexCaptures(
            #"^\[(\d+)\/(\d+)\]\s+(.*?)\s+\[[^\]]+\]\s*$"#,
            in: line
        ), stage.count == 3,
              let stageNumber = Int(stage[0]),
              let stageCount = Int(stage[1]),
              stageNumber > 0, stageNumber <= stageCount else {
            return nil
        }

        let body = stage[2]
        let phase: ImagePullProgressPhase
        if body.hasPrefix("Fetching image") {
            phase = .fetching
        } else if body.hasPrefix("Unpacking image") {
            phase = .unpacking
        } else {
            return nil
        }

        let unitCaptures = regexCaptures(#"\((\d+)\s+of\s+(\d+)\s+blobs(?:,|\))"#, in: body)
        let completedUnits = unitCaptures?.first.flatMap(Int.init)
        let totalUnits = unitCaptures?.dropFirst().first.flatMap(Int.init)
        let explicitPercent = regexCaptures(#"(?:^|\s)(\d{1,3})%"#, in: body)?
            .first.flatMap(Int.init).map { min($0, 100) }
        let phaseFraction: Double
        if let explicitPercent {
            phaseFraction = Double(explicitPercent) / 100
        } else if let completedUnits, let totalUnits, totalUnits > 0 {
            phaseFraction = min(Double(completedUnits) / Double(totalUnits), 1)
        } else {
            phaseFraction = 0
        }
        let overall = Int((
            (Double(stageNumber - 1) + phaseFraction) / Double(stageCount) * 100
        ).rounded())
        return ImagePullProgress(
            phase: phase,
            percentComplete: overall,
            completedUnits: completedUnits,
            totalUnits: totalUnits,
            updatedAt: observedAt
        )
    }

    private static func summary(from value: JSONValue, observedAt: Date) throws -> ContainerSummary {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue,
              !id.isEmpty else {
            throw ContainerCLIError.invalidOutput
        }
        let configuration = object["configuration"]?.objectValue ?? [:]
        let status = object["status"]?.objectValue ?? [:]
        let image = configuration["image"]?.objectValue
        let rawState = status["state"]?.stringValue
        let network = status["networks"]?.arrayValue?.first?.objectValue
        return ContainerSummary(
            id: id,
            displayName: configuration["id"]?.stringValue ?? id,
            imageReference: image?["reference"]?.stringValue,
            state: ContainerState.normalize(rawState),
            rawState: rawState,
            ipv4Address: network?["ipv4Address"]?.stringValue,
            ipv6Address: network?["ipv6Address"]?.stringValue,
            createdAt: configuration["creationDate"]?.stringValue.flatMap(parseDate),
            observedAt: observedAt
        )
    }

    private static func imageSummary(from raw: RawImage, observedAt: Date) throws -> ImageSummary {
        let digestPattern = #"^sha256:[0-9a-f]{64}$"#
        guard !raw.id.isEmpty,
              !raw.configuration.name.isEmpty,
              raw.configuration.descriptor.digest.range(
                of: digestPattern,
                options: .regularExpression
              ) != nil else {
            throw ContainerCLIError.invalidOutput
        }
        var sizeBytes: UInt64 = 0
        for variant in raw.variants {
            let (sum, overflow) = sizeBytes.addingReportingOverflow(variant.size)
            guard !overflow else { throw ContainerCLIError.invalidOutput }
            sizeBytes = sum
        }
        let parsedPlatforms = raw.variants.compactMap { variant -> ImagePlatform? in
            guard variant.platform.os == "linux",
                  variant.platform.architecture == "arm64" || variant.platform.architecture == "amd64" else {
                return nil
            }
            return ImagePlatform(
                os: variant.platform.os,
                architecture: variant.platform.architecture,
                variant: variant.platform.variant
            )
        }
        var seenPlatforms = Set<ImagePlatform>()
        let platforms = parsedPlatforms.filter { seenPlatforms.insert($0).inserted }
        return ImageSummary(
            id: raw.id,
            name: raw.configuration.name,
            digest: raw.configuration.descriptor.digest,
            platforms: platforms,
            sizeBytes: sizeBytes,
            observedAt: observedAt
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

private func regexCaptures(_ pattern: String, in value: String) -> [String]? {
    guard let expression = try? NSRegularExpression(pattern: pattern),
          let match = expression.firstMatch(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value)
          ) else {
        return nil
    }
    return (1..<match.numberOfRanges).compactMap { index in
        guard let range = Range(match.range(at: index), in: value) else { return nil }
        return String(value[range])
    }
}
