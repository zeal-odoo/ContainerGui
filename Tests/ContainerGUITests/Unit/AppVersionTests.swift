import XCTest

@testable import ContainerGUI

final class AppVersionTests: XCTestCase {
    func testCurrentVersionReflectsThisUpdate() {
        XCTAssertEqual(AppVersion.current, "0.2.0")
    }
}
