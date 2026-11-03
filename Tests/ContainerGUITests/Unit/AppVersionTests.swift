import XCTest

@testable import ContainerGUI

final class AppVersionTests: XCTestCase {
    func testCurrentVersionReflectsThisUpdate() {
        XCTAssertEqual(AppVersion.current, "2.27.0")
    }
}
