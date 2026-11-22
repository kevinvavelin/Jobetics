import XCTest

/// Used by scripts/screenshots.sh: rotates the iPad simulator to landscape before capturing,
/// since `simctl` has no rotation command. The orientation persists after the test ends.
final class OrientationHelper: XCTestCase {
    func testRotateToLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(XCUIDevice.shared.orientation, .landscapeLeft)
    }
}
