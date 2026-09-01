import Foundation
import XCTest

final class PackageAssetsTests: XCTestCase {
    func testPackageBuilderStagesVersionedArm64RuntimeAndChecksum() throws {
        let builder = try asset("scripts/build-pkg.sh")

        XCTAssertTrue(builder.contains("ContainerGUI-$app_version-$architecture.pkg"))
        XCTAssertTrue(builder.contains("versions/$app_version"))
        XCTAssertTrue(builder.contains("ContainerGUI_ContainerGUI.bundle"))
        XCTAssertTrue(builder.contains("pkgbuild"))
        XCTAssertTrue(builder.contains("productbuild"))
        XCTAssertTrue(builder.contains("shasum -a 256"))
        XCTAssertTrue(builder.contains("CONTAINER_GUI_INSTALLER_IDENTITY"))
        XCTAssertTrue(builder.contains("--scratch-path"))
        XCTAssertTrue(builder.contains("-file-prefix-map"))
        XCTAssertTrue(builder.contains("strip -S"))
        XCTAssertTrue(builder.contains("codesign --verify --strict"))
        XCTAssertTrue(builder.contains("xattr -cr"))
        XCTAssertFalse(builder.contains("/Users/mingliu"))

        let distribution = try asset("packaging/Distribution.xml")
        XCTAssertTrue(distribution.contains("hostArchitectures=\"arm64\""))
        XCTAssertTrue(distribution.contains("<os-version min=\"26.0\"/>"))
        XCTAssertTrue(distribution.contains("io.github.zeal-odoo.container-gui"))
    }

    func testPackageEnablesOnlyTheLoggedInUserWithBoundedBootstrapRetry() throws {
        let enable = try asset("packaging/bin/container-gui-enable")
        let postinstall = try asset("packaging/pkg-scripts/postinstall")

        XCTAssertTrue(enable.contains("/dev/console"))
        XCTAssertTrue(enable.contains("NFSHomeDirectory"))
        XCTAssertTrue(enable.contains("gui/$user_id"))
        XCTAssertTrue(enable.contains("bootstrap_with_retry"))
        XCTAssertTrue(enable.contains("for attempt_number in 1 2 3 4 5"))
        XCTAssertTrue(enable.contains("http://127.0.0.1:8787/api/v1"))
        XCTAssertFalse(enable.contains("0.0.0.0"))
        XCTAssertFalse(enable.contains("/Users/mingliu"))
        XCTAssertTrue(postinstall.contains("container-gui-enable --allow-no-user"))
    }

    func testPackageUninstallerUsesOnlyExactOwnedTargets() throws {
        let uninstaller = try asset("packaging/bin/container-gui-uninstall")

        XCTAssertTrue(uninstaller.contains("io.github.zeal-odoo.container-gui"))
        XCTAssertTrue(uninstaller.contains("/Library/Application Support/ContainerGUI"))
        XCTAssertTrue(uninstaller.contains("com.msj.container-gui"))
        XCTAssertFalse(uninstaller.contains("$HOME"))
        XCTAssertFalse(uninstaller.contains("/Users/mingliu"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func asset(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
