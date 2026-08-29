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
