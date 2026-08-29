import XCTest

@testable import ContainerGUI

final class AppVersionTests: XCTestCase {
    func testCurrentVersionReflectsThisUpdate() {
        XCTAssertEqual(AppVersion.current, "2.1.0")
    }
}
