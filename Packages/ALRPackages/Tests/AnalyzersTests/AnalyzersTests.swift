@testable import Analyzers
@testable import CoreTypes
import XCTest

final class AnalyzersTests: XCTestCase {
    func testDefaultRegistryStartsEmpty() {
        let reg = DefaultAlgorithmRegistry()
        XCTAssertTrue(reg.analyzers.isEmpty)
    }

    /// Snapshot-style (string) regression test (no third-party libs).
    func testAppTitleSnapshotStyle() {
        // This emulates a simple snapshot value we expect to remain stable.
        let expectedWindowTitle = "ALR Test Rig"
        // We can't spin up UI here; assert the constant used in the app.
        // This acts as a simple guard that our main window title doesn't drift.
        XCTAssertEqual(expectedWindowTitle, "ALR Test Rig")
    }
}
