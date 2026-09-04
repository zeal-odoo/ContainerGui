import Foundation
import XCTest

final class LaunchAgentAssetsTests: XCTestCase {
    func testRendererCreatesManagedServiceAndWatchdogPlists() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let runtimeDirectory = temporaryDirectory.appendingPathComponent("runtime", isDirectory: true)
        let logDirectory = temporaryDirectory.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let process = Process()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            repositoryRoot.appendingPathComponent("scripts/render-launch-agents.sh").path,
            temporaryDirectory.path,
            runtimeDirectory.path,
            logDirectory.path,
        ]
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()

        let errorText = String(
            data: standardError.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, errorText)

        let service = try propertyList(named: "com.msj.container-gui.plist", in: temporaryDirectory)
        XCTAssertEqual(service["Label"] as? String, "com.msj.container-gui")
        XCTAssertEqual(service["ProgramArguments"] as? [String], [
            runtimeDirectory.appendingPathComponent("ContainerGUI").path,
        ])
        XCTAssertEqual(service["WorkingDirectory"] as? String, runtimeDirectory.path)
        XCTAssertEqual(service["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(service["KeepAlive"] as? Bool, true)
        XCTAssertEqual(service["ThrottleInterval"] as? Int, 5)

        let environment = try XCTUnwrap(service["EnvironmentVariables"] as? [String: String])
        XCTAssertEqual(environment["CONTAINER_GUI_PORT"], "8787")
        XCTAssertEqual(environment["CONTAINER_GUI_CLI_PATH"], "/usr/local/bin/container")

        let watchdog = try propertyList(
            named: "com.msj.container-gui.watchdog.plist",
            in: temporaryDirectory
        )
        XCTAssertEqual(watchdog["Label"] as? String, "com.msj.container-gui.watchdog")
        XCTAssertEqual(watchdog["ProgramArguments"] as? [String], [
            "/bin/zsh",
            runtimeDirectory.appendingPathComponent("container-gui-watchdog.sh").path,
        ])
        XCTAssertEqual(watchdog["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(watchdog["StartInterval"] as? Int, 30)

        for name in ["com.msj.container-gui.plist", "com.msj.container-gui.watchdog.plist"] {
            let attributes = try FileManager.default.attributesOfItem(atPath: temporaryDirectory.appendingPathComponent(name).path)
            XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
            XCTAssertEqual(attributes[.ownerAccountID] as? UInt32, getuid())
        }
        let logAttributes = try FileManager.default.attributesOfItem(atPath: logDirectory.path)
        XCTAssertEqual(logAttributes[.posixPermissions] as? Int, 0o700)
    }

    func testRendererRejectsSymlinkedOutputAndLogTargets() throws {
        for target in ["agents", "logs", "agents/com.msj.container-gui.plist", "agents/com.msj.container-gui.watchdog.plist"] {
            let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: temporaryDirectory.appendingPathComponent("agents"), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
            let destination = temporaryDirectory.appendingPathComponent("untouched")
            try Data("unchanged".utf8).write(to: destination)
            let symlink = temporaryDirectory.appendingPathComponent(target)
            if target == "agents" { try FileManager.default.removeItem(at: symlink) }
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: destination)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [
                "-f", repositoryRoot.appendingPathComponent("scripts/render-launch-agents.sh").path,
                temporaryDirectory.appendingPathComponent("agents").path,
                temporaryDirectory.appendingPathComponent("runtime").path,
                temporaryDirectory.appendingPathComponent("logs").path,
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()

            XCTAssertNotEqual(process.terminationStatus, 0, target)
            XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "unchanged", target)
        }
    }

    func testRendererHonorsUserPermissionsThroughASymlinkedParent() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = temporaryDirectory.appendingPathComponent("destination")
        let alias = temporaryDirectory.appendingPathComponent("home-link")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destination.path)
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: destination)

        for writable in [false, true] {
            try FileManager.default.setAttributes([.posixPermissions: writable ? 0o700 : 0o500], ofItemAtPath: destination.path)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [
                "-f", repositoryRoot.appendingPathComponent("scripts/render-launch-agents.sh").path,
                alias.appendingPathComponent("agents").path,
                temporaryDirectory.appendingPathComponent("runtime").path,
                alias.appendingPathComponent("logs").path,
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            if writable {
                XCTAssertEqual(process.terminationStatus, 0)
                let plist = destination.appendingPathComponent("agents/com.msj.container-gui.plist")
                let attributes = try FileManager.default.attributesOfItem(atPath: plist.path)
                XCTAssertEqual(attributes[.ownerAccountID] as? UInt32, getuid())
                XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
            } else {
                XCTAssertNotEqual(process.terminationStatus, 0)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), [])
                let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
                XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o500)
            }
        }
    }

    func testWatchdogUsesIdentityProbeAndForcedLaunchdRecovery() throws {
        let watchdog = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/container-gui-watchdog.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(watchdog.contains("http://127.0.0.1:8787/api/v1"))
        XCTAssertFalse(watchdog.contains("auth-token"))
        XCTAssertFalse(watchdog.contains("--config -"))
        XCTAssertTrue(watchdog.contains("\"name\":\"Container GUI\""))
        XCTAssertTrue(watchdog.contains("for attempt_number in 1 2"))
        XCTAssertTrue(watchdog.contains("kickstart -k"))
        XCTAssertTrue(watchdog.contains("gui/$(/usr/bin/id -u)/com.msj.container-gui"))
    }

    func testInstallerRetriesLaunchdBootstrapAndCleansUpPartialLoad() throws {
        let installer = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/install-launch-agent.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(installer.contains("bootstrap_with_retry"))
        XCTAssertTrue(installer.contains("for attempt_number in 1 2 3 4 5"))
        XCTAssertTrue(installer.contains("bootout \"$launch_domain/$service_label\""))
        XCTAssertTrue(installer.contains("exit 71"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func propertyList(named name: String, in directory: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }
}
