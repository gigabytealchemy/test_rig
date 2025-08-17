import XCTest

final class TestRigUITests: XCTestCase {
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        // Smoke check: app launches without crashing.
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground)
    }
}
