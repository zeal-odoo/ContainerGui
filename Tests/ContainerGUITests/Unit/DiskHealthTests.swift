import Foundation
import XCTest

@testable import ContainerGUI

final class DiskHealthTests: XCTestCase {
    func testPhysicalInventoryNativeAndUSBHealthWithSharedAPFSSpace() async throws {
        let executor = DiskFixtureExecutor(replies: try replies())
        let reader = DiskHealthReader(executor: executor, smartctlURL: URL(fileURLWithPath: "/opt/homebrew/bin/smartctl"))
        let result = await reader.read()
        XCTAssertNil(result.error)
        XCTAssertEqual(result.disks.map(\.id), ["disk0", "disk6"])
        XCTAssertEqual(result.disks.map(\.health), [.passed, .passed])
        XCTAssertEqual(result.disks.map(\.source), ["macos", "smartctl"])
        XCTAssertEqual(result.disks.map(\.powerOnHours), [2488, 37877])
        XCTAssertEqual(result.disks[0].spaces.count, 1)
        XCTAssertEqual(result.disks[0].spaces[0].names, ["Macintosh HD", "Data"])
        XCTAssertEqual(result.disks[0].spaces[0].freeBytes, 400)
        XCTAssertTrue(result.disks[0].spaces[0].shared)
        XCTAssertEqual(result.disks[1].spaces[0].freeBytes, 50)
        let requests = await executor.requests
        XCTAssertEqual(Set(requests.filter { $0.executableURL.lastPathComponent == "smartctl" }.map { $0.arguments.joined(separator: " ") }), ["-i -H -A -j /dev/disk0", "-i -H -A -j /dev/disk6"])
        XCTAssertTrue(requests.allSatisfy { $0.timeout <= ($0.arguments.first == "info" ? .seconds(8) : .seconds(4)) && $0.maximumOutputBytes == 2 * 1024 * 1024 })
        let json = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        XCTAssertFalse(json.contains("private-serial"))
        XCTAssertFalse(json.contains("private-uuid"))
    }

    func testFailingWarningAndInvalidSmartOutputsDoNotBecomeHealthy() {
        for (json, code, state) in [
            (#"{"smart_status":{"passed":true}}"#, 0, DiskHealthState.passed),
            (#"{"smart_status":{"passed":false}}"#, 8, .failing),
            (#"{"smart_status":{"passed":false}}"#, 12, .failing),
            (#"{"smart_status":{"passed":true}}"#, 8, .failing),
            (#"{"smart_status":{"passed":true}}"#, 64, .warning),
            (#"{"smart_status":{"passed":true}}"#, 2, .unavailable),
            (#"{"smart_status":{"passed":true}}"#, 4, .unavailable),
            (#"{"smart_status":{"passed":true}}"#, 256, .unavailable),
            (#"{"smart_status":{"passed":"true"}}"#, 0, .unavailable),
            (#"{}"#, 0, .unavailable), ("broken", 8, .unavailable)
        ] {
            XCTAssertEqual(DiskHealthReader.smartHealth(.init(stdout: Data(json.utf8), stderr: Data(), exitCode: Int32(code), duration: .zero)), state)
        }
    }

    func testUnsupportedDisksRemainVisibleWhenOptionalToolIsMissing() async throws {
        let reader = DiskHealthReader(executor: DiskFixtureExecutor(replies: try replies()), smartctlURL: nil)
        let result = await reader.read()
        XCTAssertEqual(result.disks.count, 2)
        XCTAssertEqual(result.disks[1].health, .unavailable)
        XCTAssertEqual(result.disks[1].reason, "tool_unavailable")
        XCTAssertTrue(result.disks.allSatisfy { $0.powerOnHours == nil })
    }

    func testPowerOnHoursUseNormalizedUnitsAndRejectInvalidOrFailedReadings() {
        let cases: [(String, Int32, Int64?)] = [
            (#"{"power_on_time":{"hours":0}}"#, 0, 0),
            (#"{"power_on_time":{"hours":29808,"minutes":59}}"#, 0, 29808),
            (#"{"power_on_time":{"hours":37877},"ata_smart_attributes":{"table":[{"id":9,"raw":{"value":2272620}}]}}"#, 0, 37877),
            (#"{"power_on_time":{"hours":2488},"nvme_smart_health_information_log":{"power_on_hours":2488}}"#, 0, 2488),
            (#"{"power_on_time":{"hours":24}}"#, 8, 24),
            (#"{"power_on_time":{"hours":24}}"#, 32, 24),
            (#"{"power_on_time":{"hours":24}}"#, 1, nil),
            (#"{"power_on_time":{"hours":24}}"#, 2, nil),
            (#"{"power_on_time":{"hours":24}}"#, 4, nil),
            (#"{"power_on_time":{"hours":24}}"#, 256, nil),
            (#"{"power_on_time":{"hours":-1}}"#, 0, nil),
            (#"{"power_on_time":{"hours":1.5}}"#, 0, nil),
            (#"{"power_on_time":{"hours":"24"}}"#, 0, nil),
            (#"{"power_on_time":{"hours":true}}"#, 0, nil),
            (#"{"power_on_time":{"hours":9007199254740992}}"#, 0, nil),
            (#"{"power_on_time":{"hours":9223372036854775808}}"#, 0, nil),
            (#"{"power_on_time":{"hours":null}}"#, 0, nil),
            (#"{"ata_smart_attributes":{"table":[{"id":9,"raw":{"value":24}}]}}"#, 0, nil),
            ("{}", 0, nil), ("broken", 0, nil)
        ]
        for (json, code, expected) in cases {
            XCTAssertEqual(DiskHealthReader.smartPowerOnHours(.init(stdout: Data(json.utf8), stderr: Data(), exitCode: code, duration: .zero)), expected, json)
        }
    }

    func testTimeReadFailurePreservesNativeHealthAndNewAlertsCannotBeHidden() async throws {
        for (native, report, code, expected) in [
            ("Verified", "missing", Int32(0), DiskHealthState.passed),
            ("Verified", #"{"smart_status":{"passed":true},"power_on_time":{"hours":"bad"}}"#, 0, .passed),
            ("Verified", #"{"smart_status":{"passed":false}}"#, 8, .failing),
            ("Verified", #"{"smart_status":{"passed":true}}"#, 32, .warning),
            ("Failing", #"{"smart_status":{"passed":true}}"#, 0, .failing)
        ] {
            var fixtures = try replies()
            fixtures["info -plist disk0"] = try plist(["DeviceIdentifier": "disk0", "WholeDisk": true, "SMARTStatus": native])
            fixtures["-i -H -A -j /dev/disk0"] = report == "missing" ? nil : .init(stdout: Data(report.utf8), stderr: Data(), exitCode: code, duration: .zero)
            let result = await DiskHealthReader(executor: DiskFixtureExecutor(replies: fixtures), smartctlURL: URL(fileURLWithPath: "/opt/homebrew/bin/smartctl")).read()
            XCTAssertEqual(result.disks[0].health, expected)
            XCTAssertNil(result.disks[0].powerOnHours)
        }
    }

    func testOneDisconnectedDiskDoesNotHideOthersAndAPFSFailureDoesNotInventFreeSpace() async throws {
        var fixtures = try replies()
        fixtures.removeValue(forKey: "info -plist disk6")
        fixtures.removeValue(forKey: "apfs list -plist")
        let result = await DiskHealthReader(executor: DiskFixtureExecutor(replies: fixtures), smartctlURL: nil).read()
        XCTAssertNil(result.error)
        XCTAssertEqual(result.disks.count, 2)
        XCTAssertEqual(result.disks[0].health, .passed)
        XCTAssertTrue(result.disks[0].spaces.isEmpty)
        XCTAssertEqual(result.disks[1].health, .unavailable)
        XCTAssertEqual(result.disks[1].reason, "read_failed")
    }

    func testInvalidOrDuplicatePhysicalIdentifiersFailBeforeAnyProbe() async throws {
        for ids in [["disk0", "disk0"], ["../disk0"], ["disk0s2"], ["disk0;reboot"]] {
            let executor = DiskFixtureExecutor(replies: ["list -plist physical": try plist(["AllDisksAndPartitions": ids.map { ["DeviceIdentifier": $0] }])])
            let result = await DiskHealthReader(executor: executor, smartctlURL: nil).read()
            XCTAssertEqual(result.error, "read_failed")
            XCTAssertTrue(result.disks.isEmpty)
            let count = await executor.requests.count
            XCTAssertEqual(count, 1)
        }
    }

    func testFailedInventoryIsUnavailableAndEmptyInventoryIsValid() async throws {
        let failed = await DiskHealthReader(executor: DiskFixtureExecutor(replies: [:]), smartctlURL: nil).read()
        XCTAssertEqual(failed.error, "read_failed")
        let empty = await DiskHealthReader(executor: DiskFixtureExecutor(replies: ["list -plist physical": try plist(["AllDisksAndPartitions": []])]), smartctlURL: nil).read()
        XCTAssertNil(empty.error)
        XCTAssertTrue(empty.disks.isEmpty)
    }

    func testNativeFailureIdentityMismatchAndInvalidVolumeCapacity() async throws {
        var fixtures = try replies()
        fixtures["info -plist disk0"] = try plist(["DeviceIdentifier": "disk0", "WholeDisk": true, "SMARTStatus": "Failing"])
        fixtures["info -plist disk6"] = try plist(["DeviceIdentifier": "disk8", "WholeDisk": true, "SMARTStatus": "Verified"])
        let result = await DiskHealthReader(executor: DiskFixtureExecutor(replies: fixtures), smartctlURL: nil).read()
        XCTAssertEqual(result.disks.map(\.health), [.failing, .unavailable])

        fixtures = try replies()
        fixtures["list -plist physical"] = try plist(["AllDisksAndPartitions": [["DeviceIdentifier": "disk6", "Partitions": [["DeviceIdentifier": "disk6s1", "Content": "Microsoft Basic Data"]]]]])
        fixtures["info -plist disk6s1"] = try plist(["DeviceIdentifier": "disk6s1", "VolumeName": "External", "VolumeTotalSpace": 100, "VolumeFreeSpace": 101])
        let volume = await DiskHealthReader(executor: DiskFixtureExecutor(replies: fixtures), smartctlURL: nil).read()
        XCTAssertNil(volume.disks[0].spaces[0].freeBytes)
        XCTAssertFalse(volume.disks[0].spaces[0].shared)
    }

    func testConcurrentReadsCoalesceAndShortCacheAvoidsRepeatedProbes() async {
        let fixture = CountingDiskReader()
        let service = DiskHealthService(reader: fixture)
        async let first = service.snapshot()
        async let second = service.snapshot()
        _ = await (first, second)
        _ = await service.snapshot()
        let count = await fixture.count
        XCTAssertEqual(count, 1)
    }

    func testHardwareTimeRemainsReadableWhenVolumeMetadataIsUnavailable() async throws {
        var fixtures = try replies()
        fixtures.removeValue(forKey: "info -plist disk0")
        fixtures.removeValue(forKey: "info -plist disk6")
        let result = await DiskHealthReader(executor: DiskFixtureExecutor(replies: fixtures), smartctlURL: URL(fileURLWithPath: "/opt/homebrew/bin/smartctl")).read()
        XCTAssertEqual(result.disks.map(\.powerOnHours), [2488, 37877])
        XCTAssertEqual(result.disks.map(\.health), [.passed, .passed])
        XCTAssertEqual(result.disks.map(\.model), ["APPLE SSD", "External HDD"])
        XCTAssertEqual(result.disks.map(\.solidState), [true, false])
        XCTAssertTrue(result.disks.allSatisfy { $0.internalDisk == nil && $0.connection == nil })
    }

    private func replies() throws -> [String: CommandResult] {
        [
            "list -plist physical": try plist(["AllDisksAndPartitions": [
                ["DeviceIdentifier": "disk0", "Size": 1000, "Partitions": [["DeviceIdentifier": "disk0s2", "Content": "Apple_APFS"]]],
                ["DeviceIdentifier": "disk6", "Size": 2000, "Partitions": [["DeviceIdentifier": "disk6s2", "Content": "Apple_APFS"]]]
            ]]),
            "info -plist disk0": try plist(["DeviceIdentifier": "disk0", "WholeDisk": true, "MediaName": "APPLE SSD", "Internal": true, "SolidState": true, "TotalSize": 1000, "SMARTStatus": "Verified", "SerialNumber": "private-serial"]),
            "info -plist disk6": try plist(["DeviceIdentifier": "disk6", "WholeDisk": true, "MediaName": "External HDD", "Internal": false, "TotalSize": 2000, "SMARTStatus": "Not Supported", "FreeSpace": 0]),
            "apfs list -plist": try plist(["Containers": [
                ["ContainerReference": "disk3", "CapacityCeiling": 900, "CapacityFree": 400, "APFSContainerUUID": "private-uuid", "PhysicalStores": [["DeviceIdentifier": "disk0s2"]], "Volumes": [["Name": "Macintosh HD", "Roles": ["System"]], ["Name": "Data", "Roles": ["Data"]], ["Name": "Preboot", "Roles": ["Preboot"]]]],
                ["ContainerReference": "disk7", "CapacityCeiling": 1800, "CapacityFree": 50, "PhysicalStores": [["DeviceIdentifier": "disk6s2"]], "Volumes": [["Name": "External", "Roles": []]]]
            ]]),
            "-i -H -A -j /dev/disk0": .init(stdout: Data(#"{"smart_status":{"passed":true},"power_on_time":{"hours":2488},"model_name":"APPLE SSD","device":{"protocol":"NVMe"}}"#.utf8), stderr: Data(), exitCode: 0, duration: .zero),
            "-i -H -A -j /dev/disk6": .init(stdout: Data(#"{"smart_status":{"passed":true},"power_on_time":{"hours":37877},"model_name":"External HDD","rotation_rate":7200}"#.utf8), stderr: Data(), exitCode: 0, duration: .zero)
        ]
    }

    private func plist(_ value: [String: Any]) throws -> CommandResult {
        .init(stdout: try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0), stderr: Data(), exitCode: 0, duration: .zero)
    }
}

private actor DiskFixtureExecutor: CommandExecuting {
    let replies: [String: CommandResult]
    var requests: [CommandRequest] = []
    init(replies: [String: CommandResult]) { self.replies = replies }
    func run(_ request: CommandRequest) async throws -> CommandResult {
        requests.append(request)
        guard let reply = replies[request.arguments.joined(separator: " ")] else { throw CommandExecutionError.timedOut }
        return reply
    }
}

private actor CountingDiskReader: DiskHealthReading {
    var count = 0
    func read() async -> DiskHealthSnapshot {
        count += 1
        try? await Task.sleep(for: .milliseconds(30))
        return .init(disks: [], observedAt: Date(), error: nil)
    }
}
