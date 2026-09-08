import Foundation

struct ANEEnergyChannel: Sendable {
    let name: String
    let unit: String
    let value: Int64

    static func isANEName(_ name: String) -> Bool {
        name.hasPrefix("ANE") && name.utf8.dropFirst(3).allSatisfy { (48...57).contains($0) }
    }

    var joulesPerUnit: Double? {
        switch unit {
        case "J": 1
        case "mJ": 0.001
        case "uJ": 0.000_001
        case "nJ": 0.000_000_001
        default: nil
        }
    }

    static func validate(_ channels: [Self]) throws {
        guard !channels.isEmpty else { throw ANEPowerFailure.unsupported }
        guard channels.count <= 16,
              Set(channels.map(\.name)).count == channels.count,
              channels.count == 1 || !channels.contains(where: { $0.name == "ANE" }),
              channels.allSatisfy({ isANEName($0.name) && $0.value >= 0 }) else {
            throw ANEPowerFailure.invalidSample
        }
        guard channels.allSatisfy({ $0.joulesPerUnit != nil }) else { throw ANEPowerFailure.unsupported }
    }
}

protocol ANEEnergyReading: Sendable {
    func read() throws -> [ANEEnergyChannel]
}

enum ANEPowerFailure: String, Error, Encodable {
    case unsupported
    case readFailed = "read_failed"
    case invalidSample = "invalid_sample"
}

struct ANEPowerSnapshot: Encodable, Sendable {
    enum State: String, Encodable {
        case sampling, ready, unavailable
    }

    let state: State
    let watts: Double?
    let observedAt: Date
    let sampleSeconds: Double?
    let reason: ANEPowerFailure?

    private enum CodingKeys: String, CodingKey {
        case state, watts, observedAt, sampleSeconds, reason, scope, estimated, utilizationPercent, utilizationState
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(watts, forKey: .watts)
        try container.encode(observedAt, forKey: .observedAt)
        try container.encode(sampleSeconds, forKey: .sampleSeconds)
        try container.encode(reason, forKey: .reason)
        try container.encode("host", forKey: .scope)
        try container.encode(true, forKey: .estimated)
        try container.encodeNil(forKey: .utilizationPercent)
        try container.encode("unavailable", forKey: .utilizationState)
    }
}

actor ANEPowerSampler {
    private let reader: any ANEEnergyReading
    private let monotonicNow: @Sendable () -> Double
    private let observedAt: @Sendable () -> Date
    private var baseline: (time: Double, channels: [ANEEnergyChannel])?
    private var cached: (time: Double, snapshot: ANEPowerSnapshot)?

    init(
        reader: any ANEEnergyReading,
        monotonicNow: (@Sendable () -> Double)? = nil,
        observedAt: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.reader = reader
        let clock = ContinuousClock()
        let origin = clock.now
        self.monotonicNow = monotonicNow ?? {
            let duration = origin.duration(to: clock.now).components
            return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        }
        self.observedAt = observedAt
    }

    func snapshot() -> ANEPowerSnapshot {
        let time = monotonicNow()
        guard time.isFinite, time >= 0, cached.map({ time >= $0.time }) ?? true else {
            baseline = nil
            cached = nil
            return unavailable(.invalidSample)
        }
        if let cached, time - cached.time < 1 { return cached.snapshot }

        // Keep the actor non-reentrant. Timestamp the completed read, not lazy subscription setup.
        let reading = Result { try reader.read() }
        let sampleTime = monotonicNow()
        guard sampleTime.isFinite, sampleTime >= time else {
            baseline = nil
            cached = nil
            return unavailable(.invalidSample)
        }
        let snapshot: ANEPowerSnapshot
        do {
            let channels = try reading.get().sorted { $0.name < $1.name }
            try ANEEnergyChannel.validate(channels)
            if let baseline, sampleTime - baseline.time <= 15 {
                let seconds = sampleTime - baseline.time
                guard seconds.isFinite, seconds > 0, channels.count == baseline.channels.count else {
                    throw ANEPowerFailure.invalidSample
                }
                var joules: Double = 0
                for (previous, current) in zip(baseline.channels, channels) {
                    guard current.name == previous.name, current.unit == previous.unit,
                          current.value >= previous.value, let scale = current.joulesPerUnit else {
                        throw ANEPowerFailure.invalidSample
                    }
                    // Both values are nonnegative, so this subtraction cannot overflow Int64.
                    joules += Double(current.value - previous.value) * scale
                }
                let watts = joules / seconds
                guard watts.isFinite, watts >= 0 else { throw ANEPowerFailure.invalidSample }
                snapshot = .init(state: .ready, watts: watts, observedAt: observedAt(), sampleSeconds: seconds, reason: nil)
            } else {
                snapshot = .init(state: .sampling, watts: nil, observedAt: observedAt(), sampleSeconds: nil, reason: nil)
            }
            baseline = (sampleTime, channels)
        } catch {
            baseline = nil
            snapshot = unavailable((error as? ANEPowerFailure) ?? .readFailed)
        }
        cached = (sampleTime, snapshot)
        return snapshot
    }

    private func unavailable(_ reason: ANEPowerFailure) -> ANEPowerSnapshot {
        .init(state: .unavailable, watts: nil, observedAt: observedAt(), sampleSeconds: nil, reason: reason)
    }
}
