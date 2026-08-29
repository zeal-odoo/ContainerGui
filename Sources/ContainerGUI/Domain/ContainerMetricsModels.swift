import Foundation

struct ContainerResourceSample: Equatable, Sendable {
    let containerID: String
    let cpuUsageUsec: UInt64
    let memoryUsageBytes: UInt64
    let memoryLimitBytes: UInt64
    let observedAt: Date
}

struct ContainerResourceSampleBatch: Equatable, Sendable {
    let samples: [ContainerResourceSample]
    let observedAt: Date
}

enum CPUUsageState: String, Codable, Equatable, Sendable {
    case sampling
    case ready
}

enum ContainerRootFilesystemState: String, Codable, Equatable, Sendable {
    case ready
    case unavailable
}

struct ContainerRootFilesystemUsage: Codable, Equatable, Sendable {
    let state: ContainerRootFilesystemState
    let usedBytes: UInt64?
    let capacityBytes: UInt64?
    let availableBytes: UInt64?
    let usagePercent: Double?

    static let unavailable = ContainerRootFilesystemUsage(
        state: .unavailable,
        usedBytes: nil,
        capacityBytes: nil,
        availableBytes: nil,
        usagePercent: nil
    )

    enum CodingKeys: String, CodingKey {
        case state, usedBytes, capacityBytes, availableBytes, usagePercent
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(usedBytes, forKey: .usedBytes)
        try container.encode(capacityBytes, forKey: .capacityBytes)
        try container.encode(availableBytes, forKey: .availableBytes)
        try container.encode(usagePercent, forKey: .usagePercent)
    }
}

struct ContainerResourceUsage: Codable, Equatable, Sendable {
    let containerID: String
    let cpuPercent: Double?
    let cpuState: CPUUsageState
    let memoryUsageBytes: UInt64
    let memoryLimitBytes: UInt64
    let memoryPercent: Double?
    let rootFilesystem: ContainerRootFilesystemUsage
    let observedAt: Date

    enum CodingKeys: String, CodingKey {
        case cpuPercent, cpuState, memoryUsageBytes, memoryLimitBytes, memoryPercent, rootFilesystem, observedAt
        case containerID = "containerId"
    }

    init(
        containerID: String,
        cpuPercent: Double?,
        cpuState: CPUUsageState,
        memoryUsageBytes: UInt64,
        memoryLimitBytes: UInt64,
        memoryPercent: Double?,
        rootFilesystem: ContainerRootFilesystemUsage = .unavailable,
        observedAt: Date
    ) {
        self.containerID = containerID
        self.cpuPercent = cpuPercent
        self.cpuState = cpuState
        self.memoryUsageBytes = memoryUsageBytes
        self.memoryLimitBytes = memoryLimitBytes
        self.memoryPercent = memoryPercent
        self.rootFilesystem = rootFilesystem
        self.observedAt = observedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        containerID = try container.decode(String.self, forKey: .containerID)
        cpuPercent = try container.decodeIfPresent(Double.self, forKey: .cpuPercent)
        cpuState = try container.decode(CPUUsageState.self, forKey: .cpuState)
        memoryUsageBytes = try container.decode(UInt64.self, forKey: .memoryUsageBytes)
        memoryLimitBytes = try container.decode(UInt64.self, forKey: .memoryLimitBytes)
        memoryPercent = try container.decodeIfPresent(Double.self, forKey: .memoryPercent)
        rootFilesystem = try container.decodeIfPresent(
            ContainerRootFilesystemUsage.self,
            forKey: .rootFilesystem
        ) ?? .unavailable
        observedAt = try container.decode(Date.self, forKey: .observedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(containerID, forKey: .containerID)
        if let cpuPercent {
            try container.encode(cpuPercent, forKey: .cpuPercent)
        } else {
            try container.encodeNil(forKey: .cpuPercent)
        }
        try container.encode(cpuState, forKey: .cpuState)
        try container.encode(memoryUsageBytes, forKey: .memoryUsageBytes)
        try container.encode(memoryLimitBytes, forKey: .memoryLimitBytes)
        if let memoryPercent {
            try container.encode(memoryPercent, forKey: .memoryPercent)
        } else {
            try container.encodeNil(forKey: .memoryPercent)
        }
        try container.encode(rootFilesystem, forKey: .rootFilesystem)
        try container.encode(observedAt, forKey: .observedAt)
    }
}

struct ContainerMetricsSnapshot: Codable, Equatable, Sendable {
    let items: [ContainerResourceUsage]
    let observedAt: Date
}

actor ContainerMetricsSampler {
    private struct Computation: Sendable {
        let snapshot: ContainerMetricsSnapshot
        let currentByID: [String: ContainerResourceSample]
    }

    private var previousByID: [String: ContainerResourceSample] = [:]
    private var inFlight: (id: UInt64, task: Task<Computation, Error>)?
    private var nextID: UInt64 = 0

    func snapshot(
        load: @escaping @Sendable () async throws -> ContainerResourceSampleBatch
    ) async throws -> ContainerMetricsSnapshot {
        if let inFlight {
            return try await inFlight.task.value.snapshot
        }

        nextID += 1
        let requestID = nextID
        let previousByID = self.previousByID
        let task = Task {
            let batch = try await load()
            return Self.compute(batch: batch, previousByID: previousByID)
        }
        inFlight = (requestID, task)

        do {
            let computation = try await task.value
            if inFlight?.id == requestID {
                self.previousByID = computation.currentByID
                inFlight = nil
            }
            return computation.snapshot
        } catch {
            if inFlight?.id == requestID {
                inFlight = nil
            }
            throw error
        }
    }

    private static func compute(
        batch: ContainerResourceSampleBatch,
        previousByID: [String: ContainerResourceSample]
    ) -> Computation {
        let items = batch.samples.map { sample in
            let cpuPercent = calculateCPUPercent(
                current: sample,
                previous: previousByID[sample.containerID]
            )
            let memoryPercent: Double?
            if sample.memoryLimitBytes > 0 {
                let value = Double(sample.memoryUsageBytes) / Double(sample.memoryLimitBytes) * 100
                memoryPercent = value.isFinite && value >= 0 ? value : nil
            } else {
                memoryPercent = nil
            }
            return ContainerResourceUsage(
                containerID: sample.containerID,
                cpuPercent: cpuPercent,
                cpuState: cpuPercent == nil ? .sampling : .ready,
                memoryUsageBytes: sample.memoryUsageBytes,
                memoryLimitBytes: sample.memoryLimitBytes,
                memoryPercent: memoryPercent,
                observedAt: sample.observedAt
            )
        }
        return Computation(
            snapshot: ContainerMetricsSnapshot(items: items, observedAt: batch.observedAt),
            currentByID: Dictionary(uniqueKeysWithValues: batch.samples.map { ($0.containerID, $0) })
        )
    }

    private static func calculateCPUPercent(
        current: ContainerResourceSample,
        previous: ContainerResourceSample?
    ) -> Double? {
        guard let previous,
              current.cpuUsageUsec >= previous.cpuUsageUsec else {
            return nil
        }
        let elapsedUsec = current.observedAt.timeIntervalSince(previous.observedAt) * 1_000_000
        guard elapsedUsec > 0 else { return nil }
        let cpuUsec = Double(current.cpuUsageUsec - previous.cpuUsageUsec)
        let value = cpuUsec / elapsedUsec * 100
        return value.isFinite && value >= 0 ? value : nil
    }
}
