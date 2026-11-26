import Foundation

enum DiskHealthState: String, Codable, Sendable {
    case passed, failing, warning, unavailable
}

struct DiskSpace: Codable, Sendable {
    let id: String
    let names: [String]
    let totalBytes: Int64?
    let freeBytes: Int64?
    let shared: Bool
}

struct DiskHealth: Codable, Sendable {
    let id: String
    let model: String
    let internalDisk: Bool?
    let solidState: Bool?
    let connection: String?
    let capacityBytes: Int64?
    let powerOnHours: Int64?
    let health: DiskHealthState
    let source: String?
    let reason: String?
    let spaces: [DiskSpace]
}

struct DiskHealthSnapshot: Codable, Sendable {
    let disks: [DiskHealth]
    let observedAt: Date
    let error: String?
}

protocol DiskHealthReading: Sendable {
    func read() async -> DiskHealthSnapshot
}

actor DiskHealthService {
    private let reader: any DiskHealthReading
    private var cached: DiskHealthSnapshot?
    private var inFlight: Task<DiskHealthSnapshot, Never>?

    init(reader: any DiskHealthReading) { self.reader = reader }

    func snapshot() async -> DiskHealthSnapshot {
        if let inFlight { return await inFlight.value }
        if let cached, (0..<2).contains(Date().timeIntervalSince(cached.observedAt)) { return cached }
        let task = Task { await reader.read() }
        inFlight = task
        let result = await task.value
        cached = result
        inFlight = nil
        return result
    }
}
