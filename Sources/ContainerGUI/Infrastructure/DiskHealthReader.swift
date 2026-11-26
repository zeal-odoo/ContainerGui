import Foundation

struct DiskHealthReader: DiskHealthReading {
    let executor: any CommandExecuting
    let smartctlURL: URL?

    init(executor: any CommandExecuting, smartctlURL: URL? = DiskHealthReader.installedSmartctl()) {
        self.executor = executor
        self.smartctlURL = smartctlURL
    }

    static func installedSmartctl() -> URL? {
        ["/opt/homebrew/bin/smartctl", "/usr/local/bin/smartctl", "/opt/homebrew/sbin/smartctl", "/usr/local/sbin/smartctl"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }

    func read() async -> DiskHealthSnapshot {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        do {
            let inventory: Inventory = try await plist(["list", "-plist", "physical"], deadline: deadline)
            guard inventory.disks.count <= 128,
                  Set(inventory.disks.map(\.id)).count == inventory.disks.count,
                  inventory.disks.allSatisfy({ Self.validID($0.id, whole: true) }) else {
                throw CommandExecutionError.streamFailed
            }
            let apfs: APFSInventory? = try? await plist(["apfs", "list", "-plist"], deadline: deadline)
            var disks: [DiskHealth] = []
            // Bound both concurrent probes and total read time, including disconnected devices.
            for start in stride(from: 0, to: inventory.disks.count, by: 4) {
                let batch = inventory.disks[start..<min(start + 4, inventory.disks.count)]
                let results = await withTaskGroup(of: DiskHealth.self) { group in
                    for disk in batch { group.addTask { await readDisk(disk, apfs: apfs, deadline: deadline) } }
                    var results: [DiskHealth] = []
                    for await result in group { results.append(result) }
                    return results
                }
                disks.append(contentsOf: results)
            }
            let order = Dictionary(uniqueKeysWithValues: inventory.disks.enumerated().map { ($0.element.id, $0.offset) })
            disks.sort { order[$0.id, default: 0] < order[$1.id, default: 0] }
            return .init(disks: disks, observedAt: Date(), error: nil)
        } catch {
            return .init(disks: [], observedAt: Date(), error: "read_failed")
        }
    }

    private func readDisk(_ disk: Inventory.Entry, apfs: APFSInventory?, deadline: ContinuousClock.Instant) async -> DiskHealth {
        let info: DiskInfo? = try? await plist(["info", "-plist", disk.id], deadline: deadline)
        let validInfo = info.flatMap { $0.id == disk.id && $0.whole == true ? $0 : nil }
        var health: DiskHealthState = .unavailable
        var source: String?
        var powerOnHours: Int64?
        var hardware: SmartHardware?
        var reason: String? = validInfo == nil ? "read_failed" : "unsupported"
        switch validInfo?.smartStatus?.lowercased() {
        case "verified": health = .passed; source = "macos"; reason = nil
        case "failing": health = .failing; source = "macos"; reason = nil
        default: break
        }
        // Hardware counters do not require access to the volume's files.
        // A failed metadata query must not prevent an independent SMART read.
        if info == nil || validInfo != nil {
            if let smartctlURL {
                do {
                    let result = try await command(smartctlURL, ["-i", "-H", "-A", "-j", "/dev/\(disk.id)"], deadline: deadline)
                    powerOnHours = Self.smartPowerOnHours(result)
                    if (0...255).contains(result.exitCode), result.exitCode & 7 == 0 {
                        hardware = try? JSONDecoder().decode(SmartHardware.self, from: result.stdout)
                    }
                    let reportedHealth = Self.smartHealth(result)
                    if health == .unavailable || reportedHealth == .failing || (reportedHealth == .warning && health != .failing) {
                        health = reportedHealth
                        source = "smartctl"
                        reason = health == .unavailable ? "read_failed" : nil
                    }
                } catch { if health == .unavailable { reason = "read_failed" } }
            } else if health == .unavailable, validInfo != nil { reason = "tool_unavailable" }
        }

        let partitions = disk.partitions ?? []
        let storeIDs = Set([disk.id] + partitions.map(\.id))
        var spaces = (apfs?.containers ?? []).compactMap { container -> DiskSpace? in
            guard container.stores.contains(where: { storeIDs.contains($0.id) }) else { return nil }
            let names = container.volumes.filter {
                let roles = $0.roles ?? []
                return roles.isEmpty || roles.contains("System") || roles.contains("Data")
            }.compactMap(\.name)
            guard !names.isEmpty else { return nil }
            return .init(id: container.id, names: names, totalBytes: Self.bytes(container.capacity),
                         freeBytes: Self.freeBytes(container.free, total: container.capacity), shared: true)
        }
        // Non-APFS filesystems report volume free space on their own partition.
        for partition in partitions.prefix(128) where Self.validID(partition.id, whole: false) &&
            partition.content != "EFI" && !(partition.content ?? "").hasPrefix("Apple_APFS") {
            if let volume: DiskInfo = try? await plist(["info", "-plist", partition.id], deadline: deadline),
               volume.id == partition.id, let space = Self.volumeSpace(volume) { spaces.append(space) }
        }
        if partitions.isEmpty, let validInfo, let space = Self.volumeSpace(validInfo) { spaces.append(space) }
        return .init(id: disk.id, model: validInfo?.model ?? hardware?.model_name ?? disk.id, internalDisk: validInfo?.internalDisk,
                     solidState: validInfo?.solidState ?? hardware?.solidState, connection: validInfo?.connection,
                     capacityBytes: Self.bytes(validInfo?.size ?? disk.size), powerOnHours: powerOnHours, health: health,
                     source: source, reason: reason, spaces: spaces)
    }

    static func smartHealth(_ result: CommandResult) -> DiskHealthState {
        struct Report: Decodable {
            struct Health: Decodable { let passed: Bool }
            let smart_status: Health?
        }
        guard (0...255).contains(result.exitCode),
              let report = try? JSONDecoder().decode(Report.self, from: result.stdout) else { return .unavailable }
        // smartctl uses a bitmask: failing health is not an ordinary command error.
        if report.smart_status?.passed == false || result.exitCode & 8 != 0 { return .failing }
        if result.exitCode & 7 != 0 { return .unavailable }
        if result.exitCode & 0xf0 != 0 { return .warning }
        return report.smart_status?.passed == true ? .passed : .unavailable
    }

    static func smartPowerOnHours(_ result: CommandResult) -> Int64? {
        struct Report: Decodable {
            struct Time: Decodable { let hours: Int64? }
            let power_on_time: Time?
        }
        guard (0...255).contains(result.exitCode), result.exitCode & 7 == 0,
              let report = try? JSONDecoder().decode(Report.self, from: result.stdout),
              let hours = report.power_on_time?.hours,
              (0...9_007_199_254_740_991).contains(hours) else { return nil }
        // smartctl normalizes vendor-specific counters to hours for ATA, SCSI and NVMe.
        return hours
    }

    private static func validID(_ id: String, whole: Bool) -> Bool {
        id.range(of: whole ? #"^disk[0-9]+$"# : #"^disk[0-9]+(?:s[0-9]+)+$"#, options: .regularExpression) != nil
    }

    private static func bytes(_ value: Int64?) -> Int64? {
        value.flatMap { (0...9_007_199_254_740_991).contains($0) ? $0 : nil }
    }

    private static func freeBytes(_ value: Int64?, total: Int64?) -> Int64? {
        guard let value = bytes(value), let total = bytes(total), value <= total else { return nil }
        return value
    }

    private static func volumeSpace(_ volume: DiskInfo) -> DiskSpace? {
        guard let name = volume.volumeName, !name.isEmpty else { return nil }
        return .init(id: volume.id, names: [name], totalBytes: bytes(volume.volumeTotal),
                     freeBytes: freeBytes(volume.volumeFree, total: volume.volumeTotal), shared: false)
    }

    private func command(_ executable: URL, _ arguments: [String], deadline: ContinuousClock.Instant) async throws -> CommandResult {
        let remaining = ContinuousClock.now.duration(to: deadline)
        guard remaining > .zero, !Task.isCancelled else { throw CommandExecutionError.timedOut }
        // USB device discovery can make diskutil info take more than five seconds.
        let timeout: Duration = executable.lastPathComponent == "diskutil" && arguments.first == "info" ? .seconds(8) : .seconds(4)
        return try await executor.run(.init(executableURL: executable, arguments: arguments,
                                            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"],
                                            timeout: min(timeout, remaining), maximumOutputBytes: 2 * 1024 * 1024))
    }

    private func plist<Value: Decodable>(_ arguments: [String], deadline: ContinuousClock.Instant) async throws -> Value {
        let result = try await command(URL(fileURLWithPath: "/usr/sbin/diskutil"), arguments, deadline: deadline)
        guard result.exitCode == 0 else { throw CommandExecutionError.streamFailed }
        return try PropertyListDecoder().decode(Value.self, from: result.stdout)
    }

    private struct SmartHardware: Decodable {
        let model_name: String?
        let rotation_rate: Int?
        let device: Device?
        struct Device: Decodable {
            let storageProtocol: String?
            enum CodingKeys: String, CodingKey { case storageProtocol = "protocol" }
        }
        var solidState: Bool? {
            if device?.storageProtocol == "NVMe" { return true }
            return rotation_rate.flatMap { $0 >= 0 ? $0 == 0 : nil }
        }
    }

    private struct Inventory: Decodable, Sendable {
        let disks: [Entry]
        enum CodingKeys: String, CodingKey { case disks = "AllDisksAndPartitions" }
        struct Entry: Decodable, Sendable {
            let id: String
            let size: Int64?
            let partitions: [Partition]?
            enum CodingKeys: String, CodingKey { case id = "DeviceIdentifier", size = "Size", partitions = "Partitions" }
        }
        struct Partition: Decodable, Sendable {
            let id: String
            let content: String?
            enum CodingKeys: String, CodingKey { case id = "DeviceIdentifier", content = "Content" }
        }
    }

    private struct DiskInfo: Decodable, Sendable {
        let id: String
        let whole: Bool?
        let model: String?
        let size: Int64?
        let internalDisk: Bool?
        let solidState: Bool?
        let connection: String?
        let smartStatus: String?
        let volumeName: String?
        let volumeTotal: Int64?
        let volumeFree: Int64?
        enum CodingKeys: String, CodingKey {
            case id = "DeviceIdentifier", whole = "WholeDisk", model = "MediaName", size = "TotalSize"
            case internalDisk = "Internal", solidState = "SolidState", connection = "BusProtocol", smartStatus = "SMARTStatus"
            case volumeName = "VolumeName", volumeTotal = "VolumeTotalSpace", volumeFree = "VolumeFreeSpace"
        }
    }

    private struct APFSInventory: Decodable, Sendable {
        let containers: [Container]
        enum CodingKeys: String, CodingKey { case containers = "Containers" }
        struct Container: Decodable, Sendable {
            let id: String
            let capacity: Int64?
            let free: Int64?
            let stores: [Store]
            let volumes: [Volume]
            enum CodingKeys: String, CodingKey {
                case id = "ContainerReference", capacity = "CapacityCeiling", free = "CapacityFree"
                case stores = "PhysicalStores", volumes = "Volumes"
            }
        }
        struct Store: Decodable, Sendable {
            let id: String
            enum CodingKeys: String, CodingKey { case id = "DeviceIdentifier" }
        }
        struct Volume: Decodable, Sendable {
            let name: String?
            let roles: [String]?
            enum CodingKeys: String, CodingKey { case name = "Name", roles = "Roles" }
        }
    }
}
