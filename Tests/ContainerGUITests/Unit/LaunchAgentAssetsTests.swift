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
