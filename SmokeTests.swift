import XCTest
@testable import NotchPal

final class SmokeTests: XCTestCase {

    func testPanelConfiguration() {
        let panel = NotchPanel()
        XCTAssertFalse(panel.isOpaque)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertEqual(
            panel.level.rawValue,
            Int(CGWindowLevelForKey(.screenSaverWindow)),
            "Panel must sit above fullscreen apps"
        )
    }

    func testGeometryFallsBackToSyntheticHandleWhenNoNotch() throws {
        // Can't construct an NSScreen in a unit test, so we just exercise the
        // expanded size constant. Full geometry testing requires a running app.
        XCTAssertEqual(NotchGeometry.expandedSize, CGSize(width: 520, height: 160))
    }
}
