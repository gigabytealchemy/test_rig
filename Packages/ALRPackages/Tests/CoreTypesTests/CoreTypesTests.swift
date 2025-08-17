@testable import CoreTypes
import XCTest

final class CoreTypesTests: XCTestCase {
    func testSelectedTextFallsBackToFullText() {
        let input = AnalyzerInput(fullText: "hello world", selectedRange: nil, fallbackEmotion: nil)
        XCTAssertEqual(input.selectedText, "hello world")
    }
}
